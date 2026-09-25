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
  const reportAt = acknowledged ? remote.updatedAt : null;
  let report = "";
  if (failed) report = "Could not wake the agent. Send a message in chat.";
  else if (paused)
    report = `Agent paused${remote.paused.reason ? `: ${remote.paused.reason}.` : "."} Send a message in chat.`;
  else if (!inFlight && !acknowledged) report = "No agent report yet";
  else if (!finished && reportAt && now - Date.parse(reportAt) >= 300000)
    report = "stale";
  return { slots, ready, failed, stopped, title, summary, report, reportAt };
}
