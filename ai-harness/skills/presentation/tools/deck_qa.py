#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["playwright>=1.52"]
# ///
"""Capture presentation QA screenshots for HTML decks.

Usage:
  uv run --script tools/deck_qa.py <html-file> [<html-file> ...]
  uv run --script tools/deck_qa.py <html-file> --slide 7
  uv run --script tools/deck_qa.py <html-file> --slides 3,4,8-10

Screenshots and diagnostics are written under a unique /tmp directory by
default so concurrent agents can run QA without clobbering each other.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import cast

from playwright.sync_api import (
    Browser,
    BrowserType,
    ConsoleMessage,
    Error as PlaywrightError,
    Page,
    Playwright,
    sync_playwright,
)


DEFAULT_OUTPUT_ROOT = Path("/tmp/presentation-qa")
SCROLL_TOLERANCE_PX = 2
READY_TIMEOUT_MS = 10_000


@dataclass(frozen=True)
class Viewport:
    name: str
    width: int
    height: int


@dataclass(frozen=True)
class ConsoleProblem:
    source: str
    text: str


@dataclass(frozen=True)
class ScrollState:
    width: int
    height: int
    scroll_width: int
    scroll_height: int

    @property
    def has_scroll(self) -> bool:
        return (
            self.scroll_width > self.width + SCROLL_TOLERANCE_PX
            or self.scroll_height > self.height + SCROLL_TOLERANCE_PX
        )


@dataclass(frozen=True)
class ShotResult:
    file: Path
    viewport: Viewport
    directory: Path
    screenshots: tuple[Path, ...]
    is_deck: bool
    problems: tuple[str, ...]


@dataclass(frozen=True)
class CliArgs:
    files: tuple[Path, ...]
    all_slides: bool
    slide: tuple[int, ...]
    slides: tuple[set[int], ...]
    viewports: tuple[Viewport, ...]
    out: Path | None
    fail_on_scroll: bool
    fail_on_console_error: bool


DEFAULT_VIEWPORTS = (
    Viewport("1440x900", 1440, 900),
    Viewport("1280x800", 1280, 800),
    Viewport("1024x768", 1024, 768),
    Viewport("900x600", 900, 600),
    Viewport("768x1024", 768, 1024),
)


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9._-]+", "-", value.strip().lower()).strip("-")
    return slug or "deck"


def browser_missing(error: PlaywrightError) -> bool:
    message = str(error)
    return "Executable doesn't exist" in message or "playwright install" in message


def install_chromium() -> None:
    print(
        "Chromium is missing; running `playwright install chromium`.",
        file=sys.stderr,
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


def parse_viewport(value: str) -> Viewport:
    match = re.fullmatch(r"(\d+)x(\d+)", value.strip())
    if match is None:
        raise argparse.ArgumentTypeError(
            f"invalid viewport {value!r}; expected WIDTHxHEIGHT"
        )
    width = int(match.group(1))
    height = int(match.group(2))
    if width <= 0 or height <= 0:
        raise argparse.ArgumentTypeError("viewport dimensions must be positive")
    return Viewport(f"{width}x{height}", width, height)


def parse_slide_range(value: str) -> set[int]:
    slides: set[int] = set()
    for part in value.split(","):
        token = part.strip()
        if not token:
            continue
        if "-" in token:
            start_raw, end_raw = token.split("-", maxsplit=1)
            start = parse_slide_number(start_raw)
            end = parse_slide_number(end_raw)
            if start > end:
                raise argparse.ArgumentTypeError(
                    f"invalid slide range {token!r}; start is greater than end"
                )
            slides.update(range(start, end + 1))
        else:
            slides.add(parse_slide_number(token))
    if not slides:
        raise argparse.ArgumentTypeError("at least one slide number is required")
    return slides


def parse_slide_number(value: str) -> int:
    try:
        slide = int(value.strip())
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid slide number {value!r}") from exc
    if slide < 1:
        raise argparse.ArgumentTypeError("slide numbers are 1-based")
    return slide


def selected_slides(args: CliArgs) -> set[int] | None:
    explicit_all = args.all_slides
    selected: set[int] = set()
    for slide in args.slide:
        selected.add(slide)
    for group in args.slides:
        selected.update(group)

    if explicit_all and selected:
        raise ValueError("use either --all or --slide/--slides, not both")
    return None if explicit_all or not selected else selected


def output_base_name(file: Path) -> str:
    stem = file.stem
    return slugify(file.parent.name if stem == "index" else stem)


def make_run_root(output_root: Path | None, file: Path) -> Path:
    if output_root is not None:
        return output_root
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return DEFAULT_OUTPUT_ROOT / output_base_name(file) / f"{timestamp}-{os_pid()}"


def os_pid() -> int:
    # Small wrapper keeps the import surface local to the one value we need.
    import os

    return os.getpid()


def wait_for_reveal_ready(page: Page) -> None:
    _ = page.wait_for_function(
        "() => window.Reveal && window.Reveal.isReady && window.Reveal.isReady()",
        timeout=READY_TIMEOUT_MS,
    )
    page.wait_for_timeout(350)


def reveal_slide_count(page: Page) -> int:
    return evaluate_int(page, "() => window.Reveal.getTotalSlides()")


def reveal_slide(page: Page, slide_number: int) -> None:
    evaluate_discard(page, "(index) => window.Reveal.slide(index)", slide_number - 1)
    evaluate_discard(
        page,
        """() => {
          document.querySelectorAll(".present .fragment").forEach((fragment) => {
            fragment.classList.add("visible", "current-fragment");
          });
        }""",
    )
    page.wait_for_timeout(500)


def page_is_reveal_deck(page: Page) -> bool:
    return evaluate_bool(page, "() => typeof window.Reveal !== 'undefined'")


def evaluate_discard(page: Page, script: str, argument: int | None = None) -> None:
    if argument is None:
        _result = cast(object, page.evaluate(script))
    else:
        _result = cast(object, page.evaluate(script, argument))


def evaluate_bool(page: Page, script: str) -> bool:
    value = cast(object, page.evaluate(script))
    if not isinstance(value, bool):
        raise RuntimeError(f"expected JavaScript boolean result, got {type(value)}")
    return value


def evaluate_int(page: Page, script: str) -> int:
    value = cast(object, page.evaluate(script))
    if isinstance(value, bool) or not isinstance(value, int | float):
        raise RuntimeError(f"expected JavaScript number result, got {type(value)}")
    return int(value)


def read_scroll_state(page: Page) -> ScrollState:
    state = cast(
        object,
        page.evaluate(
            """() => {
              const doc = document.documentElement;
              const body = document.body;
              return {
                width: window.innerWidth,
                height: window.innerHeight,
                scrollWidth: Math.max(doc.scrollWidth, body ? body.scrollWidth : 0),
                scrollHeight: Math.max(doc.scrollHeight, body ? body.scrollHeight : 0),
              };
            }"""
        ),
    )
    if not isinstance(state, Mapping):
        raise RuntimeError(f"expected JavaScript object result, got {type(state)}")

    typed_state = cast(Mapping[object, object], state)
    width = mapping_number(typed_state, "width")
    height = mapping_number(typed_state, "height")
    scroll_width = mapping_number(typed_state, "scrollWidth")
    scroll_height = mapping_number(typed_state, "scrollHeight")
    return ScrollState(
        width=width,
        height=height,
        scroll_width=scroll_width,
        scroll_height=scroll_height,
    )


def mapping_number(mapping: Mapping[object, object], key: str) -> int:
    value = mapping.get(key)
    if isinstance(value, bool) or not isinstance(value, int | float):
        raise RuntimeError(f"expected numeric JavaScript field {key!r}")
    return int(value)


def scroll_problem(page: Page, label: str) -> str | None:
    state = read_scroll_state(page)
    if not state.has_scroll:
        return None
    return (
        f"{label}: page scroll detected "
        f"({state.scroll_width}x{state.scroll_height} content in "
        f"{state.width}x{state.height} viewport)"
    )


def console_problem_text(problems: Sequence[ConsoleProblem]) -> list[str]:
    return [f"{problem.source}: {problem.text}" for problem in problems]


def attach_console_tracking(page: Page, problems: list[ConsoleProblem]) -> None:
    def on_console(message: ConsoleMessage) -> None:
        if message.type == "error":
            problems.append(ConsoleProblem("console", message.text))

    def on_page_error(error: Exception) -> None:
        problems.append(ConsoleProblem("pageerror", str(error)))

    page.on("console", on_console)
    page.on("pageerror", on_page_error)


def screenshot_reveal_deck(
    page: Page,
    directory: Path,
    selected: set[int] | None,
    fail_on_scroll: bool,
) -> tuple[tuple[Path, ...], tuple[str, ...]]:
    wait_for_reveal_ready(page)
    total = reveal_slide_count(page)
    if selected is None:
        slide_numbers = list(range(1, total + 1))
    else:
        missing = sorted(slide for slide in selected if slide > total)
        if missing:
            joined = ", ".join(str(slide) for slide in missing)
            raise ValueError(f"slide selection exceeds deck length ({total}): {joined}")
        slide_numbers = sorted(selected)

    screenshots: list[Path] = []
    problems: list[str] = []
    for slide_number in slide_numbers:
        reveal_slide(page, slide_number)
        label = f"slide {slide_number}"
        if fail_on_scroll:
            problem = scroll_problem(page, label)
            if problem is not None:
                problems.append(problem)
        path = directory / f"slide-{slide_number:02d}.png"
        _ = page.screenshot(path=str(path), full_page=False)
        screenshots.append(path)

    return tuple(screenshots), tuple(problems)


def screenshot_page(
    page: Page,
    directory: Path,
    selected: set[int] | None,
    fail_on_scroll: bool,
) -> tuple[tuple[Path, ...], tuple[str, ...]]:
    if selected not in (None, {1}):
        selected_text = ", ".join(str(slide) for slide in sorted(selected))
        message = (
            "slide selection requires a Reveal deck; this page can only be "
            + f"captured as slide 1, got {selected_text}"
        )
        raise ValueError(message)
    page.wait_for_timeout(500)
    problems: list[str] = []
    if fail_on_scroll:
        problem = scroll_problem(page, "page")
        if problem is not None:
            problems.append(problem)
    path = directory / "page.png"
    _ = page.screenshot(path=str(path), full_page=True)
    return (path,), tuple(problems)


def screenshot_file(
    playwright: Playwright,
    file: Path,
    viewport: Viewport,
    output_root: Path,
    selected: set[int] | None,
    fail_on_scroll: bool,
    fail_on_console_error: bool,
) -> ShotResult:
    browser = launch_chromium(playwright.chromium)
    console_problems: list[ConsoleProblem] = []
    try:
        context = browser.new_context(
            viewport={"width": viewport.width, "height": viewport.height},
            device_scale_factor=1,
        )
        page = context.new_page()
        attach_console_tracking(page, console_problems)
        _ = page.goto(file.resolve().as_uri(), wait_until="networkidle")

        is_deck = page_is_reveal_deck(page)
        directory = output_root / viewport.name / output_base_name(file)
        directory.mkdir(parents=True, exist_ok=True)

        if is_deck:
            screenshots, scroll_problems = screenshot_reveal_deck(
                page, directory, selected, fail_on_scroll
            )
        else:
            screenshots, scroll_problems = screenshot_page(
                page, directory, selected, fail_on_scroll
            )

        problems = list(scroll_problems)
        if fail_on_console_error:
            problems.extend(console_problem_text(console_problems))
        context.close()
        return ShotResult(
            file=file,
            viewport=viewport,
            directory=directory,
            screenshots=screenshots,
            is_deck=is_deck,
            problems=tuple(problems),
        )
    finally:
        browser.close()


def validate_files(files: Sequence[Path]) -> list[Path]:
    valid_files: list[Path] = []
    for file in files:
        if not file.exists():
            raise FileNotFoundError(f"{file} does not exist")
        if not file.is_file():
            raise ValueError(f"{file} is not a file")
        valid_files.append(file)
    return valid_files


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Capture QA screenshots for presentation HTML files."
    )
    _ = parser.add_argument("files", nargs="+", type=Path, help="HTML files to capture")
    _ = parser.add_argument(
        "--all",
        action="store_true",
        help="capture every slide; this is the default when no slide is selected",
    )
    _ = parser.add_argument(
        "--slide",
        action="append",
        default=[],
        type=parse_slide_number,
        help="capture a 1-based slide number; repeatable",
    )
    _ = parser.add_argument(
        "--slides",
        action="append",
        default=[],
        type=parse_slide_range,
        help="capture comma-separated slides and ranges, for example 3,4,8-10",
    )
    _ = parser.add_argument(
        "--viewport",
        action="append",
        default=[],
        type=parse_viewport,
        help="viewport as WIDTHxHEIGHT; repeatable",
    )
    _ = parser.add_argument(
        "--out",
        type=Path,
        help="output directory; defaults to a unique /tmp/presentation-qa run",
    )
    _ = parser.add_argument(
        "--fail-on-scroll",
        action="store_true",
        help="exit non-zero if the page scrolls in a captured viewport",
    )
    _ = parser.add_argument(
        "--fail-on-console-error",
        action="store_true",
        help="exit non-zero if the browser reports console or page errors",
    )
    return parser


def parse_args(parser: argparse.ArgumentParser, argv: Sequence[str]) -> CliArgs:
    namespace = parser.parse_args(argv)
    files = namespace_path_tuple(namespace, "files")
    slide = namespace_int_tuple(namespace, "slide")
    slides = namespace_slide_group_tuple(namespace, "slides")
    viewports = namespace_viewport_tuple(namespace, "viewport")
    return CliArgs(
        files=files,
        all_slides=namespace_bool(namespace, "all"),
        slide=slide,
        slides=slides,
        viewports=viewports,
        out=namespace_optional_path(namespace, "out"),
        fail_on_scroll=namespace_bool(namespace, "fail_on_scroll"),
        fail_on_console_error=namespace_bool(namespace, "fail_on_console_error"),
    )


def namespace_value(namespace: argparse.Namespace, name: str) -> object:
    return cast(object, getattr(namespace, name))


def namespace_bool(namespace: argparse.Namespace, name: str) -> bool:
    value = namespace_value(namespace, name)
    if not isinstance(value, bool):
        raise TypeError(f"expected argparse bool for {name}")
    return value


def namespace_optional_path(namespace: argparse.Namespace, name: str) -> Path | None:
    value = namespace_value(namespace, name)
    if value is None or isinstance(value, Path):
        return value
    raise TypeError(f"expected argparse path or None for {name}")


def namespace_path_tuple(
    namespace: argparse.Namespace,
    name: str,
) -> tuple[Path, ...]:
    value = namespace_value(namespace, name)
    if not isinstance(value, list):
        raise TypeError(f"expected argparse path list for {name}")
    items = cast(list[object], value)
    paths: list[Path] = []
    for item in items:
        if not isinstance(item, Path):
            raise TypeError(f"expected argparse path list for {name}")
        paths.append(item)
    return tuple(paths)


def namespace_int_tuple(
    namespace: argparse.Namespace,
    name: str,
) -> tuple[int, ...]:
    value = namespace_value(namespace, name)
    if not isinstance(value, list):
        raise TypeError(f"expected argparse int list for {name}")
    items = cast(list[object], value)
    values: list[int] = []
    for item in items:
        if not isinstance(item, int):
            raise TypeError(f"expected argparse int list for {name}")
        values.append(item)
    return tuple(values)


def namespace_slide_group_tuple(
    namespace: argparse.Namespace,
    name: str,
) -> tuple[set[int], ...]:
    value = namespace_value(namespace, name)
    if not isinstance(value, list):
        raise TypeError(f"expected argparse slide-range list for {name}")
    items = cast(list[object], value)
    slide_groups: list[set[int]] = []
    for item in items:
        slide_group = int_set(item)
        if slide_group is None:
            raise TypeError(f"expected argparse slide-range list for {name}")
        slide_groups.append(slide_group)
    return tuple(slide_groups)


def namespace_viewport_tuple(
    namespace: argparse.Namespace,
    name: str,
) -> tuple[Viewport, ...]:
    value = namespace_value(namespace, name)
    if not isinstance(value, list):
        raise TypeError(f"expected argparse viewport list for {name}")
    items = cast(list[object], value)
    viewports: list[Viewport] = []
    for item in items:
        if not isinstance(item, Viewport):
            raise TypeError(f"expected argparse viewport list for {name}")
        viewports.append(item)
    return tuple(viewports)


def int_set(value: object) -> set[int] | None:
    if not isinstance(value, set):
        return None
    items = cast(set[object], value)
    values: set[int] = set()
    for item in items:
        if not isinstance(item, int):
            return None
        values.add(item)
    return values


def print_result(result: ShotResult) -> None:
    kind = "deck" if result.is_deck else "page"
    print(f"{result.file.name} {result.viewport.name}: {kind} -> {result.directory}")
    for screenshot in result.screenshots:
        print(f"  {screenshot}")
    for problem in result.problems:
        print(f"  ERROR: {problem}", file=sys.stderr)


def main(argv: Sequence[str]) -> int:
    parser = build_parser()
    try:
        args = parse_args(parser, argv)
        files = validate_files(args.files)
        selected = selected_slides(args)
    except (FileNotFoundError, TypeError, ValueError) as exc:
        parser.error(str(exc))

    viewports = args.viewports if args.viewports else DEFAULT_VIEWPORTS
    has_problem = False

    with sync_playwright() as playwright:
        for file in files:
            output_root = make_run_root(args.out, file)
            for viewport in viewports:
                try:
                    result = screenshot_file(
                        playwright=playwright,
                        file=file,
                        viewport=viewport,
                        output_root=output_root,
                        selected=selected,
                        fail_on_scroll=args.fail_on_scroll,
                        fail_on_console_error=args.fail_on_console_error,
                    )
                    print_result(result)
                    has_problem = has_problem or bool(result.problems)
                except (PlaywrightError, RuntimeError, ValueError) as exc:
                    has_problem = True
                    print(
                        f"ERROR: {file} {viewport.name}: {exc}",
                        file=sys.stderr,
                    )

    return 1 if has_problem else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
