-- a variety of games/practice plugins
return {
  { "ThePrimeagen/vim-be-good", enabled = true },
  {
    enabled = true,
    "nvzone/typr",
    dependencies = "nvzone/volt",
    opts = {},
    cmd = { "Typr", "TyprStats" },
  },
}
