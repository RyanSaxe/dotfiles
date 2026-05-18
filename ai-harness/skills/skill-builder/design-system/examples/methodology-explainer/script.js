/* ----------------------------------------------------------------
 * methodology-explainer / script.js
 *
 * Three things:
 *   1. Scrollspy — keep the TOC's active item in sync with the section
 *      currently in view (the canonical yellow "you are here" pattern).
 *   2. Gradient-descent figure — a 2D anisotropic quadratic with a
 *      "Step" button and a learning-rate slider; the user watches the
 *      path zigzag through the elongated valley.
 *   3. Posterior figure — Beta-binomial. Sliders set trials and
 *      successes; prior, likelihood, and posterior curves animate.
 *
 * No build step. SVG figures are drawn into the inline <svg> element
 * via createElementNS — all coordinates are computed in math-space and
 * mapped to the viewBox by small `toSvgX`/`toSvgY` helpers per figure.
 * ---------------------------------------------------------------- */

const SVG_NS = "http://www.w3.org/2000/svg";

/* ====================== Scrollspy ====================== */

function initScrollspy() {
  const links = Array.from(document.querySelectorAll("#tocList a[href^='#']"));
  const sections = links
    .map((a) => document.getElementById(a.getAttribute("href").slice(1)))
    .filter(Boolean);

  const linkFor = (id) => links.find((a) => a.getAttribute("href") === `#${id}`);

  // IntersectionObserver fires whenever sections cross thresholds; we
  // pick the topmost-visible section as the active one.
  const visible = new Set();
  const obs = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        if (e.isIntersecting) visible.add(e.target.id);
        else visible.delete(e.target.id);
      }
      // Pick the section that comes earliest in the document
      let activeId = null;
      for (const s of sections) {
        if (visible.has(s.id)) {
          activeId = s.id;
          break;
        }
      }
      // Fall back to the section above the fold (last one above viewport top)
      if (!activeId) {
        for (let i = sections.length - 1; i >= 0; i--) {
          if (sections[i].getBoundingClientRect().top < 100) {
            activeId = sections[i].id;
            break;
          }
        }
      }
      links.forEach((a) => a.classList.remove("is-active"));
      const active = activeId ? linkFor(activeId) : null;
      if (active) active.classList.add("is-active");
    },
    {
      rootMargin: "-80px 0px -55% 0px",
      threshold: 0,
    }
  );
  sections.forEach((s) => obs.observe(s));
}

/* ====================== Gradient-descent figure ====================== */

const GD_CONFIG = {
  // Loss: L(x, y) = a*x^2 + b*y^2 — anisotropic, so high LRs zigzag in y
  a: 0.15,
  b: 1.0,
  start: { x: -3, y: 1.5 },
  // Math-space window
  xMin: -4, xMax: 4,
  yMin: -2, yMax: 2,
  // SVG viewBox
  vbW: 480, vbH: 300,
  margin: { l: 30, r: 20, t: 30, b: 30 },
};

function gdLoss(p)  { return GD_CONFIG.a * p.x * p.x + GD_CONFIG.b * p.y * p.y; }
function gdGrad(p)  { return { x: 2 * GD_CONFIG.a * p.x, y: 2 * GD_CONFIG.b * p.y }; }

function gdToSvgX(x) {
  const { xMin, xMax, vbW, margin } = GD_CONFIG;
  const w = vbW - margin.l - margin.r;
  return margin.l + ((x - xMin) / (xMax - xMin)) * w;
}
function gdToSvgY(y) {
  const { yMin, yMax, vbH, margin } = GD_CONFIG;
  const h = vbH - margin.t - margin.b;
  return margin.t + ((yMax - y) / (yMax - yMin)) * h;
}

