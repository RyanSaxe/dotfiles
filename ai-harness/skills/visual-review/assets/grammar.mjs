/**
 * The block grammar, as pure functions.
 *
 * The agent writes Markdown; anything visual is a fenced block whose info
 * string names it. Parsing lives here, with no DOM and no renderer, so the
 * same rules apply in the browser, in the export, and in the tests.
 */

const refPattern = /^[A-Za-z0-9._/-]+$/;
const lineSuffix = /:(\d+)(?:-(\d+))?$/;

/**
 * Read `PATH[@REF][:START[-END]]`, the one location grammar used by fences,
 * by the reference rule, and by the code pane. Returns null for anything that
 * is not a location, because inline code is mostly not one.
 */
export function parseLocation(input) {
  let rest = String(input ?? "").trim();
  if (!rest) return null;
  let start = null;
  let end = null;
  const lines = rest.match(lineSuffix);
  if (lines) {
    start = Number(lines[1]);
    end = lines[2] === undefined ? start : Number(lines[2]);
    rest = rest.slice(0, -lines[0].length);
    if (start < 1 || end < start) return null;
  }
  let ref = null;
  const at = rest.lastIndexOf("@");
  if (at > 0) {
    ref = rest.slice(at + 1);
    rest = rest.slice(0, at);
    if (!ref || !refPattern.test(ref) || ref.startsWith("-")) return null;
  }
  const path = rest;
  if (!path || path.startsWith("/") || path.startsWith("-")) return null;
  if (path.includes("\\") || /\s/.test(path)) return null;
  if (
    path
      .split("/")
      .some((segment) => segment === ".." || segment === "." || !segment)
  )
    return null;
  return { path, ref, start, end };
}

/** `path:12-20`, the form used in chips, headers, and copied text. */
export function formatLocation(location) {
  if (!location) return "";
  const lines =
    location.start === null || location.start === undefined
      ? ""
      : location.end && location.end !== location.start
        ? `:${location.start}-${location.end}`
        : `:${location.start}`;
  return location.path + lines;
}

/**
 * Inline code becomes a reference chip only when it could be a path at all.
 * Checking every code span against the repository would spend a request on
 * every `charge()` in the prose.
 */
export function looksLikePath(text) {
  const location = parseLocation(text);
  if (!location) return null;
  const name = location.path.split("/").pop();
  if (!location.path.includes("/") && !/\.[A-Za-z0-9]+$/.test(name))
    return null;
  return location;
}

/**
 * Split a block body into entries: a line matching `start` opens one, and
 * indented lines continue the entry above it. The matcher's last group is the
 * entry's opening text, which is empty when the text is all continuation.
 */
function entries(body, start) {
  const collected = [];
  for (const line of String(body ?? "").split("\n")) {
    if (!line.trim()) continue;
    const match = line.match(start);
    if (match) {
      collected.push({ match, text: (match.at(-1) ?? "").trim() });
      continue;
    }
    if (/^\s/.test(line) && collected.length) {
      const last = collected.at(-1);
      last.text = `${last.text} ${line.trim()}`.trim();
      continue;
    }
    throw new Error(`Cannot read this line: ${line.trim()}`);
  }
  return collected;
}

function parseExcerptNotes(body) {
  return entries(body, /^(\d+)(?:\s{2,}|\t)(.*)$/).map(({ match, text }) => ({
    line: Number(match[1]),
    text,
  }));
}

/** `N`, `N-M` for a file; `+N` or `-N` for a side of a diff. */
export function parseRange(input) {
  const text = String(input ?? "").trim();
  const sided = text.match(/^([+-])(\d+)$/);
  if (sided)
    return {
      start: Number(sided[2]),
      end: Number(sided[2]),
      side: sided[1] === "+" ? "additions" : "deletions",
    };
  const span = text.match(/^(\d+)(?:-(\d+))?$/);
  if (!span) return null;
  const start = Number(span[1]);
  const end = span[2] === undefined ? start : Number(span[2]);
  if (start < 1 || end < start) return null;
  return { start, end, side: null };
}

/** `PATH@REF` for a file, or `BASE..HEAD PATH` for a diff. */
export function parseTarget(input) {
  const text = String(input ?? "").trim();
  const diff = text.match(/^(\S+)\.\.(\S+)\s+(\S+)$/);
  if (diff) {
    const location = parseLocation(diff[3]);
    if (!location || !refPattern.test(diff[1]) || !refPattern.test(diff[2]))
      return null;
    return { kind: "diff", base: diff[1], head: diff[2], path: location.path };
  }
  const location = parseLocation(text);
  if (!location || location.start !== null) return null;
  return { kind: "file", path: location.path, ref: location.ref };
}

/** The key notes and markers are grouped under, stable across pages. */
export function targetKey(target) {
  return target.kind === "diff"
    ? `${target.base}..${target.head} ${target.path}`
    : `${target.path}@${target.ref ?? ""}`;
}

