return {
  "MeanderingProgrammer/render-markdown.nvim",
  enabled = true,
  event = "VeryLazy",
  ft = { "markdown" },
  opts = {
    preset = "obsidian",
    file_types = { "markdown" },
    render_modes = true,
    anti_conceal = {
      ignore = {
        check_icon = true,
      },
    },
    latex = {
      enabled = true,
      converter = { "utftex", "latex2text" },
    },
    bullet = {
      enabled = true,
    },
    checkbox = {
      enabled = true,
    },
    html = {
      enabled = true,
      comment = {
        conceal = true,
      },
    },
  },
}
