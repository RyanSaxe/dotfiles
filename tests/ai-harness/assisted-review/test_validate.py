from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType

REPO_ROOT = Path(__file__).resolve().parents[3]
TOOLS_DIR = REPO_ROOT / "ai-harness" / "skills" / "assisted-review" / "tools"
sys.path.insert(0, str(TOOLS_DIR))


def load_module(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


review_state = load_module("review_state", TOOLS_DIR / "review_state.py")
validate = load_module("validate", TOOLS_DIR / "validate.py")
current_repo_fingerprint = review_state.current_repo_fingerprint


def git(repo: Path, *args: str) -> str:
    proc = subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        check=True,
    )
    return proc.stdout.strip()


class ValidateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.reviews_dir = self.root / "reviews"
        self.reviews_dir.mkdir()
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.email", "review@example.com")
        git(self.repo, "config", "user.name", "Review Test")
        (self.repo / "app.py").write_text("one\ntwo\n", encoding="utf-8")
        git(self.repo, "add", "app.py")
        git(self.repo, "commit", "-q", "-m", "initial")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def write_review(
        self,
        *,
        fingerprint: str | None = None,
        commit: str | None = None,
        body_header: str = "|-",
        anchor_header: str = "|-",
        suggestion_header: str = "|-",
    ) -> Path:
        fingerprint = fingerprint or current_repo_fingerprint(self.repo)
        if fingerprint is None:
            raise RuntimeError("could not fingerprint test repo")
        commit = commit or git(self.repo, "rev-parse", "HEAD")
        path = self.reviews_dir / "review.review.yaml"
        path.write_text(
            f"""generated_at: 2026-05-05T09:12:00Z
generated_by: codex

target:
  kind: local
  repo_root: {self.repo}
  branch: main
  commit: {commit}
  fingerprint: {fingerprint}

review:
  event: COMMENT
  summary:
    author: ai
    body: {body_header}
      Summary text.
    replies: []
  note:
    author: ai
    body: {body_header}
      Local note.
    replies: []
  threads:
    - id: rev-001
      type: comment
      author: ai
      file: app.py
      line: 2
      severity: medium
      confidence: high
      category: correctness
      body: {body_header}
        Finding body.
      suggestion: {suggestion_header}
        three
      status: open
      anchor_text: {anchor_header}
        two
      anchor_status: current
      replies:
        - author: user
          body: {body_header}
            Reply body.
""",
            encoding="utf-8",
        )
        return path

    def test_require_current_state_accepts_fresh_canonical_review(self) -> None:
        path = self.write_review()

        self.assertEqual(validate.validate(path, require_current_state=True), [])

    def test_schema_only_accepts_stale_but_well_formed_fingerprint(self) -> None:
        path = self.write_review(fingerprint="a" * 64)

        self.assertEqual(validate.validate(path), [])

    def test_require_current_fingerprint_rejects_stale_fingerprint(self) -> None:
        path = self.write_review(fingerprint="a" * 64)

        errors = validate.validate(path, require_current_fingerprint=True)

        self.assertIn(
            "target.fingerprint does not match current repo state",
            "\n".join(errors),
        )

    def test_canonical_yaml_rejects_plain_literal_block(self) -> None:
        path = self.write_review(anchor_header="|")

        errors = validate.validate(path, require_canonical_yaml=True)

        self.assertIn(
            "review.threads[0].anchor_text must use strip chomping style `|-`",
            "\n".join(errors),
        )

    def test_canonical_yaml_rejects_folded_block(self) -> None:
        path = self.write_review(body_header=">")

        errors = validate.validate(path, require_canonical_yaml=True)

        self.assertIn(
            "review.summary.body must use a literal block scalar using `|-`",
            "\n".join(errors),
        )

    def test_canonical_yaml_rejects_non_stripping_suggestion(self) -> None:
        path = self.write_review(suggestion_header="|")

        errors = validate.validate(path, require_canonical_yaml=True)

        self.assertIn(
            "review.threads[0].suggestion must use strip chomping style `|-`",
            "\n".join(errors),
        )


if __name__ == "__main__":
    unittest.main()
