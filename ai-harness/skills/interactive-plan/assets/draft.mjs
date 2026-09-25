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
    alignUnflagged: true,
    notes: [],
    choices: {},
    answers: {},
    noteDrafts: {},
    submitted: null,
    pending: null,
  };
}

// Where the reader was in each revision, and which tab and past revision were
// on screen. A record from before places were kept per revision holds one
// revision's place, which is kept.
export function readPlaces(saved) {
  const places = {};
  const place = (value) => {
    const top = Number(value.top);
    return { page: value.page, top: Number.isFinite(top) && top > 0 ? top : 0 };
  };
  if (!record(saved)) return { tab: "current", past: null, places };
  if (typeof saved.revision === "string" && typeof saved.page === "string")
    places[saved.revision] = place(saved);
  if (record(saved.places))
    for (const [revision, value] of Object.entries(saved.places))
      if (record(value) && typeof value.page === "string")
        places[revision] = place(value);
  return {
    tab: saved.tab === "past" ? "past" : "current",
    past: typeof saved.past === "string" ? saved.past : null,
    places,
  };
}
// A remembered page that the revision no longer has is ignored.
export function placeFor(places, revision, pageIds) {
  const place = places[revision];
  return place && pageIds.includes(place.page) ? place : null;
}

// Drafts are keyed by session and artifact, not revision. When a new revision
// lands, items that were already sent are dropped and unsent items carry over.
export function loadDraft(saved, revision) {
  if (!record(saved) || !Array.isArray(saved.notes) || !record(saved.choices))
    return emptyDraft(revision);
  const draft = {
    ...emptyDraft(revision),
    ...saved,
    alignUnflagged:
      typeof saved.alignUnflagged === "boolean" ? saved.alignUnflagged : true,
    answers: record(saved.answers) ? saved.answers : {},
    noteDrafts: record(saved.noteDrafts) ? saved.noteDrafts : {},
  };
  if (saved.revision !== revision) {
    draft.notes = draft.notes.filter((note) => !note.sentIn);
    draft.choices = filterValues(draft.choices, (choice) => !choice.sentIn);
    draft.answers = filterValues(draft.answers, (answer) => !answer.sentIn);
    draft.submitted = null;
    draft.pending = null;
    draft.acceptance = null;
    draft.acceptGuidance = "";
    draft.revision = revision;
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
    alignUnflagged: draft.alignUnflagged,
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
