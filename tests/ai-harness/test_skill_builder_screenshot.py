from __future__ import annotations

import importlib.util
import re
import sys
import types
import unittest
from pathlib import Path
from types import ModuleType
from unittest.mock import patch


REPO_ROOT = Path(__file__).resolve().parents[2]
SCREENSHOT_PATH = (
    REPO_ROOT / "ai-harness" / "skills" / "skill-builder" / "tools" / "screenshot.py"
)


def load_screenshot_module() -> ModuleType:
    playwright_module = types.ModuleType("playwright")
    sync_api_module = types.ModuleType("playwright.sync_api")

    class PlaywrightError(Exception):
        pass

    for name in ("Browser", "BrowserType", "Page", "Playwright"):
        setattr(sync_api_module, name, type(name, (), {}))
    sync_api_module.Error = PlaywrightError
    sync_api_module.sync_playwright = lambda: None

    spec = importlib.util.spec_from_file_location(
        "skill_builder_screenshot", SCREENSHOT_PATH
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {SCREENSHOT_PATH}")
    module = importlib.util.module_from_spec(spec)
    with patch.dict(
        sys.modules,
        {
            "playwright": playwright_module,
            "playwright.sync_api": sync_api_module,
            spec.name: module,
        },
    ):
        spec.loader.exec_module(module)
    return module


class SkillBuilderScreenshotTests(unittest.TestCase):
    def test_run_root_is_unique_under_shared_screenshot_root(self) -> None:
        screenshot = load_screenshot_module()

        run_root = screenshot.make_run_root()

        self.assertEqual(run_root.parent, screenshot.SHOTS_DIR)
        self.assertRegex(run_root.name, re.compile(r"^\d{8}T\d{6}Z-\d+$"))


if __name__ == "__main__":
    unittest.main()
