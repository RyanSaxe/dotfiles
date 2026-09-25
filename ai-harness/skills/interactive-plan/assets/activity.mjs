export function activityModel({
  remote,
  currentSet,
  submittedRevision,
  inFlight = false,
  now = Date.now(),
}) {
  // acknowledgedAt survives from earlier rounds, so only the ids say whether
  // the agent has read this submission.
  const acknowledged =
    Boolean(remote?.latestSubmissionId) &&
    remote.lastAcknowledgedId === remote.latestSubmissionId;
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
          : acknowledged
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
  else if (!acknowledged)
    footer = { mark: "queued", text: "No agent report yet" };
  else if (finished)
    footer = {
      mark: "complete",
      text: "Finished",
      at: remote.current?.publishedAt,
    };
  else if (!slots.length)
    footer = {
      mark: "active",
      text: "Agent read your feedback",
      at: remote.acknowledgedAt,
      late: late(remote.acknowledgedAt),
    };
  else
    footer = {
      mark: "active",
      text: "Last report",
      at: remote.updatedAt,
      late: late(remote.updatedAt),
    };
  // Until the page list exists, the bar is one track that moves while the
  // agent works on the feedback.
  const track = slots.length
    ? null
    : inFlight || (acknowledged && !stopped)
      ? "moving"
      : "still";
  return { slots, ready, failed, stopped, title, summary, footer, track };
}
