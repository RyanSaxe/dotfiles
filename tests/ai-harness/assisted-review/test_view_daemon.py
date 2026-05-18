from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
VIEW_PATH = (
    REPO_ROOT / "ai-harness" / "skills" / "assisted-review" / "tools" / "view.py"
)


class ViewerDaemonTests(unittest.TestCase):
    def test_ensure_reuses_daemon_without_lock_hang(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            env = os.environ.copy()
            env["HOME"] = tmp
            command = [sys.executable, str(VIEW_PATH), "--ensure"]

            try:
                first = subprocess.run(
                    command,
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                self.assertEqual(first.returncode, 0, first.stderr)

                start = time.monotonic()
                second = subprocess.run(
                    command,
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=3,
                )
                elapsed = time.monotonic() - start

                self.assertEqual(second.returncode, 0, second.stderr)
                self.assertLess(elapsed, 2.0)
                self.assertEqual(second.stdout.strip(), first.stdout.strip())
            finally:
                subprocess.run(
                    [sys.executable, str(VIEW_PATH), "--stop"],
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=5,
                )


if __name__ == "__main__":
    unittest.main()
