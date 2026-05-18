/* ----------------------------------------------------------------
 * fitness-dashboard / script.js
 *
 * Loads mock data, configures Chart.js with design-system tokens,
 * wires interactivity (period toggle, sortable table, hover tooltips).
 * No frameworks; vanilla JS only.
 * ---------------------------------------------------------------- */

const TOKENS = {
  emphasis: '#0a0a0a',
  fg: '#262626',
  muted: '#737373',
  border: '#e5e5e5',
  surface: '#ffffff',
  bg: '#fafafa',
  accent: '#facc15',
  positive: '#16a34a',
  positiveSoft: '#dcfce7',
  negative: '#dc2626',
  negativeSoft: '#fee2e2',
  fontSans: 'Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif',
};

// Apply Chart.js global defaults so every chart inherits our tokens.
Chart.defaults.font.family = TOKENS.fontSans;
Chart.defaults.font.size = 12;
Chart.defaults.color = TOKENS.muted;
Chart.defaults.borderColor = TOKENS.border;
Chart.defaults.elements.point.radius = 0;
Chart.defaults.elements.point.hoverRadius = 4;
Chart.defaults.elements.line.borderWidth = 2;
Chart.defaults.plugins.legend.display = false;
Chart.defaults.plugins.tooltip.backgroundColor = TOKENS.emphasis;
Chart.defaults.plugins.tooltip.titleColor = '#ffffff';
Chart.defaults.plugins.tooltip.bodyColor = '#ffffff';
Chart.defaults.plugins.tooltip.padding = 8;
Chart.defaults.plugins.tooltip.cornerRadius = 6;
Chart.defaults.plugins.tooltip.displayColors = false;

// ---------- State ----------

const state = {
  metrics: [],
  activities: [],
  period: 'week',         // 'day' | 'week' | 'month'
  sort: { key: 'date', asc: false },
  charts: {},             // chart.js instances, for re-render on period change
};

// ---------- Boot ----------
//
// Data is provided by data.js as window-level constants METRICS and ACTIVITIES.
// We don't fetch() at runtime: opening index.html via file:// blocks fetch from
// local files (CORS), so inline data is the only thing that works on a double-click.

(function init() {
  state.metrics = METRICS.map(m => ({ ...m, _date: new Date(m.date) }))
                         .sort((a, b) => a._date - b._date);
  state.activities = ACTIVITIES.slice();

  setupPeriodToggle();
  renderAll();
  initLucideIcons();
})();

function initLucideIcons() {
  // The Lucide UMD bundle exposes `lucide.createIcons()` which walks the
  // DOM and replaces `<i data-lucide="..."></i>` elements with inline SVG.
  if (window.lucide && window.lucide.createIcons) {
    window.lucide.createIcons({ attrs: { 'stroke-width': 2 } });
  }
}

// ---------- Period toggle ----------

function setupPeriodToggle() {
  const toggle = document.getElementById('periodToggle');
  toggle.addEventListener('click', e => {
    const btn = e.target.closest('button[data-period]');
    if (!btn) return;
    const period = btn.dataset.period;
    if (period === state.period) return;
    state.period = period;
    toggle.querySelectorAll('button').forEach(b => {
      const active = b.dataset.period === period;
      b.classList.toggle('is-active', active);
      b.setAttribute('aria-selected', active ? 'true' : 'false');
    });
    renderAll();
  });
}

function periodDays() {
  return { day: 1, week: 7, month: 30 }[state.period];
}

function periodLabel() {
  return { day: '24 hours', week: 'week', month: 'month' }[state.period];
}

// ---------- Data slicing ----------

function metricsForPeriod() {
  const n = periodDays();
  return state.metrics.slice(-n);
}

function metricsForPriorPeriod() {
  const n = periodDays();
  return state.metrics.slice(-n * 2, -n);
}

function avg(arr, key) {
  if (!arr.length) return 0;
  return arr.reduce((s, x) => s + x[key], 0) / arr.length;
}

function delta(curr, prior, opts = {}) {
  const { goodWhen = 'up', formatter = v => v.toFixed(1), unit = '' } = opts;
  if (!prior) return { text: '—', cls: 'neutral' };
  const diff = curr - prior;
  const pct = (diff / Math.abs(prior)) * 100;
  const isUp = diff >= 0;
  const isGood = (goodWhen === 'up' && isUp) || (goodWhen === 'down' && !isUp);
  const cls = Math.abs(pct) < 0.5 ? 'neutral' : (isGood ? 'positive' : 'negative');
  const text = `${isUp ? '+' : ''}${formatter(diff)}${unit} vs prior`;
  return { text, cls };
}

