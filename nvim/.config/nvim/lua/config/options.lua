-- Options on top of the LazyVim floor. Each line exists by explicit
-- decision; LazyVim defaults cover everything else.
local opt = vim.opt

opt.signcolumn = "number" -- signs replace the line number; no extra gutter
opt.relativenumber = false -- flash owns jumps; relative numbers are noise
opt.updatetime = 50 -- rest-on-symbol UI reacts near-instantly
