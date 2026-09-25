export function reviewAlert(entry) {
  if (!entry?.needsYou || !entry.id || !entry.revision) return null;
  const plan = entry.kind === "plan";
  return {
    id: `${plan ? "plan" : "revision"}:${entry.id}:${entry.revision}`,
    sessionId: entry.id,
    title: plan
      ? "A final plan is ready"
      : `Revision ${entry.revision} is ready`,
    body: entry.title || "",
    url: entry.url,
    createdAt: entry.publishedAt,
  };
}

// One permission and one enabled switch for the hub origin. Alerts are keyed
// per session and revision so several tabs never announce the same event, and
// the session shown in the focused tab is never announced.
export function createReviewAlerts({ window: host, button, sessionId, open }) {
  const prefix = "interactive-plan:alerts:";
  const memory = new Map();
  let latest = [],
    requesting = false,
    failed = false;
  const permission = () =>
    host.isSecureContext &&
    /^https?:$/.test(host.location.protocol) &&
    typeof host.Notification === "function"
      ? host.Notification.permission
      : "unavailable";
  const read = (key) => {
    try {
      return host.localStorage.getItem(prefix + key) || memory.get(key);
    } catch {
      return memory.get(key);
    }
  };
  const write = (key, value) => {
    memory.set(key, value);
    try {
      host.localStorage.setItem(prefix + key, value);
    } catch {
      /* Keep a usable preference when browser storage is unavailable. */
    }
  };
  const serialize = (action) =>
    host.navigator?.locks
      ? host.navigator.locks.request(prefix + "delivery", action)
      : action();
  const focused = () => {
    if (!sessionId) return;
    if (host.document.hasFocus()) write("focused", sessionId);
    else if (read("focused") === sessionId) write("focused", "");
  };
  function controls() {
    const state = permission();
    button.disabled =
      requesting || ["unavailable", "denied"].includes(state) || failed;
    button.textContent =
      state === "unavailable" || failed
        ? "Notifications unavailable"
        : state === "denied"
          ? "Notifications blocked"
          : read("enabled") === "yes" && state === "granted"
            ? "Disable notifications"
            : "Enable notifications";
    button.title =
      state === "denied"
        ? "Allow notifications in your browser's site settings."
        : failed
          ? "Notification delivery failed. Check browser and OS settings."
          : "Alerts when a revision or final plan is ready in any session.";
  }
  function enable() {
    write("enabledAt", String(Date.now()));
    for (const entry of latest) {
      const alert = reviewAlert(entry);
      if (alert) write(alert.id, "handled");
    }
    write("enabled", "yes");
  }
  async function update(entries = latest) {
    latest = Array.isArray(entries) ? entries : [];
    await serialize(() => {
      if (
        permission() === "granted" &&
        read("enabled") !== "no" &&
        !read("enabledAt")
      )
        enable();
      if (permission() !== "granted" || read("enabled") !== "yes" || failed)
        return;
      for (const entry of latest) {
        const alert = reviewAlert(entry);
        if (!alert || read(alert.id)) continue;
        if (
          read("focused") === alert.sessionId ||
          (alert.createdAt &&
            Date.parse(alert.createdAt) <= Number(read("enabledAt")))
        ) {
          write(alert.id, "handled");
          continue;
        }
        try {
          const item = new host.Notification(alert.title, {
            body: alert.body,
            tag: prefix + alert.id,
          });
          write(alert.id, "handled");
          item.onclick = () => {
            item.close();
            host.focus();
            open(alert.url);
          };
          item.onerror = () => {
            failed = true;
            controls();
          };
        } catch {
          failed = true;
        }
      }
    });
    controls();
  }
  button.onclick = async () => {
    if (read("enabled") === "yes" && permission() === "granted") {
      await serialize(() => write("enabled", "no"));
      controls();
      return;
    }
    requesting = true;
    controls();
    try {
      const result =
        permission() === "granted"
          ? "granted"
          : await host.Notification.requestPermission();
      if (result === "granted") await serialize(enable);
    } catch {
      failed = true;
    }
    requesting = false;
    controls();
  };
  host.addEventListener("storage", (event) => {
    if (event.key?.startsWith(prefix)) void update();
  });
  host.addEventListener("focus", focused);
  host.addEventListener("blur", focused);
  focused();
  controls();
  return { update };
}
