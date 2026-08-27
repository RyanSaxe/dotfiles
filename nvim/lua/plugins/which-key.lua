-- The leader popup must feel instant; the stock 200ms delay reads as
-- lag. Everything else keeps a delay, so ordinary operator sequences
-- like `dd` or `ci"` do not flash a popup mid-keystroke.
return {
  "folke/which-key.nvim",
  ---@param opts wk.Opts
  ---@return wk.Opts
  opts = function(_, opts)
    local util = require("which-key.util")
    ---@param ctx { keys: string, plugin?: string }
    ---@return number
    opts.delay = function(ctx)
      if ctx.plugin then
        return 0
      end
      if ctx.keys == util.norm("<leader>") or ctx.keys == util.norm("<localleader>") then
        return 0
      end
      return 200
    end
    return opts
  end,
}