// ---------- Render ----------

function renderAll() {
  renderHeader();
  renderHero();
  renderMetricStrip();
  renderHrvChart();
  renderSleepDonut();
  renderStepsBar();
  renderHeatmap();
  renderTable();
}

function renderHeader() {
  const period = metricsForPeriod();
  if (period.length) {
    const start = new Date(period[0].date);
    const end = new Date(period[period.length - 1].date);
    const fmt = d => d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
    document.getElementById('dateRange').textContent =
      period.length === 1 ? fmt(end) : `${fmt(start)} – ${fmt(end)}`;
  }
  document.getElementById('periodLabel').textContent = periodLabel();
}

function renderHero() {
  const period = metricsForPeriod();
  const prior = metricsForPriorPeriod();

  // Recovery
  const recoveryAvg = avg(period, 'recovery');
  const recoveryPriorAvg = avg(prior, 'recovery');
  document.getElementById('recoveryValue').textContent = Math.round(recoveryAvg);
  const rd = delta(recoveryAvg, recoveryPriorAvg, { goodWhen: 'up', formatter: v => v.toFixed(1) });
  setDelta('recoveryDelta', rd);
  setRecoveryBadge(recoveryAvg);

  // Strain
  const strainAvg = avg(period, 'strain');
  const strainPriorAvg = avg(prior, 'strain');
  document.getElementById('strainValue').textContent = strainAvg.toFixed(1);
  const sd = delta(strainAvg, strainPriorAvg, { goodWhen: 'down', formatter: v => v.toFixed(1) });
  setDelta('strainDelta', sd);
  setStrainBadge(strainAvg);

  drawSpark('recoverySpark', period.map(p => p.recovery), TOKENS.emphasis);
  drawSpark('strainSpark', period.map(p => p.strain), TOKENS.emphasis);
}

function setDelta(id, { text, cls }) {
  const el = document.getElementById(id);
  el.textContent = text;
  el.className = 'delta ' + cls;
}

function setRecoveryBadge(value) {
  const el = document.getElementById('recoveryBadge');
  el.classList.remove('badge-positive', 'badge-accent', 'badge-negative');
  if (value >= 67) {
    el.textContent = 'Ready to train';
    el.classList.add('badge-positive');
  } else if (value >= 34) {
    el.textContent = 'Maintain';
    el.classList.add('badge-accent');
  } else {
    el.textContent = 'Recover';
    el.classList.add('badge-negative');
  }
}

function setStrainBadge(value) {
  const el = document.getElementById('strainBadge');
  el.classList.remove('badge-positive', 'badge-accent', 'badge-negative');
  if (value >= 14) {
    el.textContent = 'High — take it easy';
    el.classList.add('badge-negative');
  } else if (value >= 8) {
    el.textContent = 'Moderate';
    el.classList.add('badge-accent');
  } else {
    el.textContent = 'Light week';
    el.classList.add('badge-positive');
  }
}

function renderMetricStrip() {
  const period = metricsForPeriod();
  const prior = metricsForPriorPeriod();

  // RHR — lower is better
  const rhrAvg = avg(period, 'rhr');
  document.getElementById('rhrValue').textContent = Math.round(rhrAvg);
  setDelta('rhrDelta', delta(rhrAvg, avg(prior, 'rhr'), { goodWhen: 'down', formatter: v => v.toFixed(1) }));
  drawSpark('rhrSpark', period.map(p => p.rhr), TOKENS.fg);

  // HRV — higher is better
  const hrvAvg = avg(period, 'hrv');
  document.getElementById('hrvValue').textContent = Math.round(hrvAvg);
  setDelta('hrvDelta', delta(hrvAvg, avg(prior, 'hrv'), { goodWhen: 'up', formatter: v => v.toFixed(1) }));
  drawSpark('hrvSpark', period.map(p => p.hrv), TOKENS.fg);

  // Sleep — higher is better (target 7+)
  const sleepAvg = avg(period, 'sleep_hours');
  const h = Math.floor(sleepAvg);
  const m = Math.round((sleepAvg - h) * 60);
  document.getElementById('sleepValue').textContent = `${h}:${String(m).padStart(2, '0')}`;
  setDelta('sleepDelta', delta(sleepAvg, avg(prior, 'sleep_hours'), { goodWhen: 'up', formatter: v => v.toFixed(2), unit: 'h' }));
  drawSpark('sleepSpark', period.map(p => p.sleep_hours), TOKENS.fg);

  // Steps — higher is better
  const stepsAvg = avg(period, 'steps');
  document.getElementById('stepsValue').textContent = Math.round(stepsAvg).toLocaleString();
  setDelta('stepsDelta', delta(stepsAvg, avg(prior, 'steps'), { goodWhen: 'up', formatter: v => Math.round(v).toLocaleString() }));
  drawSpark('stepsSpark', period.map(p => p.steps), TOKENS.fg);
}

