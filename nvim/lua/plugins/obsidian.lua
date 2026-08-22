-- The vault surface: daily notes, links, and backlinks over $VAULT_DIR.
-- The maintained obsidian-nvim fork, not epwalsh's archived original. No
-- mapping opens the Obsidian application; this vault is Markdown and git,
-- and Neovim is the only editor of it.
--
-- Every non-default below is load-bearing:
--
--   strict          pins the vault root. Without it `find_vault_root` walks
--                   UPWARD for a .obsidian/ directory, so one sitting
--                   anywhere above the vault silently relocates the root.
--   frontmatter     off, or a BufWritePre autocmd rewrites id/aliases/tags
--                   into every Markdown buffer in the workspace on every
--                   write — against hand-authored projects/*/TODO.md that
--                   fights the task grammar on every save.
--   ui              off: render-markdown.nvim owns rendering.
--   templates.folder  stays unset, which is also the plugin's default. It
--                   is vault-relative only, and an absolute value is
--                   destructive: Path.__div joins through vim.fs.joinpath,
--                   which CONCATENATES rather than letting an absolute
--                   right-hand side win, and Workspace.set then creates
--                   that whole path inside the vault. Individual template
--                   FILES may be absolute, so every template is referenced
--                   by full path instead. Never set both.
--   lazy = false    Obsidian.dir is set during setup() and needs no buffer,
--                   but loading on `ft` leaves the global nil until the
--                   first Markdown buffer, which breaks creating a note
--                   from anywhere that is not already a note.
local vault = require("vault")

-- A machine with no vault yet is a normal state — install.sh offers one and
-- never forces it. `Workspace.setup` raises "At least one workspace is
-- required" on a path that does not exist, and eager loading would land
-- that at startup, so setup is skipped instead. The plugin's own :Obsidian
-- command already answers "Did not setup obsidian.nvim" rather than
-- erroring, and the mappings never get that far: `require_notes` reports
-- the layer's one message, whether the vault is missing or arrived too
-- late for setup to have run.
---@param subcommand string
---@return fun()
local function obsidian(subcommand)
  return function()
    if not vault.require_notes() then
      return
    end
    vim.cmd.Obsidian(subcommand)
  end
end

return {
  "obsidian-nvim/obsidian.nvim",
  lazy = false,
  opts = {
    legacy_commands = false,
    workspaces = { { name = "vault", path = vault.dir(), strict = true } },
    ui = { enable = false },
    frontmatter = { enabled = false },
    templates = { folder = nil },
    daily_notes = {
      folder = "daily",
      date_format = "YYYY-MM-DD",
      template = vault.templates_dir() .. "/daily.md",
      default_tags = {},
    },
    attachments = { folder = "assets" },
  },
  ---@param opts table
  config = function(_, opts)
    if not vault.exists() then
      return
    end
    require("obsidian").setup(opts)
  end,
  keys = {
    { "<leader>o", group = "Vault" },
    { "<leader>od", obsidian("today"), desc = "Daily note (today)" },
    { "<leader>oD", obsidian("tomorrow"), desc = "Daily note (tomorrow)" },
    { "<leader>oy", obsidian("yesterday"), desc = "Daily note (yesterday)" },
    { "<leader>oo", obsidian("follow_link"), desc = "Follow link" },
    { "<leader>ob", obsidian("backlinks"), desc = "Backlinks" },
    {
      "<leader>on",
      function()
        require("vault.notes").new()
      end,
      desc = "New note",
    },
  },
}
