const SLIDE_WIDTH = 1280;
const SLIDE_HEIGHT = 800;
const PAGE_MARGIN = 48;

function fitSlide() {
  if (window.self !== window.top) {
    document.documentElement.style.setProperty("--slide-scale", "1");
    return;
  }
  const margin = PAGE_MARGIN;
  const scale = Math.min(
    (window.innerWidth - margin) / SLIDE_WIDTH,
    (window.innerHeight - margin) / SLIDE_HEIGHT,
    1,
  );
  document.documentElement.style.setProperty("--slide-scale", Math.max(scale, 0.2).toString());
}

window.addEventListener("resize", fitSlide);
fitSlide();
