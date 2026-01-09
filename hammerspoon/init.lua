-- Hammerspoon config: Tab focusing automation for Leader Key
-- Focus an existing Chrome tab by domain; otherwise open a new one.
--
-- NOTE: Currently Chrome-only for simplicity and guaranteed instant performance.
-- Could be expanded to support other Chromium-based browsers (Arc, Brave, Edge)
-- by detecting default browser and swapping app name in AppleScript.
-- Firefox and Safari have different/limited AppleScript APIs.

-- Enable IPC so the 'hs' command-line tool can communicate with Hammerspoon
hs.ipc.cliInstall()

-- ════════════════════════════════════════════════════════════════════════════
-- Spotlight (faster than AppleScript)
-- ════════════════════════════════════════════════════════════════════════════

-- Open Spotlight using keystroke (much faster than osascript)
-- Called via: hs -c 'openSpotlight()'
function openSpotlight()
	hs.eventtap.keyStroke({ "cmd" }, "space")
end

-- Get all Chrome tabs with window ID, tab index, URL, and title
local function getAllChromeTabs()
	local script = [[
    set out to {}
    tell application "Google Chrome"
      repeat with w in windows
        set wid to id of w
        set tIndex to 0
        repeat with t in tabs of w
          set tIndex to tIndex + 1
          set tabTitle to title of t
          set tabURL to URL of t
          set end of out to (wid as string) & "|" & (tIndex as string) & "|" & tabURL & "|" & tabTitle
        end repeat
      end repeat
    end tell
    return out
  ]]
	local ok, res = hs.osascript.applescript(script)
	if not ok or type(res) ~= "table" then
		return {}
	end
	return res
end

-- New: focus tab by window ID (robust to reordering/minimized windows)
local function focusChromeTabByWinID(winID, tabIndex)
	local script = string.format(
		[[
    tell application "Google Chrome"
      activate
      try
        set w to (first window whose id is %d)
        if (minimized of w) is true then set minimized of w to false
        set active tab index of w to %d
        set index of w to 1
      end try
      activate
    end tell
  ]],
		winID,
		tabIndex
	)
	hs.osascript.applescript(script)
end

-- Update your matcher to pass window ID (not index)
local function hostFromURL(u)
	local h = u:match("^%a[%w+.-]*://([^/]+)")
	if h then
		h = h:lower():gsub("^www%.", "")
	end
	return h
end

