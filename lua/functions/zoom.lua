-- This enables neovim to actually change the font size via called the terminal app
-- ~/.config/nvim/lua/font_control.lua

local M = {}
local default_steps = 3

-- Send “⌘+key” repeatN times to the frontmost application via System Events
-- key:     either "+" or "-" (string)
-- repeatN: integer count
local function send_cmd_key(key, repeatN)
  local apple_script = string.format(
    [[
    tell application "System Events"
      repeat %d times
        keystroke "%s" using {command down}
        delay 0.02
      end repeat
    end tell
  ]],
    repeatN,
    key
  )

  os.execute("osascript -e " .. vim.fn.shellescape(apple_script))
end

-- Font increase (⌘+) by `steps` presses (default = 3)
-- Usage: require("font_control").increase(5)  → 5 steps;
--        require("font_control").increase()   → default_steps
function M.increase(steps)
  local n = (type(steps) == "number" and steps) or default_steps
  send_cmd_key("=", n)
end

-- Font decrease (⌘–) by `steps` presses (default = 3)
-- Usage: require("font_control").decrease(2)  → 2 steps;
--        require("font_control").decrease()   → default_steps
function M.decrease(steps)
  local n = (type(steps) == "number" and steps) or default_steps
  send_cmd_key("-", n)
end

return M
