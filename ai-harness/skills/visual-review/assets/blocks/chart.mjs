/**
 * Chart: one bar or line series from the JSON the agent wrote.
 *
 * The shape is deliberately small. A chart in an explanation exists to make one
 * quantity legible, and a grammar with more knobs invites decoration.
 */
import {
  color,
  failed,
  libraries,
  script,
  whenVisible,
} from "../libraries.mjs";

function options(data) {
  return {
    grid: { top: 28, bottom: 42, left: 52, right: 16 },
    xAxis: {
      type: "category",
      data: data.chart.x.map(String),
      name: data.chart.xLabel ?? "",
      nameLocation: "middle",
      nameGap: 26,
      axisLabel: { color: color("--muted") },
      axisLine: { lineStyle: { color: color("--line") } },
    },
    yAxis: {
      type: "value",
      name: data.chart.unit ?? "",
      axisLabel: { color: color("--muted") },
      splitLine: { lineStyle: { color: color("--line") } },
    },
    series: [
      {
        type: data.chart.type,
        data: data.chart.y,
        barWidth: "45%",
        itemStyle: { color: color("--blue") },
        lineStyle: { color: color("--blue") },
        smooth: false,
      },
    ],
    backgroundColor: "transparent",
    textStyle: { color: color("--ink") },
    tooltip: {
      trigger: "axis",
      backgroundColor: color("--panel"),
      borderColor: color("--line"),
      textStyle: { color: color("--ink") },
    },
  };
}

export function chart(mount, data) {
  mount.classList.add("chart-block");
  const title = document.createElement("h3");
  title.textContent = data.title;
  const canvas = document.createElement("div");
  canvas.className = "chart-canvas";
  mount.replaceChildren(...(data.title ? [title] : []), canvas);

  let instance = null;
  const draw = () => instance?.setOption(options(data));
  const stop = whenVisible(mount, async () => {
    try {
      await script(libraries.echarts);
      if (!mount.isConnected) return;
      instance = window.echarts.init(canvas);
      draw();
    } catch (error) {
      failed(mount, error);
    }
  });

  const observer = new ResizeObserver(() => instance?.resize());
  observer.observe(canvas);
  window.addEventListener("vr:theme", draw);

  return {
    dispose() {
      stop();
      observer.disconnect();
      window.removeEventListener("vr:theme", draw);
      instance?.dispose();
    },
  };
}
