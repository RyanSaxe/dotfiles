-- Neovim plugin detector
-- Supports: lazy.nvim, packer.nvim, vim-plug
-- Detects plugins installed in the Neovim data directory

local util = require("dependency-picker.util")

local M = {}

-- Language metadata
M.name = "Neovim"
M.filetypes = { "lua", "vim" }
M.requires_buffer_path = false

-- Detect installed Neovim plugins
-- Checks multiple plugin managers in order of popularity
---@return table|nil { root = string, packages = string[] }
function M.detect()
  local data_path = vim.fn.stdpath("data")

  -- List of plugin managers to check (in order of priority)
  local candidates = {
    { name = "lazy.nvim", path = data_path .. "/lazy" },
    { name = "packer.nvim", path = data_path .. "/site/pack/packer/start" },
    { name = "vim-plug", path = data_path .. "/plugged" },
  }

  -- Find the first existing plugin directory
  for _, candidate in ipairs(candidates) do
    if util.is_directory(candidate.path) then
      -- Get list of plugins (directories only, no hidden files)
      local packages = util.scan_directories(candidate.path)

      if #packages > 0 then
        table.sort(packages)
        return { root = candidate.path, packages = packages }
      end
    end
  end

  return nil
end

return M
