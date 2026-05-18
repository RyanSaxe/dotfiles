from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
STYLE_PATH = (
    REPO_ROOT
    / "ai-harness"
    / "skills"
    / "assisted-review"
    / "tools"
    / "webapp"
    / "style.css"
)


class ViewerWebappCssTests(unittest.TestCase):
    def test_diff_rows_preserve_code_text_color(self) -> None:
        css = STYLE_PATH.read_text(encoding="utf-8")

        self.assertIn(
            ".code-table.diff-overlay-on tr.diff-added-line td.code-cell {\n"
            "  color: var(--code-text);\n"
            "}",
            css,
        )
        self.assertIn(
            ".code-table tr.diff-deleted-line td.code-cell {\n"
            "  color: var(--code-text);\n"
            "  text-decoration: none;\n"
            "}",
            css,
        )
        self.assertNotIn(
            ".code-table.diff-overlay-on tr.diff-added-line td.gutter-num,\n"
            ".code-table.diff-overlay-on tr.diff-added-line td.code-cell {\n"
            "  background: #ecfdf3;\n"
            "  color: #15803d;\n"
            "}",
            css,
        )


if __name__ == "__main__":
    unittest.main()
