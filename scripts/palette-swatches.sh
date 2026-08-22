#!/bin/sh
# Emit /tmp/catppuccin-tokens.lua: a self-coloring palette sheet for
# judging palette candidates in nvim. Open it and :so % — every hex
# paints itself (dark text on light swatches and vice versa).
set -eu
pal_dir="$(cd "$(dirname "$0")/.." && pwd)/theme/palettes"
out=/tmp/catppuccin-tokens.lua

{
  echo '-- Palette swatches. Source this file (:so %) and every hex below'
  echo '-- paints itself. Regenerate after palette edits: scripts/palette-swatches.sh'
  echo '--'
  echo '-- key              dark      light'
  awk -F= '
    FNR == NR { if ($1 !~ /^#/ && $1 != "mode") dark[$1] = $2; keys[++n] = $1; next }
    { if ($1 !~ /^#/ && $1 != "mode") light[$1] = $2 }
    END {
      for (i = 1; i <= n; i++) {
        k = keys[i]
        if (k in dark) printf "-- %-15s %s   %s\n", k, dark[k], light[k]
      }
    }
  ' "$pal_dir/mocha.conf" "$pal_dir/latte.conf"
  cat <<'LUA'

for lnum = 1, vim.api.nvim_buf_line_count(0) do
  local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1]
  local from = 1
  while true do
    local s, e = line:find("#%x%x%x%x%x%x", from)
    if not s then
      break
    end
    local hex = line:sub(s, e)
    local group = "Swatch" .. hex:sub(2)
    local r = tonumber(hex:sub(2, 3), 16)
    local g = tonumber(hex:sub(4, 5), 16)
    local b = tonumber(hex:sub(6, 7), 16)
    local fg = (0.299 * r + 0.587 * g + 0.114 * b) > 128 and "#000000" or "#ffffff"
    vim.api.nvim_set_hl(0, group, { bg = hex, fg = fg })
    vim.hl.range(0, vim.api.nvim_create_namespace("swatches"), group, { lnum - 1, s - 1 }, { lnum - 1, e })
    from = e + 1
  end
end
LUA
} >"$out"
echo "wrote $out"