function gdInit() {
  const svg = document.getElementById("gdSvg");
  const stepBtn = document.getElementById("gdStep");
  const resetBtn = document.getElementById("gdReset");
  const lrInput = document.getElementById("gdLr");
  const lrOut   = document.getElementById("gdLrOut");
  const stepsOut= document.getElementById("gdSteps");
  const lossOut = document.getElementById("gdLoss");

  let path = [{ ...GD_CONFIG.start }];
  let lr = parseFloat(lrInput.value);

  function render() {
    // clear
    while (svg.firstChild) svg.removeChild(svg.firstChild);

    // Contour ellipses for L = 0.4, 0.9, 1.6, 2.5, 3.6
    // Centered at (0,0). semi-axes: ax = sqrt(c/a), ay = sqrt(c/b).
    const levels = [0.4, 0.9, 1.6, 2.5, 3.6];
    const palette = ["#dbeafe", "#bfdbfe", "#93c5fd", "#60a5fa", "#3b82f6"];
    levels.forEach((c, i) => {
      const ax = Math.sqrt(c / GD_CONFIG.a);
      const ay = Math.sqrt(c / GD_CONFIG.b);
      const cx = gdToSvgX(0);
      const cy = gdToSvgY(0);
      const rx = gdToSvgX(ax) - cx;
      const ry = cy - gdToSvgY(ay);
      const e = document.createElementNS(SVG_NS, "ellipse");
      e.setAttribute("cx", cx);
      e.setAttribute("cy", cy);
      e.setAttribute("rx", rx);
      e.setAttribute("ry", ry);
      e.setAttribute("fill", "none");
      e.setAttribute("stroke", palette[i]);
      e.setAttribute("stroke-width", "1.2");
      svg.appendChild(e);
    });

    // Axes (light gray crosshair through origin)
    const axisAttrs = { stroke: "#e5e5e5", "stroke-width": "1", "stroke-dasharray": "2 3" };
    const xa = document.createElementNS(SVG_NS, "line");
    xa.setAttribute("x1", gdToSvgX(GD_CONFIG.xMin));
    xa.setAttribute("x2", gdToSvgX(GD_CONFIG.xMax));
    xa.setAttribute("y1", gdToSvgY(0));
    xa.setAttribute("y2", gdToSvgY(0));
    Object.entries(axisAttrs).forEach(([k, v]) => xa.setAttribute(k, v));
    svg.appendChild(xa);

    const ya = document.createElementNS(SVG_NS, "line");
    ya.setAttribute("x1", gdToSvgX(0));
    ya.setAttribute("x2", gdToSvgX(0));
    ya.setAttribute("y1", gdToSvgY(GD_CONFIG.yMin));
    ya.setAttribute("y2", gdToSvgY(GD_CONFIG.yMax));
    Object.entries(axisAttrs).forEach(([k, v]) => ya.setAttribute(k, v));
    svg.appendChild(ya);

    // Path: line through visited points
    if (path.length > 1) {
      const pl = document.createElementNS(SVG_NS, "polyline");
      pl.setAttribute(
        "points",
        path.map((p) => `${gdToSvgX(p.x)},${gdToSvgY(p.y)}`).join(" ")
      );
      pl.setAttribute("fill", "none");
      pl.setAttribute("stroke", "#dc2626");
      pl.setAttribute("stroke-width", "2");
      pl.setAttribute("stroke-linecap", "round");
      pl.setAttribute("stroke-linejoin", "round");
      svg.appendChild(pl);
    }

    // Past points (small)
    path.slice(0, -1).forEach((p) => {
      const c = document.createElementNS(SVG_NS, "circle");
      c.setAttribute("cx", gdToSvgX(p.x));
      c.setAttribute("cy", gdToSvgY(p.y));
      c.setAttribute("r", "2.5");
      c.setAttribute("fill", "#dc2626");
      svg.appendChild(c);
    });

    // Current point (larger, ringed in accent — "you are here")
    const last = path[path.length - 1];
    const ring = document.createElementNS(SVG_NS, "circle");
    ring.setAttribute("cx", gdToSvgX(last.x));
    ring.setAttribute("cy", gdToSvgY(last.y));
    ring.setAttribute("r", "8");
    ring.setAttribute("fill", "none");
    ring.setAttribute("stroke", "#facc15");
    ring.setAttribute("stroke-width", "3");
    svg.appendChild(ring);

    const dot = document.createElementNS(SVG_NS, "circle");
    dot.setAttribute("cx", gdToSvgX(last.x));
    dot.setAttribute("cy", gdToSvgY(last.y));
    dot.setAttribute("r", "4");
    dot.setAttribute("fill", "#0a0a0a");
    svg.appendChild(dot);

    // Update stats
    stepsOut.textContent = String(path.length - 1);
    lossOut.textContent  = gdLoss(last).toFixed(3);
  }

  function step() {
    const cur = path[path.length - 1];
    const g = gdGrad(cur);
    const next = { x: cur.x - lr * g.x, y: cur.y - lr * g.y };
    // Clamp to viewport so wild oscillations don't shoot offscreen
    next.x = Math.max(GD_CONFIG.xMin, Math.min(GD_CONFIG.xMax, next.x));
    next.y = Math.max(GD_CONFIG.yMin, Math.min(GD_CONFIG.yMax, next.y));
    path.push(next);
    render();
  }
  function reset() {
    path = [{ ...GD_CONFIG.start }];
    render();
  }

  stepBtn.addEventListener("click", step);
  resetBtn.addEventListener("click", reset);
  lrInput.addEventListener("input", () => {
    lr = parseFloat(lrInput.value);
    lrOut.textContent = lr.toFixed(2);
  });

  render();
}

