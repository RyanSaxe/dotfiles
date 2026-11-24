from __future__ import annotations

import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def test_pulse_frame_clears_reliably_across_recording_stop_cycles() -> None:
    lua_probe = """
local pulse = require("theme.pulse")
pulse.setup()
for i = 1, 20 do
  vim.api.nvim_exec_autocmds("RecordingEnter", {})
  vim.wait(60)
  vim.api.nvim_exec_autocmds("RecordingLeave", {})
  vim.wait(20)
  local f = pulse.frame()
  if f ~= nil then
    io.stderr:write(("cycle %d stuck at %s\\n"):format(i, f))
    os.exit(1)
  end
end
"""
    res = subprocess.run(
        ["nvim", "--clean", "--headless", "-u", "NONE", "--cmd", f"set rtp+={REPO / 'config/nvim'}", "-l", "-"],
        input=lua_probe,
        capture_output=True,
        text=True,
        check=False,
        timeout=20,
    )
    assert res.returncode == 0, res.stdout + res.stderr
