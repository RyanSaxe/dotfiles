// Ranked fuzzy matching for the dashboards.
//
// The rule that matters: a query is matched against each FIELD separately,
// never against the fields concatenated. Concatenation is what made the
// previous implementation useless — a subsequence test across ~300 joined
// characters matched almost any query, so `/asdf` returned every row and
// search looked broken.
//
// Whitespace splits a query into terms. Every term must match some field
// (fzf's AND semantics), which is what lets `/alice ci` find one item.

export interface TermMatch {
  score: number;
  // Indices into the field text, so the renderer can color the exact
  // characters that earned the match.
  positions: number[];
}

export interface FieldsMatch {
  score: number;
  // field index -> matched character positions within that field
  hits: Map<number, number[]>;
}

// Characters after which a new "word" begins. `/#-_.@:` matter here because
// the things being searched are repo/name, #1234 and @login.
const BOUNDARY = /[\s/#\-_.@:]/;

function isWordStart(text: string, index: number): boolean {
  if (index === 0) return true;
  const previous = text[index - 1];
  return previous !== undefined && BOUNDARY.test(previous);
}

// Substring hits and subsequence hits live in separate score bands, so an
// intact match always outranks a scattered one no matter how the bonuses
// land. Within a band the bonuses decide the order.
const SUBSTRING_BASE = 1000;
const SUBSEQUENCE_BASE = 0;

export function scoreTerm(text: string, term: string): TermMatch | null {
  if (term === "") return { score: 0, positions: [] };
  const haystack = text.toLowerCase();
  const needle = term.toLowerCase();
  const slack = Math.max(0, haystack.length - needle.length);

  let best: TermMatch | null = null;
  for (let from = 0; ; from += 1) {
    const at = haystack.indexOf(needle, from);
    if (at < 0) break;
    const score =
      SUBSTRING_BASE +
      (isWordStart(haystack, at) ? 400 : 0) +
      (at === 0 ? 200 : 0) -
      Math.min(200, at) -
      slack / 4;
    if (best === null || score > best.score) {
      best = {
        score,
        positions: Array.from({ length: needle.length }, (_, k) => at + k),
      };
    }
    from = at;
  }
  if (best !== null) return best;

  const positions: number[] = [];
  let cursor = 0;
  for (const character of needle) {
    const at = haystack.indexOf(character, cursor);
    if (at < 0) return null;
    positions.push(at);
    cursor = at + 1;
  }

  let score = SUBSEQUENCE_BASE - slack / 4;
  const first = positions[0];
  if (first !== undefined && isWordStart(haystack, first)) score += 30;
  for (let index = 1; index < positions.length; index += 1) {
    const previous = positions[index - 1];
    const current = positions[index];
    if (previous === undefined || current === undefined) continue;
    // Adjacent characters are the signal that this is a real word fragment
    // rather than letters happening to appear in order.
    score += current === previous + 1 ? 15 : -Math.min(10, current - previous);
  }
  return { score, positions };
}

export function scoreFields(
  fields: readonly string[],
  query: string,
): FieldsMatch | null {
  const terms = query
    .trim()
    .split(/\s+/)
    .filter((term) => term !== "");
  if (terms.length === 0) return { score: 0, hits: new Map() };

  let total = 0;
  const hits = new Map<number, number[]>();
  for (const term of terms) {
    let bestIndex = -1;
    let bestMatch: TermMatch | null = null;
    for (const [index, text] of fields.entries()) {
      const match = scoreTerm(text, term);
      if (match === null) continue;
      if (bestMatch === null || match.score > bestMatch.score) {
        bestIndex = index;
        bestMatch = match;
      }
    }
    // AND semantics: one unmatched term rejects the whole item.
    if (bestMatch === null) return null;
    total += bestMatch.score;
    hits.set(bestIndex, [
      ...(hits.get(bestIndex) ?? []),
      ...bestMatch.positions,
    ]);
  }
  return { score: total, hits };
}

export interface Ranked<T> {
  item: T;
  hits: ReadonlyMap<number, readonly number[]>;
}

export function rank<T>(
  items: readonly T[],
  query: string,
  fieldsOf: (item: T) => readonly string[],
): Ranked<T>[] {
  if (query.trim() === "") {
    return items.map((item) => ({ item, hits: new Map() }));
  }
  const scored: Array<{ ranked: Ranked<T>; score: number; order: number }> = [];
  items.forEach((item, order) => {
    const match = scoreFields(fieldsOf(item), query);
    if (match === null) return;
    scored.push({
      ranked: { item, hits: match.hits },
      score: match.score,
      order,
    });
  });
  // Score first, original order as the tie-break so equal matches keep the
  // urgency ordering the caller already established.
  scored.sort((a, b) => b.score - a.score || a.order - b.order);
  return scored.map((entry) => entry.ranked);
}
