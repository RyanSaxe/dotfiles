-- Only deliberate divergences from the LazyVim floor live here.
local opt = vim.opt

opt.signcolumn = "number" -- signs replace the line number; no extra gutter
-- LazyVim points statuscolumn at snacks, which draws signs and the
-- number as separate segments — that voids signcolumn="number". Clearing
-- it restores native rendering, where the merge actually happens.
opt.statuscolumn = ""
opt.relativenumber = false -- flash owns jumps; relative numbers are noise
opt.updatetime = 50 -- rest-on-symbol UI reacts near-instantly
opt.clipboard = "unnamedplus" -- yank straight to the system clipboard

-- No remote plugins in use: skip the provider probes (python3's alone
-- costs ~70ms on the first python buffer).
vim.g.loaded_python3_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_node_provider = 0

-- No statusline: window identity floats (incline) and file shape rides
-- the scrollbar (satellite), so the bottom row belongs to code.
vim.opt.laststatus = 0
vim.opt.cmdheight = 0
vim.opt.showmode = false
