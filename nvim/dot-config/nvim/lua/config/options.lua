-- Only deliberate divergences from the LazyVim floor live here.
local opt = vim.opt

opt.signcolumn = "yes:1" -- signs get their own column; line numbers stay numbers
opt.relativenumber = false -- flash owns jumps; relative numbers are noise
opt.updatetime = 50 -- rest-on-symbol UI reacts near-instantly
opt.clipboard = "unnamedplus" -- yank straight to the system clipboard

-- No remote plugins in use: skip the provider probes (python3's alone
-- costs ~70ms on the first python buffer).
vim.g.loaded_python3_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_node_provider = 0

-- One global statusline; identity lives in the bufferline.
vim.opt.laststatus = 3
vim.opt.cmdheight = 0
vim.opt.showmode = false
