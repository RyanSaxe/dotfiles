local util = require("dependency-picker.util")

local M = {}

M.name = "Neovim"
M.filetypes = { "lua", "vim" }
M.requires_buffer_path = false
M.file_extensions = { "lua", "vim" }  -- Both Lua and Vimscript

---@return table|nil { root = string, packages = string[] }
function M.detect()
  local data_path = vim.fn.stdpath("data")

  local candidates = {
    { name = "lazy.nvim", path = data_path .. "/lazy" },
    { name = "packer.nvim", path = data_path .. "/site/pack/packer/start" },
    { name = "vim-plug", path = data_path .. "/plugged" },
  }

  for _, candidate in ipairs(candidates) do
    if util.is_directory(candidate.path) then
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
