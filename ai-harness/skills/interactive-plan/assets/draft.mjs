const record = (value) =>
  Boolean(value) && typeof value === "object" && !Array.isArray(value);
const filterValues = (object, keep) =>
  Object.fromEntries(Object.entries(object).filter(([, value]) => keep(value)));
const mapValues = (object, fn) =>
  Object.fromEntries(
    Object.entries(object).map(([key, value]) => [key, fn(value)]),
  );

export function emptyDraft(revision, worksetId = undefined) {
  return {
    revision,
    ...(worksetId ? { worksetId } : {}),
    notes: [],
    choices: {},
    answers: {},
    noteDrafts: {},
    submitted: null,
    pending: null,
  };
}

// The remembered reading place is keyed by session, not revision. A record
// written under an earlier revision, or one naming a page this revision no
// longer has, would land the reader somewhere arbitrary, so it is dropped.
export function usablePlace(saved, revision, pageIds) {
  if (!record(saved) || saved.revision !== revision) return null;
  if (!pageIds.includes(saved.page)) return null;
  const top = Number(saved.top);
  return { page: saved.page, top: Number.isFinite(top) && top > 0 ? top : 0 };
}

// Drafts are keyed by session and artifact, not revision. When a new revision
// lands, items that were already sent are dropped and unsent items carry over.
export function loadDraft(
  saved,
  revision,
  worksetId = undefined,
  versions = {},
) {
  if (!record(saved) || !Array.isArray(saved.notes) || !record(saved.choices))
    return emptyDraft(revision, worksetId);
  const draft = {
    ...emptyDraft(revision, worksetId),
    ...saved,
    answers: record(saved.answers) ? saved.answers : {},
    noteDrafts: record(saved.noteDrafts) ? saved.noteDrafts : {},
  };
  const identityChanged =
    saved.revision !== revision ||
    (worksetId !== undefined && (saved.worksetId || null) !== worksetId);
  const pageVersionChanged =
    worksetId !== undefined &&
    [
      ...draft.notes,
      ...Object.values(draft.choices),
      ...Object.values(draft.answers),
    ].some(
      (item) =>
        item.topic !== "overall" && item.pageVersion !== versions[item.topic],
    );
  if (identityChanged || pageVersionChanged) {
    const current = (item) =>
      !item.sentIn &&
      (item.topic === "overall" ||
        (worksetId === undefined && !item.pageVersion) ||
        versions[item.topic] === item.pageVersion);
    draft.notes = draft.notes.filter(current);
    draft.choices = filterValues(draft.choices, current);
    draft.answers = filterValues(draft.answers, current);
    draft.submitted = null;
    draft.pending = null;
    draft.revision = revision;
    if (worksetId) draft.worksetId = worksetId;
    else delete draft.worksetId;
  }
  return draft;
}

// A checklist counts only once the reviewer touched it; an untouched list is
// still sent with the round so the agent has its defaults.
const counted = (choice) =>
  !choice.sentIn && (choice.kind !== "multiple" || choice.touched === true);

export function unsentItems(draft) {
  const notes = draft.notes.filter((note) => !note.sentIn);
  const choices = filterValues(draft.choices, counted);
  const answers = filterValues(draft.answers, (answer) => !answer.sentIn);
  return {
    notes,
    choices,
    answers,
    count:
      notes.length + Object.keys(choices).length + Object.keys(answers).length,
  };
}

export function submissionGroups(draft) {
  const { notes, answers } = unsentItems(draft);
  const choices = filterValues(draft.choices, (choice) => !choice.sentIn);
  const strip = ({ sentIn, ...item }) => item;
  return {
    choices: mapValues(choices, strip),
    notes: notes.map(strip),
    ...(Object.keys(answers).length
      ? { answers: mapValues(answers, strip) }
      : {}),
  };
}

export function markSent(draft, id, at) {
  const { count } = unsentItems(draft);
  for (const note of draft.notes) note.sentIn ||= id;
  for (const choice of Object.values(draft.choices)) choice.sentIn ||= id;
  for (const answer of Object.values(draft.answers)) answer.sentIn ||= id;
  draft.submitted = { id, at, revision: draft.revision, count };
  draft.pending = null;
  return draft;
}
