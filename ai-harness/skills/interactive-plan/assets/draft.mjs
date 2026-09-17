const record = (value) =>
  Boolean(value) && typeof value === "object" && !Array.isArray(value);
const filterValues = (object, keep) =>
  Object.fromEntries(Object.entries(object).filter(([, value]) => keep(value)));
const mapValues = (object, fn) =>
  Object.fromEntries(
    Object.entries(object).map(([key, value]) => [key, fn(value)]),
  );

export function emptyDraft(revision) {
  return {
    revision,
    notes: [],
    choices: {},
    answers: {},
    noteDrafts: {},
    submitted: null,
    pending: null,
  };
}

// Drafts are keyed by session and artifact, not revision. When a new revision
// lands, items that were already sent are dropped and unsent items carry over.
export function loadDraft(saved, revision) {
  if (!record(saved) || !Array.isArray(saved.notes) || !record(saved.choices))
    return emptyDraft(revision);
  const draft = {
    ...emptyDraft(revision),
    ...saved,
    answers: record(saved.answers) ? saved.answers : {},
    noteDrafts: record(saved.noteDrafts) ? saved.noteDrafts : {},
  };
  if (saved.revision !== revision) {
    draft.notes = draft.notes.filter((note) => !note.sentIn);
    draft.choices = filterValues(draft.choices, (choice) => !choice.sentIn);
    draft.answers = filterValues(draft.answers, (answer) => !answer.sentIn);
    draft.submitted = null;
    draft.pending = null;
    draft.revision = revision;
  }
  return draft;
}

export function unsentItems(draft) {
  const notes = draft.notes.filter((note) => !note.sentIn);
  const choices = filterValues(draft.choices, (choice) => !choice.sentIn);
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
  const { notes, choices, answers } = unsentItems(draft);
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