const parsers = {
  mermaid: (argument, body) => ({ source: body.trim() }),

  code(argument, body) {
    const location = parseLocation(argument);
    if (!location) throw new Error("A code excerpt names PATH@REF:START-END");
    if (location.start === null)
      throw new Error("A code excerpt names the lines to show");
    return { location, notes: parseExcerptNotes(body) };
  },

  diff(argument, body) {
    const target = parseTarget(argument);
    if (!target || target.kind !== "diff")
      throw new Error("A diff names BASE..HEAD PATH");
    return { ...target, prose: body.trim() };
  },

  steps(argument, body) {
    const steps = entries(body, /^(\d+)\.\s+(\S+)\s*()$/).map(
      ({ match, text }) => {
        const location = parseLocation(match[2]);
        if (!location) throw new Error(`Step ${match[1]} needs a location`);
        return { location, text };
      },
    );
    if (!steps.length) throw new Error("A walkthrough needs at least one step");
    return { steps };
  },

  choose(argument, body) {
    const options = body
      .split("\n")
      .map((line) => line.match(/^\s*-\s+(.*\S)\s*$/)?.[1])
      .filter(Boolean);
    if (options.length < 2 || options.length > 4)
      throw new Error("A choice offers two to four options");
    return { title: argument.trim(), options };
  },

  chart(argument, body) {
    let data;
    try {
      data = JSON.parse(body);
    } catch {
      throw new Error("A chart is one JSON object");
    }
    if (!["bar", "line"].includes(data.type))
      throw new Error('A chart type is "bar" or "line"');
    if (!Array.isArray(data.x) || !Array.isArray(data.y) || !data.x.length)
      throw new Error("A chart needs x and y arrays");
    if (data.x.length !== data.y.length)
      throw new Error("A chart needs one y value per x value");
    if (
      !data.y.every(
        (value) => typeof value === "number" && Number.isFinite(value),
      )
    )
      throw new Error("Chart y values are numbers");
    return { title: argument.trim(), chart: data };
  },

  notes(argument, body) {
    const target = parseTarget(argument);
    if (!target) throw new Error("Notes name PATH@REF or BASE..HEAD PATH");
    const notes = entries(body, /^(\S+)(?:\s{2,}|\t)(.*)$/).map(
      ({ match, text }) => {
        const range = parseRange(match[1]);
        if (!range) throw new Error(`Cannot read the range ${match[1]}`);
        if (range.side && target.kind !== "diff")
          throw new Error("A +N or -N range belongs to a diff");
        return { ...range, text };
      },
    );
    if (!notes.length) throw new Error("A notes block needs at least one note");
    return { target, key: targetKey(target), notes };
  },
};

export const blockNames = Object.keys(parsers);

/**
 * Dispatch one fence. The first word of the info string names the block, the
 * rest is its argument, and the body is its data. A block this grammar does
 * not know, or one whose data it cannot read, comes back carrying the reason
 * so the page can show the source instead of swallowing it.
 */
export function parseBlock(info, body) {
  const text = String(info ?? "").trim();
  const space = text.search(/\s/);
  const name = space === -1 ? text : text.slice(0, space);
  const argument = space === -1 ? "" : text.slice(space + 1);
  const source = String(body ?? "");
  if (!Object.hasOwn(parsers, name))
    return {
      name,
      argument,
      source,
      error: `No block named ${name || "(blank)"}`,
    };
  try {
    return { name, argument, source, data: parsers[name](argument, source) };
  } catch (error) {
    return { name, argument, source, error: error.message };
  }
}

/** `::: compare Before | After` names the two sides of the pair. */
export function parseCompare(argument) {
  const [before, after] = String(argument ?? "").split("|");
  return {
    before: (before ?? "").trim() || "Before",
    after: (after ?? "").trim() || "After",
  };
}

/**
 * The attributes the page itself emits. Sanitizing runs over the whole
 * rendered page, so these have to be named explicitly or the renderer would
 * strip its own mount points.
 */
export const pageAttributes = [
  "data-block",
  "data-block-name",
  "data-reference",
  "data-math",
  "data-before",
  "data-after",
];

/**
 * What a page may keep from the agent's raw HTML. Scripts, event handlers,
 * framed documents, and forms are the parts that would turn a page of prose
 * into something that acts on its own. Arbitrary data attributes are dropped
 * so quoted repository content cannot dress itself up as a mount point.
 */
export const sanitizerConfig = {
  FORBID_TAGS: [
    "script",
    "iframe",
    "object",
    "embed",
    "form",
    "input",
    "style",
  ],
  FORBID_ATTR: ["srcdoc", "formaction", "ping"],
  ALLOW_DATA_ATTR: false,
  ADD_ATTR: ["target", "rel", ...pageAttributes],
};
