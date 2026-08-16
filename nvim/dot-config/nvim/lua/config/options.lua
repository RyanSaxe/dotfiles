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
