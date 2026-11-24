---@meta

-- Minimal LuaCATS stubs for external Neovim plugins referenced in config/nvim/.
-- CI checks Lua without ~/.local/share/nvim/lazy installed, so these keep
-- plugin spec annotations typed without silencing real local diagnostics.

---@class wk.Opts
---@field delay? number | fun(ctx: { keys: string, plugin?: string }): number
---@field [string] any

---@class PluginLspOpts
---@field servers table<string, { keys: table[] }>

---@class blink.cmp.Config
---@field [string] any

---@class blink.cmp.API
---@field is_visible fun(): boolean
---@field select_next fun(): boolean?
---@field select_prev fun(): boolean?

---@class blink.cmp.Source
---@field get_trigger_characters fun(self: blink.cmp.Source): string[]

---@class blink.cmp.Context
---@field cursor integer[]
---@field line string
---@field bufnr integer

---@class blink.cmp.CompletionItem
---@field textEdit { range: lsp.Range, newText: string }
---@field [string] any

---@class blink.cmp.CompletionResponse
---@field items table[]
---@field is_incomplete_forward? boolean
---@field is_incomplete_backward? boolean

---@class snacks.win
---@field win integer
---@field valid fun(self: snacks.win): boolean

---@class snacks.win.Backdrop
---@field bg? string
---@field blend? integer
---@field transparent? boolean

---@class snacks.picker.layout.Config
---@field [string] any

---@class snacks.picker.Action.spec
---@field [integer] string
---@field mode? string | string[]
---@field desc? string
---@field [string] any

---@class snacks.picker.Item
---@field branch? string
---@field commit? string
---@field [string] any

---@class snacks.picker.gh.Item
---@field type? string
---@field repo? string
---@field number? integer | string
---@field [string] any

---@class snacks.picker.List
---@field win? snacks.win
---@field view fun(self: snacks.picker.List, idx: integer)

---@class snacks.picker.Layout
---@field root? snacks.win
---@field box_wins? table<any, snacks.win>

---@class snacks.Picker
---@field id number
---@field resolved_layout snacks.picker.layout.Config
---@field layout? snacks.picker.Layout
---@field preview? { win?: snacks.win }
---@field list snacks.picker.List
---@field input? { win?: snacks.win }
---@field set_layout fun(self: snacks.Picker, layout: string | snacks.picker.layout.Config | nil)
---@field cwd fun(self: snacks.Picker): string
---@field close fun(self: snacks.Picker)
---@field items fun(self: snacks.Picker): snacks.picker.Item[]
