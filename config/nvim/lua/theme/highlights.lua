-- The semantic layer: every deliberate color decision lives here, on
-- top of the catppuccin floor. Extend a new plugin by adding groups
-- referencing the role tables — never a raw hex outside `alarm`.
--
-- Vocabulary:
--   syn.*    code semantics (fn/type/structure/...)
--   alarm.*  vivid non-palette colors for things that must scream
--   accent / notify   the theme's accent pair: accent is common chrome,
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
  local notify = tokens.notify
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

  -- The code tiers come from the theme's meanings, which bat, delta and
  -- zsh share. Literals and docstrings blend further here.
  local code = tokens.code
  local syn = {
    fn = code["function"],
    type = code.type,
    structure = code.structure,
    variable = code.variable,
    member = code.member,
    module = code.module,
    constant = code.constant,
    literal = bb(r.fg, 0.7), -- literals must not pop
    docstring = bb(p.mauve, 0.5), -- documentation != comments
    comment = code.comment,
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
  -- The wash runs across the gutter too, and the cursor's number is bold
  -- in the accent color.
  hl("CursorLineNr", { fg = accent, bg = bb(p.mauve, 0.1), bold = true })
  hl("CursorLineSign", { bg = bb(p.mauve, 0.1) })
  hl("CursorLineFold", { bg = bb(p.mauve, 0.1) })

  -- The sticky context header sits on the buffer's own background. A line
  -- under it in the structure color, mixed halfway into the background,
  -- separates it from the code.
  hl("TreesitterContext", { bg = r.bg })
  hl("TreesitterContextLineNumber", { fg = r.fg_faint, bg = r.bg })
  hl("TreesitterContextBottom", { link = "TreesitterContext" })
  hl("TreesitterContextLineNumberBottom", { link = "TreesitterContextLineNumber" })
  hl("TreesitterContextSeparator", { fg = bb(p.mauve, 0.5), bg = r.bg })

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

  -- The marks outside a diff that link here, such as the git status
  -- picker's files, the undo picker's lines and CodeDiff's +N and -N.
  -- Catppuccin sets no Removed, which would leave Neovim's own pink.
  hl("Added", { fg = p.semantic_add })
  hl("Changed", { fg = p.semantic_change })
  hl("Removed", { fg = p.semantic_delete })

  -- CodeDiff fills the lines one side lacks with slashes, and marks code
  -- that moved in the gutter and on a line above it.
  hl("CodeDiffFiller", { fg = r.border })
  hl("CodeDiffMoveFrom", { fg = p.semantic_change })
  hl("CodeDiffMoveTo", { fg = p.semantic_change })

  -- grug-far's marks beside a result: a matched line, and the lines a
  -- replacement removes and adds. grug-far sets them once when it loads,
  -- so a light and dark flip used to clear them.
  hl("GrugFarResultsChangeIndicator", { fg = p.semantic_change })
  hl("GrugFarResultsRemoveIndicator", { fg = p.semantic_delete })
  hl("GrugFarResultsAddIndicator", { fg = p.semantic_add })

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

  -- Floats and sidebars both paint the chrome color, Rex's own sidebar
  -- shade. Floats keep a border, and sidebars run to a terminal edge (see
  -- ThemeChromeNormal below). Accent is the common frame color, and notify
  -- marks the input focus.
  hl("WinBar", { fg = r.fg_muted, bg = r.bg })
  hl("WinBarNC", { fg = r.fg_faint, bg = r.bg })
  hl("ThemeWinbarFile", { fg = r.fg, bg = r.bg, bold = true })
  hl("ThemeWinbarFileNC", { fg = r.fg_muted, bg = r.bg })
  hl("ThemeWinbarPath", { fg = r.fg_faint, bg = r.bg })
  hl("ThemeWinbarDirty", { fg = r.warn, bg = r.bg })
  -- The mode's color says what you're doing: moving around in the accent,
  -- sending text in notify (the color an input's border has), selecting in
  -- info, and the command line and a terminal in peach. Green and red stay
  -- for good and bad.
  hl("ThemeStlMove", { fg = accent, bg = r.bg, bold = true })
  hl("ThemeStlSend", { fg = notify, bg = r.bg, bold = true })
  hl("ThemeStlSelect", { fg = r.info, bg = r.bg, bold = true })
  hl("ThemeStlWait", { fg = p.peach, bg = r.bg, bold = true })
  hl("ThemeStlBranch", { fg = r.fg_faint, bg = r.bg })
  -- The branch name's colors when it needs you: behind wants a pull (peach,
  -- as in the prompt), and an operation in progress or a detached HEAD needs
  -- attention soon.
  hl("ThemeStlBehind", { fg = p.peach, bg = r.bg })
  hl("ThemeStlAttention", { fg = r.warn, bg = r.bg })
  hl("ThemeStlRecording", { fg = p.red, bg = r.bg, bold = true })
  hl("ThemeStlAdd", { fg = p.semantic_add, bg = r.bg })
  hl("ThemeStlChange", { fg = p.semantic_change, bg = r.bg })
  hl("ThemeStlDelete", { fg = p.semantic_delete, bg = r.bg })
  hl("ThemeStlError", { fg = p.red, bg = r.bg })
  hl("ThemeStlWarn", { fg = p.yellow, bg = r.bg })

  -- Catppuccin puts floats on mantle, which the theme makes the chrome
  -- color. Their frames and titles take the accent.
  local float = p.mantle
  hl("FloatBorder", { fg = accent, bg = float })
  hl("FloatTitle", { fg = accent, bg = float })
  hl("MiniFilesTitleFocused", { fg = accent, bg = float })

  -- The chrome surface: sidebars that run to a terminal edge and read as
  -- a continuation of tmux's bar. Ordinary sidebars opt in via
  -- winhighlight; the Snacks explorer uses an active namespace in
  -- theme.surfaces.
  hl("ThemeChromeNormal", { fg = r.fg_muted, bg = p.chrome })
  hl("ThemeChromeNormalNC", { fg = r.fg_faint, bg = p.chrome })
  hl("ThemeChromeCursorLine", { bg = p.base })
  -- The chrome copy of a picker's frame, for the explorer alone. Its only
  -- framed window is the input, and notify is the color the pickers give
  -- an input's border and title.
  hl("ThemeChromeFrame", { fg = notify, bg = p.chrome })

  -- Splits are divided by a thin line in a quiet gray (see fillchars). A
  -- sidebar's own edge stays a band of its chrome color, so the explorer
  -- reads as one surface.
  hl("WinSeparator", { fg = p.surface1, bg = r.bg })
  hl("VertSplit", { link = "WinSeparator" })
  hl("ThemeChromeWinSeparator", { fg = p.chrome, bg = p.chrome })
  -- The one status line sits on the buffer's background, like the tab row.
  hl("StatusLine", { fg = r.fg_faint, bg = r.bg })
  hl("StatusLineNC", { link = "StatusLine" })

  -- The recording fade, precomputed. A cell can only hold one color, so
  -- the animation is a ramp of groups the pulse timer walks. Cosine, not
  -- linear: it eases at both ends, which is what makes it read as
  -- breathing rather than as a sawtooth. The floor of 0.35 keeps the dot
  -- legible at its dimmest — it is a state indicator, not a firefly.
  local pulse = require("theme.pulse")
  for i = 1, pulse.FRAMES do
    local wave = 0.5 + 0.5 * math.cos(2 * math.pi * (i - 1) / pulse.FRAMES)
    hl(pulse.group(i), { fg = blend(p.red, r.bg, 0.35 + 0.65 * wave), bg = r.bg, bold = true })
  end

  -- Snacks windows hover over the buffer and do not reach a terminal
  -- edge, so they paint the content surface. The explorer is scoped
  -- separately in theme.surfaces, which applies an active namespace
  -- mapping the source groups used by its windows to the chrome roles.
  hl("SnacksNormal", { fg = r.fg, bg = r.bg })
  hl("SnacksNormalNC", { fg = r.fg_muted, bg = r.bg })
  -- The rest of the set every snacks window is opened with. Unnamed, they
  -- fall back to the float groups and a window lands half on either surface.
  hl("SnacksTitle", { fg = accent, bg = r.bg })
  hl("SnacksFooter", { fg = r.fg_muted, bg = r.bg })
  hl("SnacksWinBar", { fg = r.fg_muted, bg = r.bg })
  hl("SnacksWinBarNC", { fg = r.fg_faint, bg = r.bg })
  -- gh:// windows route through their own groups, so they have to be named
  -- even while they land on the same surface as the rest.
  hl("SnacksGhNormal", { fg = r.fg, bg = r.bg })
  hl("SnacksGhNormalNC", { fg = r.fg_muted, bg = r.bg })
  -- Snacks colors a pull request's or issue's state, its checks and its
  -- reviews through these four, which default to GitHub's own colors: open
  -- and passing, closed and failing, merged and completed, draft.
  hl("SnacksGhGreen", { fg = r.success })
  hl("SnacksGhRed", { fg = p.red })
  hl("SnacksGhPurple", { fg = accent })
  hl("SnacksGhGray", { fg = r.fg_faint })
  -- A pull request's +N and -N count lines, as CodeDiff's do.
  hl("SnacksGhAdditions", { link = "Added" })
  hl("SnacksGhDeletions", { link = "Removed" })
  hl("SnacksPicker", { bg = r.bg })
  hl("SnacksPickerList", { bg = r.bg })
  hl("SnacksPickerBox", { bg = r.bg })
  hl("SnacksPickerInput", { bg = r.bg })
  hl("SnacksPickerBorder", { fg = accent, bg = r.bg })
  hl("SnacksPickerTitle", { fg = accent, bg = r.bg })
  hl("SnacksPickerBoxBorder", { fg = accent, bg = r.bg })
  hl("SnacksPickerBoxTitle", { fg = notify, bg = r.bg })
  hl("SnacksPickerListBorder", { fg = accent, bg = r.bg })
  hl("SnacksPickerInputBorder", { fg = notify, bg = r.bg })
  hl("SnacksPickerInputTitle", { fg = notify, bg = r.bg })
  hl("SnacksPickerPrompt", { fg = notify })
  hl("SnacksPickerToggle", { fg = accent, bg = r.bg_alt })
  hl("SnacksWinSeparator", { fg = r.bg, bg = r.bg })
end

return M
