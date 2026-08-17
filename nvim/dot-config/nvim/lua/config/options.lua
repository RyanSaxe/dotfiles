-- Only deliberate divergences from the LazyVim floor live here.
local opt = vim.opt

opt.signcolumn = "yes:1" -- signs get their own column; line numbers stay numbers
opt.relativenumber = false -- flash owns jumps; relative numbers are noise
opt.updatetime = 50 -- rest-on-symbol UI reacts near-instantly
opt.clipboard = "unnamedplus" -- yank straight to the system clipboard

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

-- One global statusline, reduced to the mode cell; per-window facts
-- ride the winbar instead.
vim.opt.laststatus = 3
vim.opt.cmdheight = 0
vim.opt.showmode = false