/* ====================== Posterior figure ====================== */

const POST_CONFIG = {
  vbW: 480, vbH: 280,
  margin: { l: 35, r: 15, t: 20, b: 35 },
  // Prior: Beta(2, 2)
  priorA: 2, priorB: 2,
  // Curve series colors (categorical content palette)
  colors: {
    prior:      "#06b6d4",
    likelihood: "#f97316",
    posterior:  "#8b5cf6",
  },
};

function postToSvgX(x) {
  const { vbW, margin } = POST_CONFIG;
  const w = vbW - margin.l - margin.r;
  return margin.l + x * w;
}
function postToSvgY(y, yMax) {
  const { vbH, margin } = POST_CONFIG;
  const h = vbH - margin.t - margin.b;
  return margin.t + (1 - y / yMax) * h;
}

// Compute unnormalized Beta(α, β) values at x
function betaPdfUn(x, a, b) {
  if (x <= 0 || x >= 1) return 0;
  return Math.pow(x, a - 1) * Math.pow(1 - x, b - 1);
}

// Compute likelihood ∝ x^s (1-x)^(n-s) (binomial, viewed as a function of x)
function likelihoodUn(x, s, n) {
  if (x < 0 || x > 1) return 0;
  if (n === 0) return 1; // flat (no data)
  return Math.pow(x, s) * Math.pow(1 - x, n - s);
}

function buildCurve(fn, samples) {
  const xs = [];
  for (let i = 0; i <= samples; i++) xs.push(i / samples);
  const ys = xs.map(fn);
  const yMax = Math.max(...ys);
  // Normalize each curve to its own max so all three are comparable
  // by shape (prior stays the same; likelihood and posterior tighten).
  const yNorm = yMax > 0 ? ys.map((y) => y / yMax) : ys;
  return { xs, ys: yNorm };
}

