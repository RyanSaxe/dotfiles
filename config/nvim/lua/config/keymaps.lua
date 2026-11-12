-- Deliberately sparse: the LazyVim floor is the keymap surface.
-- Constraint that must hold forever: never map bare <Esc> in terminal
-- mode (embedded TUIs with vim bindings need it raw).

-- Terminal escape is a DOUBLE Esc, which is what makes it safe: a single
-- Esc still reaches the embedded program untouched.
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { silent = true, desc = "Terminal: exit to Normal mode" })

-- Visual J/K move the selection, re-indenting to the new context. This
-- costs visual-mode join (J) and keywordprg (K), both of which are
-- reachable from normal mode; moving a block is not.
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { silent = true, desc = "Move selection down" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { silent = true, desc = "Move selection up" })