// ---------- Sparkline (mini line) ----------

function drawSpark(canvasId, values, color) {
  if (state.charts[canvasId]) state.charts[canvasId].destroy();
  if (!values.length) return;
  const ctx = document.getElementById(canvasId).getContext('2d');
  state.charts[canvasId] = new Chart(ctx, {
    type: 'line',
    data: {
      labels: values.map((_, i) => i),
      datasets: [{
        data: values,
        borderColor: color,
        backgroundColor: 'transparent',
        tension: 0.35,
        fill: false,
      }],
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      animation: { duration: 400 },
      scales: { x: { display: false }, y: { display: false } },
      plugins: { tooltip: { enabled: false } },
    },
  });
}

// ---------- HRV trend (line, full width) ----------

function renderHrvChart() {
  const window = state.metrics.slice(-28); // last 28 days regardless of period
  const labels = window.map(m => m.date);
  const values = window.map(m => m.hrv);
  const baseline = avg(window, 'hrv');
  const baselineSeries = window.map(() => baseline);

  if (state.charts.hrvLine) state.charts.hrvLine.destroy();
  const ctx = document.getElementById('hrvLine').getContext('2d');

  // Highlight today's point with the accent color
  const todayIdx = window.length - 1;
  const pointBg = window.map((_, i) => i === todayIdx ? TOKENS.accent : TOKENS.emphasis);
  const pointRadius = window.map((_, i) => i === todayIdx ? 5 : 0);

  state.charts.hrvLine = new Chart(ctx, {
    type: 'line',
    data: {
      labels,
      datasets: [
        {
          data: values,
          borderColor: TOKENS.emphasis,
          backgroundColor: 'transparent',
          tension: 0.3,
          pointBackgroundColor: pointBg,
          pointBorderColor: pointBg,
          pointRadius,
          pointHoverRadius: 5,
        },
        {
          data: baselineSeries,
          borderColor: TOKENS.muted,
          borderDash: [4, 4],
          borderWidth: 1,
          backgroundColor: 'transparent',
          pointRadius: 0,
        },
      ],
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      animation: { duration: 500 },
      scales: {
        x: {
          grid: { display: false },
          ticks: {
            maxRotation: 0,
            callback: function (val, idx) {
              const d = new Date(labels[idx]);
              return idx % 4 === 0 ? d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) : '';
            },
          },
        },
        y: {
          grid: { color: TOKENS.border, drawBorder: false },
          ticks: { stepSize: 20 },
        },
      },
      plugins: {
        tooltip: {
          callbacks: {
            title: items => new Date(items[0].label).toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' }),
            label: ctx => ctx.datasetIndex === 0 ? `HRV ${ctx.parsed.y} ms` : `Baseline ${baseline.toFixed(0)} ms`,
          },
        },
      },
    },
  });

  document.getElementById('hrvNote').textContent = `${window.length}-day baseline ${baseline.toFixed(0)} ms`;
}

// ---------- Sleep stages donut ----------

