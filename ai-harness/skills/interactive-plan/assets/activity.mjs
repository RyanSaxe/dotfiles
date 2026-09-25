export function activityModel({
  remote,
  currentSet,
  submittedRevision,
  inFlight = false,
  now = Date.now(),
}) {
  // Timestamps survive from earlier rounds, so only the ids say whether the
  // agent has this submission: ack receives it, and read receives and reads it.
  const latest = remote?.latestSubmissionId;
  const read = Boolean(latest) && remote.lastAcknowledgedId === latest;
  const received =
    read || (Boolean(latest) && remote.lastReceivedId === latest);
  // The agent's last report, and the note it gave with ack. State saved
  // before reports existed has only acknowledgedAt and updatedAt.
  const reportAt = remote?.report?.at;
  const note = remote?.report?.note;
  const failed = remote?.wake?.last?.ok === false;
  const paused = Boolean(remote?.paused);
  const stopped = failed || paused;
  const slots = remote?.pageRound
    ? [
        { id: "agreed", title: "Agreed so far", state: "ready" },
        ...remote.pageRound.pages,
      ]
    : remote?.current?.revision !== submittedRevision
      ? currentSet?.pages || []
      : [];
  const ready = slots.filter((item) => item.state === "ready").length;
  const finished = slots.length > 0 && ready === slots.length;
  const title = inFlight
    ? "Sending feedback"
    : stopped
      ? "Agent needs attention"
      : finished
        ? "All pages ready"
        : slots.length
          ? "Pages in progress"
          : received
            ? "Preparing the next revision"
            : "Waiting for the agent";
  const summary = inFlight
    ? "Saving your comments"
    : slots.length
      ? `${ready} of ${slots.length} pages ready`
      : "Feedback saved";
  const late = (at) => Boolean(at) && now - Date.parse(at) >= 300000;
  // The footer always has a mark and a line, so the card keeps its shape
  // from Submit to the last page. The frame shows `at` as a relative time.
  let footer;
  if (inFlight) footer = { mark: "active", text: "Saving your feedback" };
  else if (failed)
    footer = {
      mark: "stopped",
      text: "Could not wake the agent. Send a message in chat.",
      late: true,
    };
  else if (paused)
    footer = {
      mark: "stopped",
      text: `Agent paused${remote.paused.reason ? `: ${remote.paused.reason}.` : "."} Send a message in chat.`,
      late: true,
    };
  else if (!received) footer = { mark: "queued", text: "No agent report yet" };
  else if (finished)
    footer = {
      mark: "complete",
      text: "Finished",
      at: remote.current?.publishedAt,
    };
  else if (note)
    footer = {
      mark: "active",
      text: note,
      note: true,
      at: reportAt,
      late: late(reportAt),
    };
  else if (!slots.length) {
    const at = reportAt || remote.acknowledgedAt;
    footer = {
      mark: "active",
      text: read ? "Agent read your feedback" : "Agent received your feedback",
      at,
      late: late(at),
    };
  } else {
    const at = reportAt || remote.updatedAt;
    footer = { mark: "active", text: "Last report", at, late: late(at) };
  }
  // Until the page list exists, the bar is one track that moves while the
  // agent works on the feedback.
  const track = slots.length
    ? null
    : inFlight || (received && !stopped)
      ? "moving"
      : "still";
  return { slots, ready, failed, stopped, title, summary, footer, track };
}

// While a revision's pages are still arriving, the Pages heading says so, so
// dim names never sit there without a sign of the agent. The page round
// exists only until the last page publishes.
export function roundModel({ remote, now = Date.now() }) {
  const round = remote?.pageRound;
  if (!round) return null;
  const total = round.pages.length + 1;
  const ready = 1 + round.pages.filter((item) => item.state === "ready").length;
  if (ready === total) return null;
  if (remote.paused) return { text: "Agent paused", late: true };
  const reported = remote.report?.at || remote.updatedAt;
  const minutes = Math.floor((now - Date.parse(reported)) / 60000);
  if (minutes >= 5) return { text: `No report for ${minutes} min`, late: true };
  return { text: `${ready} of ${total} ready`, late: false };
}