function postInit() {
  const svg = document.getElementById("postSvg");
  const nIn = document.getElementById("postN");
  const sIn = document.getElementById("postS");
  const nOut = document.getElementById("postNOut");
  const sOut = document.getElementById("postSOut");
  const legendEl = document.getElementById("postLegend");

  function draw() {
    let n = parseInt(nIn.value, 10);
    let s = parseInt(sIn.value, 10);
    if (s > n) {
      s = n;
      sIn.value = String(s);
    }
    sIn.max = String(Math.max(n, 1));
    nOut.textContent = n;
    sOut.textContent = s;

    const samples = 200;
    const prior = buildCurve(
      (x) => betaPdfUn(x, POST_CONFIG.priorA, POST_CONFIG.priorB),
      samples
    );
    const lik = buildCurve(
      (x) => likelihoodUn(x, s, n),
      samples
    );
    const post = buildCurve(
      (x) => betaPdfUn(x, POST_CONFIG.priorA + s, POST_CONFIG.priorB + n - s),
      samples
    );

    // clear
    while (svg.firstChild) svg.removeChild(svg.firstChild);

    // x-axis
    const xAxis = document.createElementNS(SVG_NS, "line");
    xAxis.setAttribute("x1", postToSvgX(0));
    xAxis.setAttribute("x2", postToSvgX(1));
    xAxis.setAttribute("y1", postToSvgY(0, 1));
    xAxis.setAttribute("y2", postToSvgY(0, 1));
    xAxis.setAttribute("stroke", "#d4d4d4");
    xAxis.setAttribute("stroke-width", "1");
    svg.appendChild(xAxis);

    // x-axis ticks
    [0, 0.25, 0.5, 0.75, 1].forEach((tx) => {
      const t = document.createElementNS(SVG_NS, "line");
      t.setAttribute("x1", postToSvgX(tx));
      t.setAttribute("x2", postToSvgX(tx));
      t.setAttribute("y1", postToSvgY(0, 1));
      t.setAttribute("y2", postToSvgY(0, 1) + 4);
      t.setAttribute("stroke", "#d4d4d4");
      t.setAttribute("stroke-width", "1");
      svg.appendChild(t);

      const lbl = document.createElementNS(SVG_NS, "text");
      lbl.setAttribute("x", postToSvgX(tx));
      lbl.setAttribute("y", postToSvgY(0, 1) + 16);
      lbl.setAttribute("font-size", "10");
      lbl.setAttribute("text-anchor", "middle");
      lbl.setAttribute("fill", "#737373");
      lbl.setAttribute("font-family", "ui-sans-serif, system-ui");
      lbl.textContent = tx.toString();
      svg.appendChild(lbl);
    });

    // x-axis title
    const xt = document.createElementNS(SVG_NS, "text");
    xt.setAttribute("x", (postToSvgX(0) + postToSvgX(1)) / 2);
    xt.setAttribute("y", POST_CONFIG.vbH - 4);
    xt.setAttribute("font-size", "10");
    xt.setAttribute("text-anchor", "middle");
    xt.setAttribute("fill", "#737373");
    xt.setAttribute("font-family", "ui-sans-serif, system-ui");
    xt.setAttribute("font-style", "italic");
    xt.textContent = "θ  (probability of success)";
    svg.appendChild(xt);

    function plotCurve(curve, color, fillOpacity) {
      const points = curve.xs
        .map((x, i) => `${postToSvgX(x)},${postToSvgY(curve.ys[i], 1)}`)
        .join(" ");

      // Filled area under curve (translucent)
      const area = document.createElementNS(SVG_NS, "polygon");
      area.setAttribute(
        "points",
        `${postToSvgX(0)},${postToSvgY(0, 1)} ${points} ${postToSvgX(1)},${postToSvgY(0, 1)}`
      );
      area.setAttribute("fill", color);
      area.setAttribute("fill-opacity", fillOpacity);
      area.setAttribute("stroke", "none");
      svg.appendChild(area);

      // Curve
      const line = document.createElementNS(SVG_NS, "polyline");
      line.setAttribute("points", points);
      line.setAttribute("fill", "none");
      line.setAttribute("stroke", color);
      line.setAttribute("stroke-width", "2.2");
      line.setAttribute("stroke-linejoin", "round");
      svg.appendChild(line);
    }

    plotCurve(prior, POST_CONFIG.colors.prior, 0.10);
    plotCurve(lik,   POST_CONFIG.colors.likelihood, 0.10);
    plotCurve(post,  POST_CONFIG.colors.posterior, 0.18);

    // Posterior mean (vertical dashed line + label)
    const postMean = (POST_CONFIG.priorA + s) / (POST_CONFIG.priorA + POST_CONFIG.priorB + n);
    const ml = document.createElementNS(SVG_NS, "line");
    ml.setAttribute("x1", postToSvgX(postMean));
    ml.setAttribute("x2", postToSvgX(postMean));
    ml.setAttribute("y1", postToSvgY(0, 1));
    ml.setAttribute("y2", postToSvgY(1, 1));
    ml.setAttribute("stroke", POST_CONFIG.colors.posterior);
    ml.setAttribute("stroke-width", "1");
    ml.setAttribute("stroke-dasharray", "2 3");
    svg.appendChild(ml);

    const meanLbl = document.createElementNS(SVG_NS, "text");
    meanLbl.setAttribute("x", postToSvgX(postMean));
    meanLbl.setAttribute("y", postToSvgY(1, 1) - 4);
    meanLbl.setAttribute("font-size", "10");
    meanLbl.setAttribute("text-anchor", "middle");
    meanLbl.setAttribute("fill", POST_CONFIG.colors.posterior);
    meanLbl.setAttribute("font-family", "ui-sans-serif, system-ui");
    meanLbl.setAttribute("font-weight", "600");
    meanLbl.textContent = `mean = ${postMean.toFixed(2)}`;
    svg.appendChild(meanLbl);
  }

  // Build the legend once (the colors don't change)
  legendEl.innerHTML = `
    <li><span class="swatch" style="background:${POST_CONFIG.colors.prior}"></span>Prior — Beta(2, 2)</li>
    <li><span class="swatch" style="background:${POST_CONFIG.colors.likelihood}"></span>Likelihood — what the data says</li>
    <li><span class="swatch" style="background:${POST_CONFIG.colors.posterior}"></span>Posterior — combined belief</li>
  `;

  nIn.addEventListener("input", draw);
  sIn.addEventListener("input", draw);
  draw();
}

/* ====================== Boot ====================== */

document.addEventListener("DOMContentLoaded", () => {
  initScrollspy();
  gdInit();
  postInit();

  // Highlight code blocks (single language: python)
  document.querySelectorAll("pre code").forEach((block) => {
    hljs.highlightElement(block);
  });

  lucide.createIcons();
});
