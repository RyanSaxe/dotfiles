/* A formula, and the table that names its terms. */
/* KaTeX runs with no trust option, so \htmlClass is refused and a colour
   has to be a literal in the source. The literal is swapped for a class
   here, which is what lets a term follow the theme. */
const termPalette = ["#1d4ed8", "#a16207", "#047857", "#9333ea"];
const termColors = termPalette.map((hex) => {
  const probe = document.createElement("span");
  probe.style.color = hex;
  return probe.style.color;
});
function termRow(term, index, show) {
  const row = document.createElement("div");
  row.className = "formula-term";
  row.dataset.term = String(index + 1);
  row.tabIndex = 0;
  const symbol = document.createElement("dt");
  symbol.className = `term-${index + 1}`;
  symbol.textContent = term.symbol || "";
  const meaning = document.createElement("dd");
  meaning.append(term.meaning || "");
  if (term.value) {
    const value = document.createElement("b");
    value.textContent = term.value;
    meaning.append(value);
  }
  row.append(symbol, meaning);
  row.onpointerenter = () => show(row.dataset.term);
  row.onfocus = () => show(row.dataset.term);
  row.onpointerleave = () => show(null);
  row.onblur = () => show(null);
  return row;
}
function nameTerms(element) {
  const terms = readData(element.dataset.terms);
  const colored = [...element.querySelectorAll("[style*='color']")].filter(
    (span) => termColors.includes(span.style.color),
  );
  if (!colored.length && !terms.length) return;
  for (const span of colored) {
    const index = termColors.indexOf(span.style.color);
    span.classList.add("term", `term-${index + 1}`);
    span.dataset.term = String(index + 1);
    span.style.removeProperty("color");
  }
  const formula = document.createElement("div");
  formula.className = "formula";
  const body = document.createElement("div");
  body.className = "formula-body";
  element.replaceWith(formula);
  body.append(element);
  formula.append(body);
  if (!terms.length) return;
  const list = document.createElement("dl");
  list.className = "formula-terms";
  const show = (term) => {
    if (term) formula.dataset.focus = term;
    else delete formula.dataset.focus;
    for (const span of element.querySelectorAll(".term"))
      span.dataset.on = String(!term || span.dataset.term === term);
    for (const row of list.querySelectorAll(".formula-term"))
      row.dataset.active = String(Boolean(term) && row.dataset.term === term);
  };
  terms.forEach((term, index) => list.append(termRow(term, index, show)));
  formula.append(list);
}
async function renderMath(element) {
  try {
    await Promise.all([
      script(
        libraries.katex,
        "sha384-cMkvdD8LoxVzGF/RPUKAcvmm49FQ0oxwDF3BGKtDXcEc+T1b2N+teh/OJfpU0jr6",
      ),
      script(
        libraries.katexCss,
        "sha384-5TcZemv2l/9On385z///+d7MSYlvIEw9FuZTIdZ14vJLqWphw7e7ZPuOiCHJcFCP",
        true,
      ),
    ]);
    if (element.isConnected) {
      window.katex.render(element.textContent, element, {
        throwOnError: true,
        displayMode: element.dataset.math !== "inline",
      });
      nameTerms(element);
    }
  } catch (error) {
    failed(element, error);
  }
}
planUI.define("formula", {
  match: "[data-math]",
  setup: (element) => renderMath(element),
});
