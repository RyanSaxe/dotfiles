-- The recording tell: the state dot in the tab row breathes red while a
-- macro records, and rides the mode color the rest of the time.
--
-- A terminal cell holds one color at a time, so the fade is precomputed
-- as a ramp of highlight groups (built in theme.highlights from the same
-- FRAMES constant) and this timer walks it. Two alternating colors would
-- be a blink; a full cosine cycle reads as breathing.
--
-- The tab row is not redrawn on mode changes or on a timer by default —
-- it repaints on buffer events only. So this module owns every trigger
-- that has to reach it, and is the single place that knows the tab row
-- needs waking.
local M = {}

-- One full breath is FRAMES * TICK_MS.
M.FRAMES = 24
local TICK_MS = 60

---@type integer|nil nil whenever no macro is recording
local frame = nil
---@type uv.uv_timer_t|nil
local timer = nil

---@param index integer
---@return string
function M.group(index)
  return ("ThemePulse%02d"):format(index)
end

-- The dot's highlight group while recording, or nil to use the mode's.
---@return string|nil
function M.frame()
  return frame and M.group(frame) or nil
end

-- Marking the tab row dirty and flushing are separate things, and both
-- are needed: marking alone leaves the new color unpainted until some
-- later event flushes (which is why the dot used to wait for the next
-- keystroke), and flushing alone repaints the row from cache.
local function repaint()
  vim.api.nvim__redraw({ tabline = true, flush = true })
end

local function stop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  frame = nil
  repaint()
end

local function start()
  frame = 1
  -- RecordingEnter fires while nvim is still inside the keystroke that
  -- started the macro, where a flush is dropped. Scheduling puts the
  -- first frame immediately after it, before nvim waits for the next key.
  vim.schedule(repaint)
  if timer then
    return
  end
  timer = vim.uv.new_timer()
  if not timer then
    return
  end
  timer:start(
    TICK_MS,
    TICK_MS,
    vim.schedule_wrap(function()
      frame = (frame or 0) % M.FRAMES + 1
      repaint()
    end)
  )
end

function M.setup()
  local group = vim.api.nvim_create_augroup("theme_pulse", { clear = true })
  vim.api.nvim_create_autocmd("RecordingEnter", { group = group, callback = start })
  vim.api.nvim_create_autocmd("RecordingLeave", { group = group, callback = stop })
  -- ModeChanged can fire from inside nvim_win_call — snacks' picker preview
  -- runs `norm!` in its own window while you type — and a synchronous flush
  -- at that instant clamps the input window's insert cursor back from
  -- end-of-line, so the next character lands mid-string. Deferring puts the
  -- flush after the caller restores the cursor. A mode() guard cannot catch
  -- this: mode() already reads "n" inside that window call.
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    ---@return nil
    callback = function()
      vim.schedule(repaint)
    end,
  })
end

return M
