#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Render `tmux capture-pane -e` output to a PNG.

The rail's look-iteration loop: run the rail in a detached tmux pane,
capture it with escape sequences, render the capture to pixels, and compare
against the gold standard by eye. Only SGR truecolor/256/reset sequences are
interpreted — exactly what capture-pane emits.

    tmux capture-pane -ep -t rail-pane | uv run -q --script ansi2png.py out.png
"""

import re
import sys

from PIL import Image, ImageDraw, ImageFont

FONT_PATH = "/System/Library/Fonts/Menlo.ttc"
FONT_SIZE = 14
# Terminal default colors when a cell carries no explicit SGR color: catppuccin
# mocha base/text, so unpainted cells look exactly as they would in ghostty.
DEFAULT_BG = (30, 30, 46)
DEFAULT_FG = (205, 214, 244)

ANSI_256: list[tuple[int, int, int]] = []
for i in range(16):
    base = [
        (0, 0, 0),
        (205, 0, 0),
        (0, 205, 0),
        (205, 205, 0),
        (0, 0, 238),
        (205, 0, 205),
        (0, 205, 205),
        (229, 229, 229),
        (127, 127, 127),
        (255, 0, 0),
        (0, 255, 0),
        (255, 255, 0),
        (92, 92, 255),
        (255, 0, 255),
        (0, 255, 255),
        (255, 255, 255),
    ]
    ANSI_256.append(base[i])
for r in range(6):
    for g in range(6):
        for b in range(6):
            scale = lambda v: 0 if v == 0 else 55 + v * 40
            ANSI_256.append((scale(r), scale(g), scale(b)))
for i in range(24):
    v = 8 + i * 10
    ANSI_256.append((v, v, v))

SGR = re.compile(r"\x1b\[([0-9;]*)m")


def parse(text: str) -> list[list[tuple[str, tuple, tuple]]]:
    """Each cell: (char, fg_rgb, bg_rgb). SGR state persists across lines,
    exactly as the terminal treats a capture-pane stream."""
    lines = []
    fg, bg = DEFAULT_FG, DEFAULT_BG
    raw_lines = text.split("\n")
    if raw_lines and raw_lines[-1] == "":
        raw_lines.pop()
    for raw in raw_lines:
        cells = []
        pos = 0
        for match in SGR.finditer(raw):
            for ch in raw[pos : match.start()]:
                cells.append((ch, fg, bg))
            pos = match.end()
            params = [int(p) for p in match.group(1).split(";") if p] or [0]
            i = 0
            while i < len(params):
                p = params[i]
                if p == 0:
                    fg, bg = DEFAULT_FG, DEFAULT_BG
                elif p == 39:
                    fg = DEFAULT_FG
                elif p == 49:
                    bg = DEFAULT_BG
                elif p in (38, 48) and i + 1 < len(params):
                    target = "fg" if p == 38 else "bg"
                    if params[i + 1] == 2 and i + 4 < len(params):
                        color = tuple(params[i + 2 : i + 5])
                        i += 4
                    elif params[i + 1] == 5 and i + 2 < len(params):
                        color = ANSI_256[params[i + 2]]
                        i += 2
                    else:
                        i += 1
                        continue
                    if target == "fg":
                        fg = color
                    else:
                        bg = color
                elif 30 <= p <= 37:
                    fg = ANSI_256[p - 30]
                elif 40 <= p <= 47:
                    bg = ANSI_256[p - 40]
                elif 90 <= p <= 97:
                    fg = ANSI_256[p - 90 + 8]
                elif 100 <= p <= 107:
                    bg = ANSI_256[p - 100 + 8]
                i += 1
        for ch in raw[pos:]:
            cells.append((ch, fg, bg))
        lines.append(cells)
    return lines


def render(grid: list, out_path: str) -> None:
    font = ImageFont.truetype(FONT_PATH, FONT_SIZE)
    cell_w = round(font.getlength("M"))
    cell_h = round(FONT_SIZE * 1.35)
    cols = max((len(line) for line in grid), default=1)
    img = Image.new("RGB", (cols * cell_w, len(grid) * cell_h), DEFAULT_BG)
    draw = ImageDraw.Draw(img)
    for row, cells in enumerate(grid):
        for col, (ch, fg, bg) in enumerate(cells):
            x, y = col * cell_w, row * cell_h
            draw.rectangle([x, y, x + cell_w - 1, y + cell_h - 1], fill=tuple(bg))
            if ch != " ":
                draw.text((x, y + 1), ch, font=font, fill=tuple(fg))
    img.save(out_path)
    print(f"{out_path}: {cols}x{len(grid)} cells")


if __name__ == "__main__":
    render(parse(sys.stdin.read()), sys.argv[1])
