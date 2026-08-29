"""Unit tests for mascot-accents' pure logic.

The binary is a PEP 723 script; load it as a module directly.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import sys
from collections.abc import Callable
from pathlib import Path
from typing import Any

_SPEC = importlib.util.spec_from_loader(
    "mascot_accents",
    importlib.machinery.SourceFileLoader(
        "mascot_accents",
        str(Path(__file__).parent.parent.parent / "theme/bin/mascot-accents.py"),
    ),
)
assert _SPEC and _SPEC.loader
accents = importlib.util.module_from_spec(_SPEC)
sys.modules["mascot_accents"] = accents
_SPEC.loader.exec_module(accents)

# PIL comes through the module under test, keeping this file stdlib-only for
# the type checker (Pillow only exists inside the uv script's environment).
Image = accents.Image


def local_mascot_dir(tmp_path: Path, monkeypatch: Any) -> Path:
    data_home = tmp_path / "data"
    monkeypatch.setenv("XDG_DATA_HOME", str(data_home))
    return data_home / "dotfiles/mascots"


def test_registry_resolves_qualified_identities() -> None:
    provider, identity = accents.resolve("pokemon:raikou")
    assert provider is accents.PROVIDERS["pokemon"]
    assert identity == "raikou"
    # Shiny is its own registered picker entry, not a flag.
    assert "shiny-pokemon" in accents.PROVIDERS


def test_local_provider_lists_png_filenames(tmp_path: Path, monkeypatch: Any) -> None:
    mascot_dir = local_mascot_dir(tmp_path, monkeypatch)
    mascot_dir.mkdir(parents=True)
    Image.new("RGBA", (8, 8), (40, 80, 220, 255)).save(mascot_dir / "cat.png")
    (mascot_dir / "notes.txt").write_text("not a mascot")

    assert accents.PROVIDERS["local"].identities() == ["cat.png"]


def test_local_provider_resolves_a_png_fixture(
    tmp_path: Path, monkeypatch: Any
) -> None:
    mascot_dir = local_mascot_dir(tmp_path, monkeypatch)
    mascot_dir.mkdir(parents=True)
    source = mascot_dir / "cat.png"
    Image.new("RGBA", (8, 8), (40, 80, 220, 255)).save(source)

    provider, identity = accents.resolve("local:cat.png")
    images = provider.fetch(identity)

    assert images == accents.MascotImages(sprite=source, palette=source)


def test_local_provider_reports_a_missing_png(tmp_path: Path, monkeypatch: Any) -> None:
    mascot_dir = local_mascot_dir(tmp_path, monkeypatch)
    mascot_dir.mkdir(parents=True)

    message = _exit_message(lambda: accents.PROVIDERS["local"].fetch("missing.png"))

    assert "local mascot PNG not found: missing.png" in message


def _exit_message(action: Callable[[], object]) -> str:
    # SystemExit instead of pytest.raises keeps this file stdlib-only for
    # the type checker (see the loader note above).
    try:
        action()
    except SystemExit as error:
        return str(error)
    raise AssertionError("expected SystemExit")


def test_resolve_rejects_unqualified_and_unknown_values() -> None:
    assert "not provider-qualified" in _exit_message(lambda: accents.resolve("raikou"))
    assert "unknown provider" in _exit_message(
        lambda: accents.resolve("digimon:agumon")
    )


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

    accent, notify = accents.pick_pair(*_pixels_of(image))

    hue_distance = abs(accent[0] - notify[0])
    hue_distance = min(hue_distance, 1 - hue_distance)
    assert hue_distance >= 45 / 360  # genuinely different hues


def test_pick_pair_relaxes_to_nearby_hue_over_inventing_one() -> None:
    # A synthetic shiny gyarados: red body, gold fins ~35 degrees away —
    # closer than the strict 45-degree tier, but REAL. The pair must be
    # red + gold, never red + a synthesized complement (teal).
    image = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    image.paste(Image.new("RGBA", (60, 60), (216, 60, 50, 255)), (18, 18))  # red
    image.paste(Image.new("RGBA", (20, 10), (230, 180, 60, 255)), (30, 80))  # gold

    _accent, notify = accents.pick_pair(*_pixels_of(image))

    gold_hue = accents.colorsys.rgb_to_hsv(230 / 255, 180 / 255, 60 / 255)[0]
    assert abs(notify[0] - gold_hue) < 0.06  # the gold, not teal


def test_pick_pair_single_hue_never_invents_a_color() -> None:
    image = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    image.paste(Image.new("RGBA", (60, 60), (216, 60, 50, 255)), (18, 18))  # red only

    accent, notify = accents.pick_pair(*_pixels_of(image))

    assert notify[0] == accent[0]  # same hue, not a complement


def test_qualified_values_cover_every_registered_provider() -> None:
    def unused_fetch(name: str) -> object:
        raise AssertionError("fetch is not part of value listing")

    shared_names = ["raikou", "mew"]
    registry = {
        "pokemon": accents.Provider(lambda: shared_names, unused_fetch),
        "shiny-pokemon": accents.Provider(lambda: shared_names, unused_fetch),
    }

    values = accents.qualified_values(registry)

    assert values == [
        "pokemon:raikou",
        "pokemon:mew",
        "shiny-pokemon:raikou",
        "shiny-pokemon:mew",
    ]


def test_fetch_failures_exit_with_one_line_errors() -> None:
    def raise_http_404() -> object:
        raise accents.HTTPError("https://example", 404, "Not Found", None, None)

    def raise_offline() -> object:
        raise accents.URLError("no route to host")

    # The contract: one line, naming what failed and why. The phrasing
    # around those parts is free to change.
    message = _exit_message(
        lambda: accents.fetch_or_exit(raise_http_404, "'pokemon:badmon'")
    )
    assert "\n" not in message
    assert "'pokemon:badmon'" in message
    assert "404" in message and "Not Found" in message

    message = _exit_message(
        lambda: accents.fetch_or_exit(raise_offline, "'pokemon:mew'")
    )
    assert "\n" not in message
    assert "'pokemon:mew'" in message
    assert "no route to host" in message


def test_styled_output_is_valid_hex() -> None:
    color = (0.75, 0.6, 0.8)
    for dark in (True, False):
        for bright in (True, False):
            value = accents.styled(color, dark_background=dark, bright=bright)
            assert len(value) == 7 and value.startswith("#")
            int(value[1:], 16)
