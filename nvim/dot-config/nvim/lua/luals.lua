-- The ONE place that answers "which directories are typed libraries".
--
-- Both consumers require this: the editor, through the lua_ls settings in
-- plugins/lua.lua, and CI, through dev/luals-check.lua. That is the whole
-- point. They used to answer it separately — `.luarc.json` listed
-- `$VIMRUNTIME/lua`, a shell-style placeholder that only the check script
-- expanded, so the editor ran with no vim runtime types at all and
-- reported hundreds of `Cannot infer type` warnings on code CI called
-- clean. A divergence like that is invisible until someone opens a file.
local M = {}

-- Installed plugins are typed sources (snacks, blink, LazyVim classes).
-- nvim-v2 stays in the list for machines still holding the pre-stow data
-- dir; both resolve to the same config now that nvim is a stowed package.
---@type string[]
local APPNAMES = { "nvim", "nvim-v2" }

---@return string[]
function M.libraries()
  ---@type string[]
  local libraries = { vim.env.VIMRUNTIME .. "/lua" }
  ---@type string
  local data_home = vim.env.XDG_DATA_HOME or (vim.env.HOME .. "/.local/share")
  for _, appname in ipairs(APPNAMES) do
    vim.list_extend(libraries, vim.fn.glob(data_home .. "/" .. appname .. "/lazy/*/lua", true, true))
  end
  return libraries
end

return M
