export function reviewAlert(status) {
  if (!status?.current || status.stage === "complete") return null;
  const current = status.current;
  if (["ready", "updated"].includes(status.stage))
    return {
      id: `revision:${current.artifactId}:${current.revision}`,
      title: "A new review is ready",
      url: current.url,
      createdAt: current.publishedAt,
    };
  return null;
}

export function createReviewAlerts({
  window: host,
  button,
  sessionId,
  plan,
  open,
}) {
  const prefix = `interactive-plan:alerts:${sessionId}:`;
  const memory = new Map();
  let latest = null,
    requesting = false,
    failed = false;
  const permission = () =>
    sessionId &&
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
    host.navigator.locks
      ? host.navigator.locks.request(prefix + "delivery", action)
      : action();
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
          : "Notifications for new reviews. Keep this tab open.";
  }
  function enable() {
    write("enabledAt", String(Date.now()));
    const current = reviewAlert(latest);
    if (current) write(current.id, "handled");
    write("enabled", "yes");
  }
  async function update(status = latest) {
    latest = status;
    const alert = reviewAlert(status);
    host.document.title = alert ? `${alert.title} · ${plan.title}` : plan.title;
    await serialize(() => {
      if (
        permission() === "granted" &&
        read("enabled") !== "no" &&
        !read("enabledAt")
      )
        enable();
      if (
        !alert ||
        permission() !== "granted" ||
        read("enabled") !== "yes" ||
        failed
      )
        return;
      if (read(alert.id) || reviewAlert(latest)?.id !== alert.id) return;
      if (
        alert.createdAt &&
        Date.parse(alert.createdAt) <= Number(read("enabledAt"))
      ) {
        write(alert.id, "handled");
        return;
      }
      try {
        const item = new host.Notification(alert.title, {
          body: plan.title,
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
  controls();
  return { update };
}
