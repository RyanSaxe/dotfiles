const SLIDE_WIDTH = 1280;
const SLIDE_HEIGHT = 800;
const PAGE_MARGIN = 72;

function fitSlide() {
  if (window.self !== window.top) {
    document.documentElement.style.setProperty("--slide-scale", "1");
    return;
  }
  const scale = Math.min(
    (window.innerWidth - PAGE_MARGIN) / SLIDE_WIDTH,
    (window.innerHeight - PAGE_MARGIN) / SLIDE_HEIGHT,
    1,
  );
  document.documentElement.style.setProperty("--slide-scale", Math.max(scale, 0.2).toString());
}

window.addEventListener("resize", fitSlide);
fitSlide();
