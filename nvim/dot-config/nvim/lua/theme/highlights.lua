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
  local mix = function(c, b)
    return math.floor(c * amount + b * (1 - amount) + 0.5)
  end
  return string.format("#%02x%02x%02x", mix(cr, br), mix(cg, bg_), mix(cb, bb_))
end

---@param tokens ThemeTokens
function M.apply(tokens)
  local p = tokens.palette
  local r = tokens.roles
  local accent, notify = tokens.accent, tokens.notify
  ---@param color string
  ---@param amount number
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
    type = p.teal,
    structure = p.mauve, -- keywords, operators, punctuation: code shape
    variable = p.blue,
    member = p.sapphire, -- members, parameters, builtins: dimmer blues
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
  hl("LspInlayHint", { fg = syn.comment })

  -- Editing surfaces
  hl("CursorLine", { bg = bb(p.mauve, 0.1) })
  hl("WinSeparator", { fg = r.border })
  hl("VertSplit", { link = "WinSeparator" })

  -- Ghost text: AI suggestions whisper in pink
  hl("BlinkCmpGhostText", { fg = bb(p.pink, 0.5), bg = r.bg_alt })
  hl("CopilotSuggestion", { fg = bb(p.pink, 0.5) })

  -- Diffs: primary-color washes so add/change/delete read at a glance
  hl("DiffAdd", { bg = bb("#00ff00", 0.1) })
  hl("DiffAdded", { link = "DiffAdd" })
  hl("DiffChange", { bg = bb("#0000ff", 0.1) })
  hl("DiffChanged", { link = "DiffChange" })
  hl("DiffDelete", { bg = bb("#ff0000", 0.1) })
  hl("DiffDeleted", { link = "DiffDelete" })
  hl("DiffText", { fg = p.red, bg = bb("#0000ff", 0.1) })
  hl("MiniDiffOverChange", { fg = p.red, bg = bb("#0000ff", 0.1) })
  hl("MiniDiffOverChangeBuf", { bg = bb("#00ff00", 0.1) })

  -- Gutter signs stay faint
  hl("MiniDiffSignAdd", { fg = bb(p.teal, 0.7) })
  hl("GitSignsAdd", { link = "MiniDiffSignAdd" })
  hl("MiniDiffSignChange", { fg = bb(p.mauve, 0.7) })
  hl("GitSignsChange", { link = "MiniDiffSignChange" })
  hl("MiniDiffSignDelete", { fg = bb(p.red, 0.7) })
  hl("GitSignsDelete", { link = "MiniDiffSignDelete" })

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

  -- Chrome is crust, everywhere: floats, pickers, and (in the chrome
  -- phase) statusline and bufferline share the rail's surface so the
  -- whole frame reads as one piece. Accent is the common frame color,
  -- notify marks the input focus.
  local chrome = p.crust
  hl("NormalFloat", { bg = chrome })
  hl("FloatBorder", { fg = accent, bg = chrome })
  hl("FloatTitle", { fg = accent, bg = chrome })
  hl("SnacksPickerBorder", { fg = accent, bg = chrome })
  hl("SnacksPickerTitle", { fg = accent, bg = chrome })
  hl("SnacksPickerBoxTitle", { fg = notify, bg = chrome })
  hl("SnacksPickerInputBorder", { fg = notify, bg = chrome })
  hl("SnacksPickerInputTitle", { fg = notify, bg = chrome })
  hl("SnacksPickerPrompt", { fg = notify })
  hl("SnacksPickerToggle", { fg = accent, bg = bb(accent, 0.1) })
end

return M
