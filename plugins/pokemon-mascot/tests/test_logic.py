"""Unit tests for pokemon-mascot's pure logic.

The binary is an extensionless PEP 723 script; load it as a module directly.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import sys
from pathlib import Path

_SPEC = importlib.util.spec_from_loader(
    "herdr_pokemon",
    importlib.machinery.SourceFileLoader(
        "herdr_pokemon", str(Path(__file__).parent.parent / "bin/herdr-pokemon")
    ),
)
assert _SPEC and _SPEC.loader
mascot = importlib.util.module_from_spec(_SPEC)
sys.modules["herdr_pokemon"] = mascot
_SPEC.loader.exec_module(mascot)

# PIL comes through the module under test, keeping this file stdlib-only for
# the type checker (Pillow only exists inside the uv script's environment).
Image = mascot.Image


def pane(pane_id: str, x: int, y: int, width: int, height: int) -> mascot.Pane:
    return mascot.Pane(pane_id=pane_id, x=x, y=y, width=width, height=height)


def test_anchor_picks_bottom_right_most_pane() -> None:
    left = pane("w1:p1", x=0, y=0, width=40, height=40)
    right = pane("w1:p2", x=41, y=0, width=40, height=40)
    assert mascot.anchor_pane([left, right]) == right

    top = pane("w1:p3", x=0, y=0, width=80, height=20)
    bottom = pane("w1:p4", x=0, y=21, width=80, height=19)
    assert mascot.anchor_pane([top, bottom]) == bottom


def test_anchor_prefers_bottom_edge_over_right_edge() -> None:
    tall_right = pane("w1:p1", x=50, y=0, width=30, height=20)
    lower_left = pane("w1:p2", x=0, y=21, width=30, height=20)
    assert mascot.anchor_pane([tall_right, lower_left]) == lower_left


def test_anchor_of_no_panes_is_none() -> None:
    assert mascot.anchor_pane([]) is None


def test_placement_sits_in_bottom_right_corner() -> None:
    result = mascot.placement(pane("p", 0, 0, width=80, height=40), 10, 5)
    assert result == {
        "viewport_col": 69,
        "viewport_row": 34,
        "grid_cols": 10,
        "grid_rows": 5,
    }


def test_placement_clamps_in_tiny_panes() -> None:
    result = mascot.placement(pane("p", 0, 0, width=6, height=3), 10, 5)
    assert result["viewport_col"] == 0
    assert result["viewport_row"] == 0


def test_normalize_crops_and_centers_content() -> None:
    # A 96x96 canvas with a 10x20 blob offset toward the top-left, as real
    # sprites are.
    canvas = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    blob = Image.new("RGBA", (10, 20), (255, 0, 0, 255))
    canvas.paste(blob, (5, 8))

    result = mascot.normalize(canvas)

    assert result.width == result.height  # square
    assert result.height >= 20  # content preserved
    # Content is centered: the visible bbox midpoint is the canvas midpoint.
    box = result.getchannel("A").getbbox()
    assert box is not None
    center_x = (box[0] + box[2]) / 2
    center_y = (box[1] + box[3]) / 2
    assert abs(center_x - result.width / 2) <= 1
    assert abs(center_y - result.height / 2) <= 1


def test_normalize_of_blank_image_does_not_crash() -> None:
    blank = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    assert mascot.normalize(blank).width >= 1


def test_focused_tab_panes_reads_snapshot_shape() -> None:
    snapshot = {
        "focused_tab_id": "w1:t1",
        "layouts": [
            {
                "tab_id": "w1:t1",
                "panes": [
                    {
                        "pane_id": "w1:p1",
                        "rect": {"x": 0, "y": 0, "width": 40, "height": 20},
                    }
                ],
            },
            {"tab_id": "w1:t2", "panes": []},
        ],
    }
    panes = mascot.focused_tab_panes(snapshot)
    assert panes == [pane("w1:p1", 0, 0, 40, 20)]
