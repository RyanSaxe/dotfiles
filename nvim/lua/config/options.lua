-- Only deliberate divergences from the LazyVim floor live here.
local opt = vim.opt

opt.signcolumn = "yes:1" -- signs get their own column; line numbers stay numbers
opt.relativenumber = false -- flash owns jumps; relative numbers are noise
opt.updatetime = 50 -- rest-on-symbol UI reacts near-instantly
opt.clipboard = "unnamedplus" -- yank straight to the system clipboard
opt.swapfile = false -- worktrees and short-lived review sessions do not need swapfiles

-- Every float wears a border, including any plugin installed later that
-- forgets to ask for one. Neovim reads this only for floats that do not name
-- their own border, so the ones that do are untouched: snacks resolves
-- `border = true` through here and already fell back to rounded, and noice
-- draws its own frames (see plugins/noice.lua). What changes is mini.files,
-- which hardcodes `single` only while this is unset.
opt.winborder = "rounded"

-- Every cursor shape keeps the cell's full HEIGHT; only width varies.
-- Load-bearing beyond taste: ghostty's frame shader infers the display
-- scale from the cursor height (iCurrentCursor.w), so nvim's stock
-- `r-cr-o:hor20` — a bar 20% of a cell tall — reads as a 1x display and
-- collapses the frame ring to half its width the moment you enter
-- Replace mode. Block there keeps the probe honest.
vim.opt.guicursor = "n-v-c-sm-r-cr-o:block,i-ci-ve:ver25,t:block-blinkon500-blinkoff500-TermCursor"

-- No remote plugins in use: skip the provider probes (python3's alone
-- costs ~70ms on the first python buffer).
vim.g.loaded_python3_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_node_provider = 0

-- No statusline: it would band the full width and stop the chrome
-- surface short of the terminal floor. Mode rides the tab row,
-- per-window facts ride the winbar.
vim.opt.laststatus = 0
vim.opt.cmdheight = 0
vim.opt.showmode = false

-- laststatus=0 removes the bar but NOT the divider between stacked
-- windows: nvim still draws a statusline there, and an unset one falls
-- back to the built-in default, which is why that row read as a
-- filename. Blanked, it renders as a plain painted strip.
vim.opt.statusline = " "

-- Separators as painted bands rather than hairline glyphs. A drawn
-- glyph leaves the cell's own background beside it — which is the gap
-- next to the explorer, and what ghostty's always-extend smears at the
-- edges. Space glyphs let the WinSeparator background be the divider,
-- the same fix as the tmux border.
vim.opt.fillchars:append({
  vert = " ",
  horiz = " ",
  horizup = " ",
  horizdown = " ",
  vertleft = " ",
  vertright = " ",
  verthoriz = " ",
})