function renderSleepDonut() {
  const period = metricsForPeriod();
  const totals = period.reduce((acc, m) => {
    acc.deep  += m.sleep_stages.deep;
    acc.rem   += m.sleep_stages.rem;
    acc.light += m.sleep_stages.light;
    acc.awake += m.sleep_stages.awake;
    return acc;
  }, { deep: 0, rem: 0, light: 0, awake: 0 });
  const n = Math.max(1, period.length);
  const avgs = {
    deep: totals.deep / n, rem: totals.rem / n,
    light: totals.light / n, awake: totals.awake / n,
  };
  // Sequential blue ramp through one hue family — sleep stages share a meaning
  // ("depth of sleep") so a single-hue ramp reads as ordered, not categorical.
  // From design-system viz palette § Sequential ramps (blue).
  const stages = [
    { key: 'Deep',  value: avgs.deep,  color: '#1e3a8a' }, // deepest blue
    { key: 'REM',   value: avgs.rem,   color: '#3b82f6' },
    { key: 'Light', value: avgs.light, color: '#60a5fa' },
    { key: 'Awake', value: avgs.awake, color: '#bfdbfe' }, // palest
  ];

  if (state.charts.sleepDonut) state.charts.sleepDonut.destroy();
  const ctx = document.getElementById('sleepDonut').getContext('2d');
  state.charts.sleepDonut = new Chart(ctx, {
    type: 'doughnut',
    data: {
      labels: stages.map(s => s.key),
      datasets: [{
        data: stages.map(s => s.value),
        backgroundColor: stages.map(s => s.color),
        borderColor: TOKENS.surface,
        borderWidth: 2,
      }],
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      cutout: '70%',
      animation: { duration: 500 },
      plugins: {
        tooltip: {
          callbacks: {
            label: ctx => `${ctx.label}: ${ctx.parsed.toFixed(2)} h`,
          },
        },
      },
    },
  });

  // Center label
  const total = stages.reduce((s, st) => s + st.value, 0);
  const h = Math.floor(total);
  const m = Math.round((total - h) * 60);
  document.getElementById('sleepDonutCenter').textContent = `${h}:${String(m).padStart(2, '0')}`;

  // Custom legend below the donut
  const legend = document.getElementById('sleepLegend');
  legend.innerHTML = '';
  stages.forEach(s => {
    const li = document.createElement('li');
    li.innerHTML = `
      <span class="swatch" style="background: ${s.color}"></span>
      <span class="legend-key">${s.key}</span>
      <span class="legend-value">${s.value.toFixed(2)} h</span>
    `;
    legend.appendChild(li);
  });
}

// ---------- Daily steps bar ----------

function renderStepsBar() {
  const window = state.metrics.slice(-14); // always show 14 days regardless of period
  const labels = window.map(m => m.date);
  const values = window.map(m => m.steps);
  const todayIdx = window.length - 1;
  // Today's bar = accent yellow; rest = emphasis black
  const colors = window.map((_, i) => i === todayIdx ? TOKENS.accent : TOKENS.emphasis);

  if (state.charts.stepsBar) state.charts.stepsBar.destroy();
  const ctx = document.getElementById('stepsBar').getContext('2d');
  state.charts.stepsBar = new Chart(ctx, {
    type: 'bar',
    data: {
      labels,
      datasets: [{
        data: values,
        backgroundColor: colors,
        borderRadius: 4,
        borderSkipped: false,
      }],
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      animation: { duration: 500 },
      scales: {
        x: {
          grid: { display: false },
          ticks: {
            callback: (v, i) => {
              const d = new Date(labels[i]);
              return d.toLocaleDateString(undefined, { weekday: 'short' });
            },
          },
        },
        y: {
          grid: { color: TOKENS.border, drawBorder: false },
          ticks: {
            callback: v => v >= 1000 ? (v / 1000).toFixed(0) + 'k' : v,
          },
        },
      },
      plugins: {
        tooltip: {
          callbacks: {
            title: items => new Date(items[0].label).toLocaleDateString(undefined, { weekday: 'long', month: 'short', day: 'numeric' }),
            label: ctx => `${ctx.parsed.y.toLocaleString()} steps`,
          },
        },
      },
    },
  });
}

// ---------- Heatmap ----------
//
// GitHub-style: columns = weeks (Mon at top, Sun at bottom), days laid out
// left-to-right oldest-to-newest. Month labels are positioned over the column
// where each new month begins.

