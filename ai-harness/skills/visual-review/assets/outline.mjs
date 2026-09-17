/**
 * The outline model: polled state in, the sidebar's shape out.
 *
 * Kept separate from the DOM so the ordering, the page states, and the
 * progress reading are decided in one place and can be checked without a
 * browser.
 */

/**
 * A page carries independent facts rather than one state name: it can be the
 * page being read, already written, the one the agent is writing next, and
 * revised since the reader last saw it, in any combination.
 */
function describePages(question, currentPageId) {
  const firstPlanned = question.pages.find((page) => page.status === "planned");
  const writing =
    question.status === "writing" || question.status === "planned";
  return question.pages.map((page) => ({
    id: page.id,
    title: page.title,
    written: page.status === "written",
    current: page.id === currentPageId,
    writing: writing && page.id === firstPlanned?.id,
    updated: (page.revision ?? 0) > 1,
  }));
}

export function outlineModel(state, view = {}) {
  const collapsed = view.collapsed ?? new Set();
  const questions = (state.questions ?? []).map((question) => {
    const open = !collapsed.has(question.id);
    const written = question.pages.filter((page) => page.status === "written");
    return {
      id: question.id,
      title: question.title,
      status: question.status,
      statusLine: question.statusLine,
      expanded: open,
      pageCount: question.pages.length,
      writtenCount: written.length,
      followUpCount: (question.followUps ?? []).length,
      pages: open ? describePages(question, view.pageId) : [],
    };
  });
  return { questions, progress: progressFor(state, view.questionId) };
}

/**
 * The bar and the line under it describe the question being written. When
 * every answer is finished there is nothing to report, and the region is empty
 * rather than showing a full bar nobody is waiting on.
 */
export function progressFor(state, preferredQuestionId) {
  const working = (state.questions ?? []).filter(
    (question) => question.status !== "done",
  );
  if (!working.length) return null;
  const question =
    working.find((entry) => entry.id === preferredQuestionId) ?? working[0];
  const total = question.pages.length;
  const written = question.pages.filter(
    (page) => page.status === "written",
  ).length;
  const next = question.pages.find((page) => page.status === "planned");
  return {
    questionId: question.id,
    written,
    total,
    fraction: total ? written / total : 0,
    label: next
      ? `Writing ${next.title} · ${Math.min(written + 1, total)} of ${total}`
      : total
        ? `${written} of ${total}`
        : "Planning",
    statusLine: question.statusLine ?? null,
  };
}

/** Which page h and l move to, within the question the reader is in. */
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
