/**
 * The page renderer: Markdown in, HTML plus a list of blocks out.
 *
 * Every visual is a fenced block. The renderer does not know how any of them
 * look; it leaves a mount point carrying the parsed data, and the block
 * components fill it. That keeps this module free of Pierre, Mermaid, KaTeX,
 * and ECharts, and keeps the grammar the only thing it enforces.
 */
import {
  looksLikePath,
  parseBlock,
  parseCompare,
  sanitizerConfig,
} from "./grammar.mjs";

export const libraries = {
  markdownIt: "https://esm.sh/markdown-it@15.0.2",
  container: "https://esm.sh/markdown-it-container@4.0.0",
  purify: "https://esm.sh/dompurify@3.4.15",
};

let loading;
async function load() {
  loading ||= Promise.all([
    import(libraries.markdownIt),
    import(libraries.container),
    import(libraries.purify),
  ]);
  const [markdownIt, container, purify] = await loading;
  return {
    MarkdownIt: markdownIt.default,
    container: container.default,
    purify: purify.default,
  };
}

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

export async function createRenderer() {
  const { MarkdownIt, container, purify } = await load();
  const md = new MarkdownIt({
    html: true,
    linkify: true,
    breaks: false,
    typographer: false,
  });

  let collected;

  /** Reserve a mount point and hand the block to the page's components. */
  const mount = (block) => {
    const index = collected.blocks.push(block) - 1;
    return `<div class="block" data-block="${index}" data-block-name="${escapeHtml(block.name)}"></div>`;
  };

  md.renderer.rules.fence = (tokens, index) => {
    const token = tokens[index];
    const block = parseBlock(token.info, token.content);
    if (block.error && block.name !== "mermaid" && !block.data) {
      // An unreadable block keeps its source on the page with the reason,
      // rather than disappearing into a silent gap in the explanation.
      collected.errors.push(block);
      return (
        `<div class="block-source"><pre><code>` +
        escapeHtml(`\`\`\`${token.info}\n${token.content}\`\`\``) +
        `</code></pre><p class="renderer-error">${escapeHtml(block.error)}</p></div>`
      );
    }
    if (block.name === "notes") {
      collected.notes.push(block.data);
      const count = block.data.notes.length;
      return `<p class="notes-summary">${count} note${count === 1 ? "" : "s"} on <code>${escapeHtml(block.data.target.path)}</code></p>`;
    }
    return mount(block);
  };

  md.use(container, "added", {
    render: (tokens, index) =>
      tokens[index].nesting === 1
        ? `<section class="added"><h3>Added after your question</h3>`
        : `</section>`,
  });

  md.use(container, "compare", {
    render(tokens, index) {
      const token = tokens[index];
      if (token.nesting !== 1) return `</div>`;
      const sides = parseCompare(token.info.replace(/^\s*compare\s*/, ""));
      return (
        `<div class="compare" data-before="${escapeHtml(sides.before)}" ` +
        `data-after="${escapeHtml(sides.after)}">`
      );
    },
  });

  // $…$ and $$…$$ reach the page as mount points KaTeX fills, so a dollar
  // sign in ordinary prose stays a dollar sign.
  md.inline.ruler.before("escape", "math", (state, silent) => {
    if (state.src[state.pos] !== "$") return false;
    const display = state.src.startsWith("$$", state.pos);
    const fence = display ? "$$" : "$";
    const start = state.pos + fence.length;
    const end = state.src.indexOf(fence, start);
    if (end === -1 || end === start) return false;
    const content = state.src.slice(start, end);
    if (!display && /^\s|\s$/.test(content)) return false;
    if (!silent) {
      const token = state.push("math", "", 0);
      token.content = content;
      token.markup = fence;
    }
    state.pos = end + fence.length;
    return true;
  });
  md.renderer.rules.math = (tokens, index) =>
    `<span class="math" data-math="${tokens[index].markup === "$$" ? "block" : "inline"}">` +
    `${escapeHtml(tokens[index].content)}</span>`;

  // Inline code that could name a file becomes a candidate reference. The
  // page confirms it against the repository before it turns into a chip.
  md.renderer.rules.code_inline = (tokens, index) => {
    const content = tokens[index].content;
    const location = looksLikePath(content);
    if (!location) return `<code>${escapeHtml(content)}</code>`;
    collected.references.push(location);
    return (
      `<code class="reference" data-reference="${escapeHtml(content)}">` +
      `${escapeHtml(content)}</code>`
    );
  };

  const link = md.renderer.rules.link_open;
  md.renderer.rules.link_open = (tokens, index, options, env, self) => {
    tokens[index].attrSet("target", "_blank");
    tokens[index].attrSet("rel", "noreferrer noopener");
    return link
      ? link(tokens, index, options, env, self)
      : self.renderToken(tokens, index, options);
  };

  return {
    /** Render one page. The caller mounts `blocks` into the returned HTML. */
    render(markdown) {
      collected = { blocks: [], notes: [], references: [], errors: [] };
      const html = purify.sanitize(md.render(String(markdown ?? "")), {
        ...sanitizerConfig,
        RETURN_TRUSTED_TYPE: false,
      });
      return { html, ...collected };
    },
  };
}
