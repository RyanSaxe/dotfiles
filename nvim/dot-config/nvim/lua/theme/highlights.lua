-- The semantic layer: every deliberate color decision lives here, on
-- top of the catppuccin floor. Extend a new plugin by adding groups
-- referencing the role tables — never a raw hex outside `alarm`.
--
-- Vocabulary:
--   syn.*    code semantics (fn/type/structure/...)
--   alarm.*  vivid non-palette colors for things that must scream
--   accent / notify   the mascot pair: accent is common chrome,
--                     notify is deliberately rarer emphasis
local M = {}

---@param hex string
---@return integer red, integer green, integer blue
local function to_rgb(hex)
  return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

-- Share `amount` of color over the background (amount=1 is pure color).
---@param color string
---@param bg string
---@param amount number
---@return string
local function blend(color, bg, amount)
  local cr, cg, cb = to_rgb(color)
  local br, bg_, bb_ = to_rgb(bg)
  ---@param c integer one channel of the color
  ---@param b integer the same channel of the background
  ---@return integer
  local mix = function(c, b)
    return math.floor(c * amount + b * (1 - amount) + 0.5)
  end
  return string.format("#%02x%02x%02x", mix(cr, br), mix(cg, bg_), mix(cb, bb_))
end

---@param tokens ThemeTokens
function M.apply(tokens)
  local p = tokens.palette
  local r = tokens.roles
  -- Inner accent; the outer pair lives on `o` and paints the sidebars.
  local accent = tokens.accent
  ---@param color string
  ---@param amount number
  ---@return string
  local function bb(color, amount)
    return blend(color, r.bg, amount)
  end
  ---@param group string
  ---@param spec vim.api.keyset.highlight
  local function hl(group, spec)
    vim.api.nvim_set_hl(0, group, spec)
  end

  local syn = {
    fn = p.peach, -- anything callable
    type = p.green, -- out of the cyan region: members must never read as types
    structure = p.mauve, -- keywords, operators, punctuation: code shape
    variable = p.blue,
    member = p.sky, -- members and parameters: lighter than variables, not a blue twin
    module = p.pink,
    constant = p.red, -- constants and private variables stand out alike
    literal = bb(r.fg, 0.7), -- literals must not pop
    docstring = bb(p.mauve, 0.5), -- documentation != comments
    comment = r.fg_faint,
  }
  local alarm = {
    risky = "#ff007c",
    fix = "#ff0000",
    hack = "#f76da7",
  }

  -- Literals
  for _, g in ipairs({ "@string", "@number", "@number.float", "@boolean", "@constant.builtin" }) do
    hl(g, { fg = syn.literal })
  end
  hl("@string.documentation", { fg = syn.docstring })
  hl("@lsp.typemod.string.documentation", { link = "@string.documentation" })

  -- Callables
  hl("@function", { fg = syn.fn })
  for _, g in ipairs({
    "@function.call",
    "@function.builtin",
    "@function.method",
    "@function.method.call",
    "@constructor",
  }) do
    hl(g, { link = "@function" })
  end
  hl("@lsp.type.decorator", { link = "@function" })

  -- Types, constants, modules
  hl("@type", { fg = syn.type })
  hl("@type.builtin", { link = "@type" })
  hl("@lsp.type.typeParameter", { fg = syn.type })
  hl("@constant", { fg = syn.constant })
  hl("@variable.private", { fg = syn.constant })
  hl("@module", { fg = syn.module })
  hl("@lsp.type.namespace", { link = "@module" })

  -- Variables
  hl("@variable", { fg = syn.variable })
  for _, g in ipairs({ "@variable.member", "@variable.parameter" }) do
    hl(g, { fg = syn.member })
  end
  -- LSP semantic tokens outrank treesitter; claim the member-shaped ones
  -- or the floor's own mappings (lavender properties) leak through.
  hl("@lsp.type.property", { link = "@variable.member" })
  hl("@lsp.type.parameter", { link = "@variable.parameter" })
  -- Receiver objects (self/cls/this) read as context, like modules.
  hl("@variable.builtin", { fg = syn.module })

  -- Structure: the shape of code recedes into one calm color
  for _, g in ipairs({
    "@keyword.conditional",
    "@keyword.repeat",
    "@keyword.exception",
    "@keyword.function",
    "@keyword.return",
    "@keyword.type",
    "@keyword.import",
    "@operator",
    "@punctuation.delimiter",
    "@punctuation.bracket",
    "@punctuation.special",
  }) do
    hl(g, { fg = syn.structure })
  end

  -- Alarms
  hl("@keyword.risky", { fg = alarm.risky, bold = true, italic = true, underline = true })
  hl("@keyword.error", { fg = alarm.risky })

  -- Comments and inlay hints read as one quiet voice
  hl("Comment", { fg = syn.comment, italic = true })
  -- Inferred types blend toward the background from the type color:
  -- still recessive, but readable as type information at a glance and
  -- distinguishable from annotations the file actually declares.
  hl("LspInlayHint", { fg = bb(syn.type, 0.45), italic = true })

  -- Editing surfaces
  hl("CursorLine", { bg = bb(p.mauve, 0.1) })

  -- Ghost text: AI suggestions whisper in pink
  hl("BlinkCmpGhostText", { fg = bb(p.pink, 0.5), bg = r.bg_alt })
  hl("CopilotSuggestion", { fg = bb(p.pink, 0.5) })

  -- Semantic ops: designed in-palette washes shared by every tool.
  -- Rows stay soft, changed words step up, gutter signs carry the
  -- full accent.
  hl("DiffAdd", { bg = bb(p.semantic_add, 0.2) })
  hl("DiffAdded", { link = "DiffAdd" })
  hl("DiffChange", { bg = bb(p.semantic_change, 0.2) })
  hl("DiffChanged", { link = "DiffChange" })
  hl("DiffDelete", { bg = bb(p.semantic_delete, 0.2) })
  hl("DiffDeleted", { link = "DiffDelete" })
  hl("DiffText", { bg = bb(p.semantic_change, 0.46) })
  hl("MiniDiffOverAdd", { bg = bb(p.semantic_add, 0.46) })
  hl("MiniDiffOverDelete", { bg = bb(p.semantic_delete, 0.46) })
  hl("MiniDiffOverChange", { link = "DiffText" })
  hl("MiniDiffOverChangeBuf", { bg = bb(p.semantic_add, 0.46) })

  hl("MiniDiffSignAdd", { fg = p.semantic_add })
  hl("MiniDiffSignChange", { fg = p.semantic_change })
  hl("MiniDiffSignDelete", { fg = p.semantic_delete })

  -- Todo-comment badges: fg-only, bold italic, trailing text stays quiet
  local badges = {
    TodoBgPERF = bb(p.teal, 0.7),
    TodoBgWARN = bb(p.yellow, 0.7),
    TodoBgHACK = bb(alarm.hack, 0.7),
    TodoBgFIX = alarm.fix,
    TodoBgNOTE = bb(p.sky, 0.7),
    TodoBgTODO = bb(p.peach, 0.7),
    TodoBgTEST = bb(p.pink, 0.7),
  }
  for group, color in pairs(badges) do
    hl(group, { fg = color, bold = true, italic = true })
    hl(group:gsub("Bg", "Fg"), { link = "Comment" })
  end

  -- Chrome splits by whether a surface touches a terminal edge.
  --
  -- Floats hover over the buffer and never reach an edge, so they take
  -- the INNER crust. Sidebars do reach an edge and continue the tmux
  -- rail, so they take the OUTER one (see ThemeOuterNormal below). Both
  -- are crust; when the layers run different modes they are different
  -- colors, which is the whole distinction. Accent is the common frame
  -- color, notify marks the input focus.
  hl("StatusLine", { fg = r.fg_muted, bg = r.bg })
  hl("StatusLineNC", { fg = r.fg_faint, bg = r.bg })
  hl("MiniStatuslineInactive", { fg = r.fg_faint, bg = r.bg })
  hl("WinBar", { fg = r.fg_muted, bg = r.bg })
  hl("WinBarNC", { fg = r.fg_faint, bg = r.bg })
  hl("ThemeStlNormal", { fg = accent, bg = r.bg, bold = true })
  hl("ThemeStlInsert", { fg = p.mauve, bg = r.bg, bold = true })
  hl("ThemeStlVisual", { fg = p.blue, bg = r.bg, bold = true })
  hl("ThemeStlCommand", { fg = p.peach, bg = r.bg, bold = true })
  hl("ThemeStlReplace", { fg = p.pink, bg = r.bg, bold = true })
  hl("ThemeStlTerminal", { fg = p.green, bg = r.bg, bold = true })
  hl("ThemeStlBranch", { fg = r.fg_faint, bg = r.bg })
  hl("ThemeStlRecording", { fg = p.red, bg = r.bg, bold = true })
  hl("ThemeStlAdd", { fg = p.semantic_add, bg = r.bg })
  hl("ThemeStlChange", { fg = p.semantic_change, bg = r.bg })
  hl("ThemeStlDelete", { fg = p.semantic_delete, bg = r.bg })
  hl("ThemeStlError", { fg = p.red, bg = r.bg })
  hl("ThemeStlWarn", { fg = p.yellow, bg = r.bg })

  local float = p.crust
  hl("NormalFloat", { bg = float })
  hl("FloatBorder", { fg = accent, bg = float })
  hl("FloatTitle", { fg = accent, bg = float })
  hl("MiniFilesNormal", { bg = float })
  hl("MiniFilesBorder", { fg = accent, bg = float })
  hl("MiniFilesTitleFocused", { fg = accent, bg = float })

  -- The outer surface: sidebars that run to a terminal edge and read as
  -- a continuation of the tmux rail. Windows opt in via `winhighlight`
  -- (see theme.surfaces), so this is the only place the color is named.
  local o = tokens.outer
  hl("ThemeOuterNormal", { fg = o.fg_muted, bg = o.crust })
  hl("ThemeOuterNormalNC", { fg = o.fg_faint, bg = o.crust })
  hl("ThemeOuterCursorLine", { bg = o.mantle })

  -- Window separators are painted bands, not hairlines: a glyph drawn in
  -- fg leaves the cell's background showing, which ghostty's always-extend
  -- then smears at the edges and which never merges with the explorer
  -- beside it. Space glyphs (see fillchars) plus a background make the
  -- divider one solid strip of chrome, exactly as on the tmux side.
  hl("WinSeparator", { fg = o.crust, bg = o.crust })
  hl("VertSplit", { link = "WinSeparator" })
  hl("ThemeOuterWinSeparator", { link = "WinSeparator" })
  -- With no statusline, nvim still draws one as the divider between
  -- stacked windows. Blanked in options.lua, it becomes the horizontal
  -- twin of the band above.
  hl("StatusLine", { fg = o.crust, bg = o.crust })
  hl("StatusLineNC", { link = "StatusLine" })

  -- The tab row's state readout. These are real groups rather than
  -- per-render colors because bufferline creates custom-area highlights
  -- with `default = true`: the first paint would win forever and the
  -- mode color would never change again.
  ---@type table<string, string>
  local modes = {
    Normal = o.accent,
    Insert = o.mauve,
    Visual = o.blue,
    Command = o.peach,
    Replace = o.pink,
    Terminal = o.green,
  }
  for name, color in pairs(modes) do
    hl("ThemeMode" .. name, { fg = color, bg = o.crust, bold = true })
  end
  -- The recording fade, precomputed. A cell can only hold one color, so
  -- the animation is a ramp of groups the pulse timer walks. Cosine, not
  -- linear: it eases at both ends, which is what makes it read as
  -- breathing rather than as a sawtooth. The floor of 0.35 keeps the dot
  -- legible at its dimmest — it is a state indicator, not a firefly.
  local pulse = require("theme.pulse")
  for i = 1, pulse.FRAMES do
    local wave = 0.5 + 0.5 * math.cos(2 * math.pi * (i - 1) / pulse.FRAMES)
    hl(pulse.group(i), { fg = blend(o.red, o.crust, 0.35 + 0.65 * wave), bg = o.crust, bold = true })
  end
  hl("ThemeBranch", { fg = o.fg_faint, bg = o.crust })

  -- Snacks, wholesale (see plugins/explorer.lua for why it can't split).
  hl("SnacksNormal", { fg = o.fg, bg = o.crust })
  hl("SnacksNormalNC", { fg = o.fg_muted, bg = o.crust })
  hl("SnacksPicker", { bg = o.crust })
  hl("SnacksPickerList", { bg = o.crust })
  hl("SnacksPickerBox", { bg = o.crust })
  hl("SnacksPickerInput", { bg = o.crust })
  hl("SnacksPickerBorder", { fg = o.accent, bg = o.crust })
  hl("SnacksPickerTitle", { fg = o.accent, bg = o.crust })
  hl("SnacksPickerBoxBorder", { fg = o.accent, bg = o.crust })
  hl("SnacksPickerBoxTitle", { fg = o.notify, bg = o.crust })
  hl("SnacksPickerListBorder", { fg = o.accent, bg = o.crust })
  hl("SnacksPickerInputBorder", { fg = o.notify, bg = o.crust })
  hl("SnacksPickerInputTitle", { fg = o.notify, bg = o.crust })
  hl("SnacksPickerPrompt", { fg = o.notify })
  hl("SnacksPickerToggle", { fg = o.accent, bg = o.mantle })
  hl("SnacksWinSeparator", { fg = o.crust, bg = o.crust })
end

return M
