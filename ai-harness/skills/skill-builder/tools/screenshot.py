#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["playwright>=1.52"]
# ///
"""Capture visual self-review screenshots for generated HTML artifacts.

Usage:
  uv run --script tools/screenshot.py <html-file> [<html-file> ...]

Each HTML file is opened in headless Chromium at three viewports. Screenshots
land in /tmp/skill-screenshots/<timestamp>-<pid>/<viewport>/<basename>/.

If the page exposes window.Reveal, every slide is screenshotted with fragments
shown. Otherwise the tool captures one full-page screenshot.
"""

from __future__ import annotations

import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from os import getpid
from pathlib import Path
from typing import Sequence

from playwright.sync_api import (
    Browser,
    BrowserType,
    Error as PlaywrightError,
    Page,
    Playwright,
    sync_playwright,
)


SHOTS_DIR = Path("/tmp/skill-screenshots")


@dataclass(frozen=True)
class Viewport:
    name: str
    width: int
    height: int


@dataclass(frozen=True)
class ShotResult:
    count: int
    is_deck: bool
    directory: Path


VIEWPORTS = (
    Viewport("16x9", 1280, 800),
    Viewport("wide", 1920, 1080),
    Viewport("portrait", 900, 1200),
)


def browser_missing(error: PlaywrightError) -> bool:
    message = str(error)
    return "Executable doesn't exist" in message or "playwright install" in message


def install_chromium() -> None:
    print(
        "Chromium is missing; running `playwright install chromium`.", file=sys.stderr
    )
    result = subprocess.run(
        [sys.executable, "-m", "playwright", "install", "chromium"],
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError("failed to install Playwright Chromium")


def launch_chromium(chromium: BrowserType) -> Browser:
    try:
        return chromium.launch()
    except PlaywrightError as exc:
        if not browser_missing(exc):
            raise
        install_chromium()
        return chromium.launch()


def output_base_name(file: Path) -> str:
    stem = file.stem
    return file.parent.name if stem == "index" else stem


def make_run_root() -> Path:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return SHOTS_DIR / f"{timestamp}-{getpid()}"


def shoot_deck(page: Page, directory: Path) -> int:
    page.wait_for_function(
        "() => window.Reveal && window.Reveal.isReady && window.Reveal.isReady()"
    )
    page.wait_for_timeout(400)

    total = int(page.evaluate("() => window.Reveal.getTotalSlides()"))
    for idx in range(total):
        page.evaluate("(slideIndex) => window.Reveal.slide(slideIndex)", idx)
        page.evaluate(
            """() => {
              document.querySelectorAll(".present .fragment").forEach((fragment) => {
                fragment.classList.add("visible", "current-fragment");
              });
            }"""
        )
        page.wait_for_timeout(700)
        page.screenshot(
            path=str(directory / f"slide-{idx + 1:02d}.png"),
            full_page=False,
        )

    return total


def shoot_page(page: Page, directory: Path) -> int:
    page.wait_for_timeout(700)
    page.screenshot(path=str(directory / "page.png"), full_page=True)
    return 1


def shoot(
    playwright: Playwright,
    file: Path,
    viewport: Viewport,
    run_root: Path,
) -> ShotResult:
    browser = launch_chromium(playwright.chromium)
    try:
        context = browser.new_context(
            viewport={"width": viewport.width, "height": viewport.height},
            device_scale_factor=1,
        )
        page = context.new_page()
        page.goto(file.resolve().as_uri(), wait_until="networkidle")

        is_deck = bool(page.evaluate("() => typeof window.Reveal !== 'undefined'"))
        directory = run_root / viewport.name / output_base_name(file.resolve())
        directory.mkdir(parents=True, exist_ok=True)

        count = shoot_deck(page, directory) if is_deck else shoot_page(page, directory)
        context.close()
        return ShotResult(count=count, is_deck=is_deck, directory=directory)
    finally:
        browser.close()


def main(argv: Sequence[str]) -> int:
    files = [Path(arg) for arg in argv]
    if not files:
        print(
            "Usage: uv run --script screenshot.py <html-file> [<html-file> ...]",
            file=sys.stderr,
        )
        return 2

    run_root = make_run_root()

    with sync_playwright() as playwright:
        for file in files:
            if not file.exists() or not file.is_file():
                print(f"skip: {file} not found", file=sys.stderr)
                continue
            for viewport in VIEWPORTS:
                result = shoot(playwright, file, viewport, run_root)
                kind = f"{result.count} slides" if result.is_deck else "full page"
                print(f"{file.name} {viewport.name}: {kind} -> {result.directory}/")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