function renderHeatmap() {
  const WEEKS = 12;
  const days = state.metrics.slice(-WEEKS * 7);
  const grid = document.getElementById('heatmap');
  const months = document.getElementById('heatmapMonths');
  grid.innerHTML = '';
  months.innerHTML = '';

  // Pad the start so the grid begins on Monday.
  const firstDate = new Date(days[0].date);
  const startDayOfWeek = (firstDate.getDay() + 6) % 7; // Mon = 0 .. Sun = 6
  for (let i = 0; i < startDayOfWeek; i++) {
    const cell = document.createElement('div');
    cell.className = 'heatmap-cell is-pad';
    grid.appendChild(cell);
  }

  // Intensity buckets from strain
  const max = Math.max(...days.map(d => d.strain));
  const bucket = v => v < 1.5 ? 0
                    : v < max * 0.35 ? 1
                    : v < max * 0.6  ? 2
                    : v < max * 0.85 ? 3
                    : 4;

  // Track which week-column each new month starts in (1-indexed for grid-column)
  const monthFirstSeen = {}; // monthKey ("YYYY-MM") -> grid column
  const todayISO = days[days.length - 1].date;
  let totalStrain = 0;

  days.forEach((d, i) => {
    totalStrain += d.strain;

    // Compute the week-column this day will fall into within the grid.
    // (i + startDayOfWeek) is the linear position in the grid; integer-divide by 7 = week column.
    const weekCol = Math.floor((i + startDayOfWeek) / 7) + 1;
    const dateObj = new Date(d.date);
    const monthKey = `${dateObj.getFullYear()}-${dateObj.getMonth()}`;
    if (monthFirstSeen[monthKey] === undefined) {
      monthFirstSeen[monthKey] = { col: weekCol, date: dateObj };
    }

    const cell = document.createElement('div');
    cell.className = 'heatmap-cell';
    cell.dataset.level = bucket(d.strain);
    if (d.date === todayISO) cell.classList.add('is-today');
    const pretty = dateObj.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
    cell.dataset.tooltip = `${pretty} · strain ${d.strain.toFixed(1)}`;
    grid.appendChild(cell);
  });

  // Month labels — only show a label if its column won't crowd the next month's label.
  // (If a month has fewer than ~2 columns visible, skip it.)
  const monthEntries = Object.values(monthFirstSeen).sort((a, b) => a.col - b.col);
  monthEntries.forEach((entry, i) => {
    const nextCol = monthEntries[i + 1]?.col ?? (WEEKS + 1);
    if (nextCol - entry.col < 2) return; // not enough room
    const label = document.createElement('span');
    label.className = 'month-label';
    label.textContent = entry.date.toLocaleDateString(undefined, { month: 'short' });
    label.style.gridColumn = entry.col;
    months.appendChild(label);
  });

  document.getElementById('heatmapTotal').textContent =
    `${days.length} days · cumulative strain ${totalStrain.toFixed(0)}`;
}

// ---------- Workouts table (sortable) ----------

function renderTable() {
  const tbody = document.querySelector('#workoutsTable tbody');
  const ths = document.querySelectorAll('#workoutsTable .th-sortable');
  ths.forEach(th => {
    th.classList.toggle('is-sorted', th.dataset.sort === state.sort.key);
    th.classList.toggle('asc', state.sort.asc);
  });
  ths.forEach(th => {
    th.onclick = () => {
      if (state.sort.key === th.dataset.sort) state.sort.asc = !state.sort.asc;
      else { state.sort.key = th.dataset.sort; state.sort.asc = th.dataset.sort !== 'date' && th.dataset.sort !== 'strain'; }
      renderTable();
    };
  });

  const sorted = [...state.activities].sort((a, b) => {
    const k = state.sort.key;
    let av = a[k], bv = b[k];
    if (k === 'date') { av = new Date(av); bv = new Date(bv); }
    if (av < bv) return state.sort.asc ? -1 : 1;
    if (av > bv) return state.sort.asc ? 1 : -1;
    return 0;
  });

  tbody.innerHTML = '';
  sorted.forEach(w => {
    const tr = document.createElement('tr');
    const date = new Date(w.date).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
    tr.innerHTML = `
      <td>${date}</td>
      <td><span class="workout-name">${w.name}</span></td>
      <td><span class="cat-pill">${w.category}</span></td>
      <td class="td-num">${w.duration_min} min</td>
      <td class="td-num">${w.strain.toFixed(1)}</td>
      <td><span class="status ${w.status.toLowerCase()}">${w.status}</span></td>
    `;
    tbody.appendChild(tr);
  });

  document.getElementById('workoutsCount').textContent = `${state.activities.length} entries`;
}
