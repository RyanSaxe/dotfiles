-- Mason is the fallback, never the authority: appended to PATH so a
-- project venv's pinned servers (ty, ruff via uv) — or any deliberate
-- global — win, and mason quietly covers the rest. Check what's
-- actually running with := vim.fn.exepath("ty").
return {
  "mason-org/mason.nvim",
  opts = { PATH = "append" },
}
