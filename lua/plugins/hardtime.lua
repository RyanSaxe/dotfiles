-- add a toggle that is disruptive when the user does inefficient vim motions
-- and ensure this feature is off by default

--NOTE: possible should create this as a fun "extras" group in snacks. Need to put more effort into organizing
--      keybinds and toggles in snacks.nvim
local toggleopt = {
  name = "Hardtime",
  keys = "<leader>tv",
  which_key = true,
  get = function()
    return vim.g.hardtime_enabled == 1
  end,
  notify = true,
  set = function(state)
    if state then
      vim.g.hardtime_enabled = 1
      vim.cmd("Hardtime enable")
    else
      vim.g.hardtime_enabled = 0
      vim.cmd("Hardtime disable")
    end
  end,
}

return {
  "m4xshen/hardtime.nvim",
  dependencies = {
    "MunifTanjim/nui.nvim", -- hardtime requirement
    "folke/snacks.nvim", -- for the toggle
  },
  event = "UIEnter",
  config = function()
    -- ensure our flag exists and default to “off”
    vim.g.hardtime_enabled = 0

    -- ensure hardtime is disabled by default and add a snacks toggle for it
    require("hardtime").setup({
      enabled = false,
    })
    require("snacks.toggle").new(toggleopt):map(toggleopt.keys, { mode = { "n", "v" } })
  end,
}
