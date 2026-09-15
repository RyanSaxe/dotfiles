export function reviewAlert(status, plan) {
  if (!status?.current || status.stage === "complete") return null;
  const current = status.current;
  if (status.stage === "needs_reply" && status.question)
    return {
      id: `question:${status.question.id}`,
      title: "The agent has a question",
      url: `${current.url}#feedback`,
      viewed:
        current.artifactId === plan.artifactId &&
        current.revision === plan.revision,
      question: true,
    };
  if (["ready", "updated"].includes(status.stage))
    return {
      id: `revision:${current.artifactId}:${current.revision}`,
      title: "A new review is ready",
      url: current.url,
      viewed:
        current.artifactId === plan.artifactId &&
        current.revision === plan.revision,
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
  const document = host.document;
  const prefix = `interactive-plan:alerts:${sessionId}:`;
  const memory = new Map();
  let latest = null,
    notification = null,
    requesting = false,
    failed = false;
  const supported = () =>
    sessionId &&
    host.isSecureContext &&
    /^https?:$/.test(host.location.protocol) &&
    typeof host.Notification === "function";
  const permission = () =>
    supported() ? host.Notification.permission : "unavailable";
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
      /* Memory and notification tags still limit duplicate alerts. */
    }
  };
  function controls() {
    const state = permission();
    const enabled = read("enabled") === "yes";
    button.disabled =
      requesting || state === "unavailable" || state === "denied" || failed;
    button.textContent =
      state === "unavailable"
        ? "Notifications unavailable"
        : state === "denied"
          ? "Notifications blocked"
          : failed
            ? "Notifications unavailable"
            : enabled && state === "granted"
              ? "Disable notifications"
              : "Enable notifications";
    button.title =
      state === "denied"
        ? "Allow notifications in your browser's site settings. The tab title still shows updates."
        : failed || state === "unavailable"
          ? "The tab title still shows updates. Desktop alerts require a supported browser and a live session."
          : "Desktop alerts for new reviews and questions. Keep this tab open.";
  }
  async function update(status = latest) {
    latest = status;
    controls();
    const alert = reviewAlert(status, plan);
    if (!alert) {
      document.title = plan.title;
      notification?.close();
      notification = null;
      return;
    }
    const focused = !document.hidden && document.hasFocus();
    const viewed =
      alert.viewed && (!alert.question || host.location.hash === "#feedback");
    if (focused && viewed) write(alert.id, "seen");
    document.title =
      read(alert.id) === "seen" ? plan.title : `${alert.title} · ${plan.title}`;
    if (read(alert.id) === "seen") {
      notification?.close();
      notification = null;
      return;
    }
    if (
      focused ||
      permission() !== "granted" ||
      read("enabled") !== "yes" ||
      failed
    )
      return;
    const deliver = () => {
      if (
        read(alert.id) ||
        reviewAlert(latest, plan)?.id !== alert.id ||
        permission() !== "granted" ||
        read("enabled") !== "yes" ||
        failed ||
        (!document.hidden && document.hasFocus())
      )
        return;
      try {
        notification?.close();
        const item = new host.Notification(alert.title, {
          body: plan.title,
          tag: `${prefix}${alert.id}`,
        });
        notification = item;
        write(alert.id, "sent");
        item.onclick = () => {
          item.close();
          host.focus();
          const active = reviewAlert(latest, plan);
          if (active) open(active.url);
        };
        item.onerror = () => {
          failed = true;
          controls();
        };
      } catch {
        failed = true;
        controls();
      }
    };
    // Serialize the storage check across tabs; tags provide a fallback without locks.
    try {
      if (host.navigator.locks)
        await host.navigator.locks.request(prefix + "delivery", deliver);
      else deliver();
    } catch {
      deliver();
    }
  }
  button.onclick = async () => {
    if (read("enabled") === "yes" && permission() === "granted") {
      write("enabled", "no");
      notification?.close();
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
      if (result === "granted") write("enabled", "yes");
    } catch {
      failed = true;
    }
    requesting = false;
    await update();
  };
  host.addEventListener("focus", () => void update());
  document.addEventListener("visibilitychange", () => void update());
  host.addEventListener("storage", (event) => {
    if (event.key?.startsWith(prefix)) void update();
  });
  controls();
  return { update };
}
