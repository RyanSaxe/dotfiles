-- Enter and o continue a list: after a task the new line starts with
-- `- [ ] `, after a bullet with `- `. Numbered lists don't count up, and
-- Ctrl-U clears an item you don't want. A ticked task continues as a plain
-- bullet, since `- [x]` only matches `-`.
vim.opt_local.comments = { "b:- [ ]", "b:-", "b:*", "b:+", "n:>" }
vim.opt_local.formatoptions:append("ro")
