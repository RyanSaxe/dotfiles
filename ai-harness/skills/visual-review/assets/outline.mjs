/**
 * The models behind the top bar and the thread: polled state in, the stepper
 * and the question rows out.
 *
 * Kept separate from the DOM so the page states and the status readings are
 * decided in one place and can be checked without a browser.
 */

/**
 * A page carries independent facts rather than one state name: it can be the
 * page being read, already written, the one the agent is writing next, and
 * revised since the reader first saw it, in any combination.
 */
export function stepperPills(state, view = {}) {
  const question = (state.questions ?? []).find(
    (entry) => entry.id === view.questionId,
  );
  if (!question) return [];
  const firstPlanned = question.pages.find((page) => page.status === "planned");
  const writing =
    question.status === "writing" || question.status === "planned";
  return question.pages.map((page, index) => ({
    id: page.id,
    n: index + 1,
    title: page.title,
    written: page.status === "written",
    current: page.id === view.pageId,
    writing: writing && page.id === firstPlanned?.id,
    updated: (page.revision ?? 0) > 1,
  }));
}

/** One line under a question in the thread: asked, writing, or the page count. */
export function statusLine(question) {
  const total = question.pages.length;
  const pages = `${total} page${total === 1 ? "" : "s"}`;
  if (question.status === "asked") return "asked";
  if (question.status === "done") return pages;
  const detail = question.statusLine ? ` · ${question.statusLine}` : "";
  return total ? `${pages} · writing${detail}` : `planning${detail}`;
}

/**
 * Waiting, the agent polls every second; working, it reads code for minutes
 * between commands. Five minutes of silence means it is gone.
 */
const AGENT_SILENCE = 5 * 60_000;

/** Whether an agent has spoken to the helper within the last five minutes. */
export function agentListening(state, now = Date.now()) {
  return (
    Boolean(state.agentSeenAt) &&
    now - Date.parse(state.agentSeenAt) < AGENT_SILENCE
  );
}

/**
 * The thread's rows, in the order the questions were asked.
 *
 * `now` is null for an export, where no agent is expected; live, an
 * unfinished question with no agent listening says so instead of spinning.
 */
export function threadRows(state, view = {}, now = Date.now()) {
  const listening = now === null || agentListening(state, now);
  return (state.questions ?? []).map((question) => {
    const done = question.status === "done";
    return {
      id: question.id,
      text: question.text,
      title: question.title,
      status: question.status,
      line: done || listening ? statusLine(question) : "no agent listening",
      working: !done && listening,
      current: question.id === view.questionId,
      firstPage:
        question.pages.find((page) => page.status === "written")?.id ?? null,
    };
  });
}

/** Which page ] and [ move to, within the question the reader is in. */
export function neighbors(state, questionId, pageId) {
  const question = (state.questions ?? []).find(
    (entry) => entry.id === questionId,
  );
  const pages =
    question?.pages.filter((page) => page.status === "written") ?? [];
  const index = pages.findIndex((page) => page.id === pageId);
  return {
    pages,
    index,
    previous: index > 0 ? pages[index - 1] : null,
    next: index >= 0 && index < pages.length - 1 ? pages[index + 1] : null,
  };
}

/** The page to show when the reader has not chosen one, or theirs disappeared. */
export function defaultPage(state, questionId) {
  const question =
    (state.questions ?? []).find((entry) => entry.id === questionId) ??
    (state.questions ?? []).at(-1);
  if (!question) return null;
  const written = question.pages.find((page) => page.status === "written");
  return written ? { questionId: question.id, pageId: written.id } : null;
}
