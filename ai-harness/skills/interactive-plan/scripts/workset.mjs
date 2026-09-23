import crypto from "node:crypto";

const idPattern = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$/;

const copy = (value) => JSON.parse(JSON.stringify(value));
const escapeHtml = (value) =>
  String(value).replace(
    /[&<>"']/g,
    (character) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
      })[character],
  );

export function pageVersion() {
  return `pv-${crypto.randomBytes(12).toString("hex")}`;
}

export function pendingPageHtml(page, workset) {
  return `<section class="workset-pending" data-workset-pending="${escapeHtml(workset.id)}" data-page-id="${escapeHtml(page.id)}"><h2>Waiting for ${escapeHtml(page.title)}</h2><p>This page is part of the ${escapeHtml(workset.title)} work set. It will become available after its page checks and publication gate pass.</p><p class="muted">Other pages can be reviewed while this page is pending.</p></section>`;
}

export function declareWorkset(
  artifact,
  id = `ws-${crypto.randomUUID()}`,
  now = new Date().toISOString(),
) {
  if (!idPattern.test(id)) throw new Error("Invalid work-set ID");
  const authoredAgreed = artifact.pages.find((page) => page.id === "agreed");
  const pages = [
    {
      id: "agreed",
      title: authoredAgreed?.title || "Agreed so far",
      order: 0,
      state: "ready",
      version: pageVersion(),
      renderVerified: true,
    },
    ...artifact.pages
      .filter((page) => page.id !== "agreed")
      .map((page, index) => ({
        id: page.id,
        title: page.title,
        order: index + 1,
        state: "pending",
      })),
  ];
  return {
    id,
    artifactId: artifact.artifactId,
    title: artifact.title,
    declared: pages,
    readyCount: 1,
    declaredCount: pages.length,
    updatedAt: now,
  };
}

export function readiness(workset) {
  const declared = workset.declared || [];
  const ready = declared.filter((page) => page.state === "ready");
  return {
    readyCount: ready.length,
    declaredCount: declared.length,
    complete: ready.length === declared.length && declared.length > 0,
  };
}

export function pageEntry(workset, pageId) {
  return (workset.declared || []).find((page) => page.id === pageId) || null;
}

export function pageVersions(workset) {
  return (workset.declared || [])
    .filter((page) => page.state === "ready" && page.version)
    .sort((a, b) => a.order - b.order)
    .map(({ id, version }) => ({ pageId: id, version }));
}

export function manifestFor(workset) {
  const result = pageVersions(workset);
  const readinessState = readiness(workset);
  if (!readinessState.complete)
    throw new Error("A final revision requires every declared page");
  return { worksetId: workset.id, pages: result };
}

export function worksetData(artifact, workset, records = new Map()) {
  const data = copy(artifact);
  delete data.manifest;
  data.workset = copy(workset);
  data.pages = artifact.pages.map((page) => {
    const slot = pageEntry(workset, page.id);
    const record = records.get(page.id);
    return {
      ...page,
      html: record ? record.html : pendingPageHtml(page, workset),
      ...(slot?.version ? { version: slot.version } : {}),
      ...(slot?.renderVerified !== undefined
        ? { renderVerified: slot.renderVerified }
        : {}),
    };
  });
  return data;
}

export function finalData(artifact, workset, records) {
  const data = copy(artifact);
  delete data.workset;
  const authoredAgreed = artifact.pages.some((page) => page.id === "agreed");
  const slots = authoredAgreed
    ? artifact.pages.map((page) => pageEntry(workset, page.id))
    : workset.declared
        .filter((slot) => slot.id !== "agreed")
        .sort((a, b) => a.order - b.order);
  data.pages = slots.map((slot) => {
    const record = records.get(slot.id);
    if (!record) throw new Error(`Missing page ${slot.id}`);
    return {
      id: slot.id,
      title: record.title,
      html: record.html,
    };
  });
  data.manifest = manifestFor(workset);
  return data;
}
