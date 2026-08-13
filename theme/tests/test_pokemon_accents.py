"""Unit tests for pokemon-accents' pure logic.

The binary is an extensionless PEP 723 script; load it as a module directly.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import sys
from pathlib import Path

_SPEC = importlib.util.spec_from_loader(
    "pokemon_accents",
    importlib.machinery.SourceFileLoader(
        "pokemon_accents",
        str(Path(__file__).parent.parent / ".local/bin/pokemon-accents"),
    ),
)
assert _SPEC and _SPEC.loader
accents = importlib.util.module_from_spec(_SPEC)
sys.modules["pokemon_accents"] = accents
_SPEC.loader.exec_module(accents)

# PIL comes through the module under test, keeping this file stdlib-only for
# the type checker (Pillow only exists inside the uv script's environment).
Image = accents.Image


def test_normalize_crops_centers_and_scales() -> None:
    # A 96x96 canvas with a 10x20 blob offset toward the top-left, as real
    # sprites are.
    canvas = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    blob = Image.new("RGBA", (10, 20), (255, 0, 0, 255))
    canvas.paste(blob, (5, 8))

    result = accents.normalize(canvas)

    assert result.width == result.height  # square
    assert result.height >= 20 * accents.MASCOT_SCALE  # content preserved, scaled
    # Content is centered: the visible bbox midpoint is the canvas midpoint.
    box = result.getchannel("A").getbbox()
    assert box is not None
    center_x = (box[0] + box[2]) / 2
    center_y = (box[1] + box[3]) / 2
    assert abs(center_x - result.width / 2) <= accents.MASCOT_SCALE
    assert abs(center_y - result.height / 2) <= accents.MASCOT_SCALE


def test_normalize_of_blank_image_does_not_crash() -> None:
    blank = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    assert accents.normalize(blank).width >= 1


def _pixels_of(image: accents.Image.Image) -> tuple[list, list]:
    vivid, pale = [], []
    for x in range(image.width):
        for y in range(image.height):
            r, g, b, a = image.getpixel((x, y))
            if a <= 128:
                continue
            h, s, v = accents.colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if not (0.2 < v <= 0.98):
                continue
            (vivid if s >= 0.25 else pale if s >= 0.10 else []).append((h, s, v))
    return vivid, pale


def test_pick_pair_finds_two_distinct_hues() -> None:
    # A synthetic gengar: a large purple body with small red eyes. The pair
    # must be the two hues, never two shades of purple.
    # Eyes sized to clear the 2%-of-primary noise threshold honestly — the
    # old 8x4 version only "passed" via the now-dead complement fallback.
    image = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    image.paste(Image.new("RGBA", (60, 60), (140, 100, 220, 255)), (18, 18))  # purple
    image.paste(Image.new("RGBA", (16, 8), (220, 40, 40, 255)), (40, 30))  # red eyes

    accent, accent_bright = accents.pick_pair(*_pixels_of(image))

    hue_distance = abs(accent[0] - accent_bright[0])
    hue_distance = min(hue_distance, 1 - hue_distance)
    assert hue_distance >= 45 / 360  # genuinely different hues


def test_pick_pair_relaxes_to_nearby_hue_over_inventing_one() -> None:
    # A synthetic shiny gyarados: red body, gold fins ~35 degrees away —
    # closer than the strict 45-degree tier, but REAL. The pair must be
    # red + gold, never red + a synthesized complement (teal).
    image = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    image.paste(Image.new("RGBA", (60, 60), (216, 60, 50, 255)), (18, 18))  # red
    image.paste(Image.new("RGBA", (20, 10), (230, 180, 60, 255)), (30, 80))  # gold

    _accent, accent_bright = accents.pick_pair(*_pixels_of(image))

    gold_hue = accents.colorsys.rgb_to_hsv(230 / 255, 180 / 255, 60 / 255)[0]
    assert abs(accent_bright[0] - gold_hue) < 0.06  # the gold, not teal


def test_pick_pair_single_hue_never_invents_a_color() -> None:
    image = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    image.paste(Image.new("RGBA", (60, 60), (216, 60, 50, 255)), (18, 18))  # red only

    accent, accent_bright = accents.pick_pair(*_pixels_of(image))

    assert accent_bright[0] == accent[0]  # same hue, not a complement


def test_styled_output_is_valid_hex() -> None:
    color = (0.75, 0.6, 0.8)
    for dark in (True, False):
        for bright in (True, False):
            value = accents.styled(color, dark_background=dark, bright=bright)
            assert len(value) == 7 and value.startswith("#")
            int(value[1:], 16)
