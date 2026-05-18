"""Regression tests for the repo_size utility."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = REPO_ROOT / "scripts"


def load_module(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


repo_size = load_module("repo_size", SCRIPTS_DIR / "repo_size.py")


class RepoSizeTests(unittest.TestCase):
    def run_git(self, root: Path, *args: str) -> None:
        subprocess.run(
            ["git", "-C", str(root), *args],
            check=True,
            capture_output=True,
            text=True,
        )

    def sample_repo(self) -> tempfile.TemporaryDirectory[str]:
        tmp = tempfile.TemporaryDirectory()
        root = Path(tmp.name)
        self.run_git(root, "init")
        (root / ".gitignore").write_text("ignored.txt\n")
        (root / "docs.md").write_text("hello\nworld")
        (root / "ignored.txt").write_text("ignored\n")
        (root / "image.bin").write_bytes(b"\0binary")
        source = root / "src" / "app.py"
        source.parent.mkdir()
        source.write_text("print('hello')\n")
        self.run_git(root, "add", ".gitignore", "docs.md", "image.bin", "src/app.py")
        return tmp

    def test_loc_counts_git_visible_text_files(self) -> None:
        with self.sample_repo() as tmp:
            tree = repo_size.build_loc_tree(tmp)

        self.assertEqual(tree.loc, 4)
        self.assertEqual(tree.children["docs.md"].loc, 2)
        self.assertEqual(tree.children["src"].loc, 1)
        self.assertNotIn("ignored.txt", tree.children)
        self.assertNotIn("image.bin", tree.children)

    def test_tokens_count_uses_o200k_base_for_git_visible_text(self) -> None:
        with self.sample_repo() as tmp:
            tree = repo_size.build_token_tree(tmp)

        encoding = repo_size.get_token_encoding()
        expected = sum(
            len(encoding.encode(text, disallowed_special=()))
            for text in ("ignored.txt\n", "hello\nworld", "print('hello')\n")
        )
        self.assertEqual(tree.tokens, expected)

    def test_tokens_rendering_uses_tokens_header(self) -> None:
        with self.sample_repo() as tmp:
            tree = repo_size.build_token_tree(tmp)

        rendered = repo_size.render_tree(
            tree,
            depth=1,
            mode="tokens",
            colors=repo_size.Colors(enabled=False),
        )
        self.assertIn("TOKENS", rendered)
        self.assertIn("src", rendered)


if __name__ == "__main__":
    unittest.main()
