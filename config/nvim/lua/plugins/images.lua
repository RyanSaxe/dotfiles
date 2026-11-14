-- snacks.nvim draws a note's pictures, Mermaid diagrams and math in the
-- text, through the terminal's Kitty graphics. Mermaid goes through mmdc,
-- math through pdflatex, and every picture through ImageMagick, all three
-- from modules/home/packages.nix. markdown/health.lua checks them, and
-- config/options.lua tells snacks that Rex can draw. A diagram takes the
-- theme's colors from theme/apps/mermaid.nix, and math the text color from
-- theme/highlights.lua.
return {
  "folke/snacks.nvim",
  ---@type snacks.Config
  opts = {
    image = {
      enabled = true,
      convert = {
        -- snacks' own mmdc arguments, with the theme's file for the mode in
        -- place of Mermaid's dark or neutral theme. snacks names a diagram's
        -- picture by `background`, so the colors follow it too.
        mermaid = function()
          local colors = ("%s/%s/mermaid.json"):format(require("theme").dir, vim.o.background)
          return { "-i", "{src}", "-o", "{file}", "-b", "transparent", "-c", colors, "-s", "{scale}" }
        end,
      },
      -- snacks' own LaTeX page with \boldmath added, so equations are bold.
      math = {
        latex = {
          tpl = [[
            \documentclass[preview,border=0pt,varwidth,12pt]{standalone}
            \usepackage{${packages}}
            \begin{document}
            ${header}
            { \${font_size} \selectfont
              \color[HTML]{${color}}
              \boldmath
            ${content}}
            \end{document}]],
        },
      },
    },
  },
}