local function domainMatches(host, domain)
	if not host then
		return false
	end
	host = host:lower():gsub("^www%.", "")
	domain = domain:lower():gsub("^www%.", "")
	return host == domain or host:sub(-(#domain + 1)) == ("." .. domain)
end

-- Main function: focus existing Chrome tab or open URL
-- Exposed globally so Leader Key can call it: hs -c 'focusByDomainOrOpen("example.com", "https://example.com")'
function focusByDomainOrOpen(domain, url)
	local chrome = hs.application.find("Google Chrome")
	if chrome then
		for _, line in ipairs(getAllChromeTabs()) do
			-- Format: windowID|tabIndex|URL|title
			local wid, t, u = line:match("^(%d+)|(%d+)|([^|]+)")
			if wid and t and u then
				local host = hostFromURL(u)
				if domainMatches(host, domain) then
					focusChromeTabByWinID(tonumber(wid), tonumber(t))
					return true
				end
			end
		end
	end
	hs.urlevent.openURL(url)
	return false
end

-- Focus a Chrome tab by domain AND title pattern
-- titlePattern: Lua pattern to match against tab title (e.g., "Chat", "Calendar")
-- Returns true if tab was found and focused
function focusByDomainAndTitle(domain, titlePattern, fallbackUrl)
	local chrome = hs.application.find("Google Chrome")
	if chrome then
		for _, line in ipairs(getAllChromeTabs()) do
			-- Format: windowID|tabIndex|URL|title
			local wid, t, u, title = line:match("^(%d+)|(%d+)|([^|]+)|(.*)$")
			if wid and t and u and title then
				local host = hostFromURL(u)
				if domainMatches(host, domain) and title:match(titlePattern) then
					focusChromeTabByWinID(tonumber(wid), tonumber(t))
					return true
				end
			end
		end
	end
	-- Tab not found, open fallback URL
	if fallbackUrl then
		hs.urlevent.openURL(fallbackUrl)
	end
	return false
end

-- Focus tab by domain+title and send keystroke
function focusByDomainTitleAndSendKey(domain, titlePattern, fallbackUrl, key, modifiers)
	modifiers = modifiers or {}

	local found = focusByDomainAndTitle(domain, titlePattern, fallbackUrl)

	local chrome = hs.application.find("Google Chrome")
	if found and chrome and chrome:isFrontmost() then
		hs.timer.doAfter(0.05, function()
			hs.eventtap.keyStroke(modifiers, key, 50000)
		end)
		return
	end

	-- Wait for Chrome to activate
	local watcher
	watcher = hs.application.watcher.new(function(name, event, _)
		if event == hs.application.watcher.activated and name == "Google Chrome" then
			hs.timer.doAfter(0.15, function()
				hs.eventtap.keyStroke(modifiers, key, 50000)
			end)
			watcher:stop()
		end
	end)
	watcher:start()

	hs.timer.doAfter(5, function()
		watcher:stop()
	end)
end

-- Focus web app and send keystroke after focused
-- For browser-only workflows (Outlook web, Teams web, etc.)
-- Called via: hs -c 'focusWebAndSendKey("outlook.office.com", "https://outlook.office.com", "n", {})'
function focusWebAndSendKey(domain, url, key, modifiers)
	modifiers = modifiers or {}

	-- Focus or open the web app
	local wasAlreadyOpen = focusByDomainOrOpen(domain, url)

	-- If tab was already open and Chrome is frontmost, send key immediately
	local chrome = hs.application.find("Google Chrome")
	if wasAlreadyOpen and chrome and chrome:isFrontmost() then
		hs.timer.doAfter(0.05, function()
			hs.eventtap.keyStroke(modifiers, key, 50000)
		end)
		return
	end

	-- Otherwise wait for Chrome to activate, then send keystroke
	local watcher
	watcher = hs.application.watcher.new(function(name, event, _)
		if event == hs.application.watcher.activated and name == "Google Chrome" then
			-- Delay to ensure page is ready (especially for new tabs)
			hs.timer.doAfter(0.3, function()
				hs.eventtap.keyStroke(modifiers, key, 50000)
			end)
			watcher:stop()
		end
	end)
	watcher:start()

	-- Safety timeout
	hs.timer.doAfter(5, function()
		watcher:stop()
	end)
end

-- ════════════════════════════════════════════════════════════════════════════
-- Window Tiling Functions (called via Leader Key)
-- ════════════════════════════════════════════════════════════════════════════

function tileLeft()
	local win = hs.window.focusedWindow()
	if win then
		local screen = win:screen():frame()
		win:setFrame({ x = screen.x, y = screen.y, w = screen.w / 2, h = screen.h })
	end
end

function tileRight()
	local win = hs.window.focusedWindow()
	if win then
		local screen = win:screen():frame()
		win:setFrame({ x = screen.x + screen.w / 2, y = screen.y, w = screen.w / 2, h = screen.h })
	end
end

function tileTop()
	local win = hs.window.focusedWindow()
	if win then
		local screen = win:screen():frame()
		win:setFrame({ x = screen.x, y = screen.y, w = screen.w, h = screen.h / 2 })
	end
end

function tileBottom()
	local win = hs.window.focusedWindow()
	if win then
		local screen = win:screen():frame()
		win:setFrame({ x = screen.x, y = screen.y + screen.h / 2, w = screen.w, h = screen.h / 2 })
	end
end

function windowMaximize()
	local win = hs.window.focusedWindow()
	if win then
		win:maximize()
	end
end

function windowFullscreen()
	local win = hs.window.focusedWindow()
	if win then
		win:toggleFullScreen()
	end
end

-- === OBS Virtual Camera scene control ===
-- You set these in OBS:
--   Switch to Scene: VirtualCameraFace   -> alt+cmd+1
--   Switch to Scene: VirtualCameraTablet -> alt+cmd+2

local _obsCam = "face" -- local state: "face" or "tablet"

function obsCameraFace()
	hs.eventtap.keyStroke({ "alt", "cmd" }, "1", 0)
	_obsCam = "face"
end

function obsCameraTablet()
	hs.eventtap.keyStroke({ "alt", "cmd" }, "2", 0)
	_obsCam = "tablet"
end

function toggleObsCamera()
	if _obsCam == "face" then
		obsCameraTablet()
	else
		obsCameraFace()
	end
end

-- === Outlook Web helpers ===
-- Mark all as read in Outlook Web: Select all (Cmd+A) then mark as read (Q)
-- In Outlook Web, single-key shortcuts work when focus is on the message list
function outlookMarkAllAsRead()
	-- Focus Outlook Web first
	focusByDomainOrOpen("outlook.office.com", "https://outlook.office.com")

	-- Wait for Chrome to be ready, then send keystrokes
	hs.timer.doAfter(0.3, function()
		-- Select all messages (Cmd+A on Mac)
		hs.eventtap.keyStroke({ "cmd" }, "a", 50000)
		-- Small delay between keystrokes
		hs.timer.doAfter(0.15, function()
			-- Mark as read - just "q" key in Outlook Web (single-key shortcut)
			hs.eventtap.keyStroke({}, "q", 50000)
		end)
	end)
end

hs.hotkey.bind({ "cmd", "shift" }, "R", hs.reload)

hs.alert.show("Hammerspoon config loaded ✅", 2)
