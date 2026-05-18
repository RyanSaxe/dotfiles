from __future__ import annotations

import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "ai-harness" / "scripts" / "attention-daemon.sh"


def wait_for_pid_file(path: Path, process: subprocess.Popen[str]) -> None:
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        if path.exists():
            return
        if process.poll() is not None:
            raise AssertionError(
                f"daemon exited early with {process.returncode}: {process.stderr.read()}"
            )
        time.sleep(0.05)
    raise AssertionError("daemon did not write pid file")


class AttentionDaemonTests(unittest.TestCase):
    def test_second_start_exits_without_replacing_live_lock(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            fake_tmux = bin_dir / "tmux"
            fake_tmux.write_text("#!/usr/bin/env zsh\nexit 0\n", encoding="utf-8")
            fake_tmux.chmod(0o755)

            cache_home = root / "cache"
            pid_file = cache_home / "ai-harness" / "tmux-attention-daemon.pid"
            env = os.environ.copy()
            env["XDG_CACHE_HOME"] = str(cache_home)
            env["PATH"] = f"{bin_dir}{os.pathsep}{env['PATH']}"
            env["AI_HARNESS_TMUX_ATTENTION_INTERVAL"] = "60"

            first = subprocess.Popen(
                ["zsh", str(SCRIPT_PATH)],
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            try:
                wait_for_pid_file(pid_file, first)
                self.assertIsNone(first.poll())

                second = subprocess.run(
                    ["zsh", str(SCRIPT_PATH)],
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=3,
                )

                self.assertEqual(second.returncode, 0, second.stderr)
                self.assertIsNone(first.poll())
                self.assertEqual(
                    pid_file.read_text(encoding="utf-8").strip(), str(first.pid)
                )
            finally:
                first.terminate()
                try:
                    first.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    first.kill()
                    first.wait(timeout=3)


if __name__ == "__main__":
    unittest.main()
