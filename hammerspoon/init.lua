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

-- Replace your tab enumeration with window IDs (stable)
local function getAllChromeTabs()
	local script = [[
    set out to {}
    tell application "Google Chrome"
      repeat with w in windows
        set wid to id of w
        set tIndex to 0
        repeat with t in tabs of w
          set tIndex to tIndex + 1
          set end of out to (wid as string) & "|" & (tIndex as string) & "|" & (URL of t as string)
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
			local wid, t, u = line:match("^(%d+)|(%d+)|(.+)$")
			if wid and t and u then
				local host = hostFromURL(u)
				if domainMatches(host, domain) then
					focusChromeTabByWinID(tonumber(wid), tonumber(t))
					return
				end
			end
		end
	end
	hs.urlevent.openURL(url)
end

-- Function to open app if it exists, otherwise open web URL
function openAppOrWeb(appName, appPath, webUrl)
	-- Check if the app exists
	local file = io.open(appPath, "r")
	if file then
		file:close()
		-- App exists, open it
		hs.application.open(appPath)
	else
		-- App doesn't exist, open web version
		local domain = webUrl:match("^https?://([^/]+)")
		if domain then
			-- Remove protocol and use our existing function
			domain = domain:lower():gsub("^www%.", "")
			focusByDomainOrOpen(domain, webUrl)
		else
			-- Fallback to just opening the URL
			hs.urlevent.openURL(webUrl)
		end
	end
end

-- Function to open app and send a keystroke once focused
-- Supports different keystrokes for native app vs web version
-- appKey/appModifiers: keystroke to send when opening native app (optional)
-- webKey/webModifiers: keystroke to send when opening web version (optional)
function openAppWithKey(appName, appPath, webUrl, appKey, appModifiers, webKey, webModifiers)
	appModifiers = appModifiers or {}
	webModifiers = webModifiers or {}

	-- Helper to send keystroke after app/page is focused
	local function sendKeystrokeWhenFocused(targetAppName, key, modifiers)
		if not key then
			return
		end

		-- Check if app is already frontmost
		local app = hs.application.find(targetAppName)
		if app and app:isFrontmost() then
			hs.eventtap.keyStroke(modifiers, key, 50000)
			return
		end

		-- Set up watcher to send keystroke when app is activated
		local watcher
		watcher = hs.application.watcher.new(function(name, event, _)
			if event == hs.application.watcher.activated and name == targetAppName then
				-- Small delay to ensure window is ready
				hs.timer.doAfter(0.15, function()
					hs.eventtap.keyStroke(modifiers, key, 50000)
				end)
				watcher:stop()
			end
		end)
		watcher:start()

		-- Safety timeout: stop watcher after 5 seconds
		hs.timer.doAfter(5, function()
			watcher:stop()
		end)
	end

	-- Check if the native app exists
	local file = io.open(appPath, "r")
	if file then
		file:close()
		-- App exists, open it and send app keystroke
		hs.application.open(appPath)
		sendKeystrokeWhenFocused(appName, appKey, appModifiers)
	else
		-- App doesn't exist, open web version
		local domain = webUrl:match("^https?://([^/]+)")
		if domain then
			domain = domain:lower():gsub("^www%.", "")
			focusByDomainOrOpen(domain, webUrl)
		else
			hs.urlevent.openURL(webUrl)
		end
		-- Send web keystroke (Chrome will be the focused app)
		sendKeystrokeWhenFocused("Google Chrome", webKey, webModifiers)
	end
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

-- === Outlook helpers ===
function outlookMarkAllAsRead()
	local app = hs.appfinder.appFromName("Microsoft Outlook")
	if not app then
		hs.application.open("/Applications/Microsoft Outlook.app")
		return
	end
	app:activate()

	-- Menu path can vary slightly; these are the common ones.
	-- We'll try a couple in order.
	local candidates = {
		{ "Message", "Mark All as Read" },
		{ "Message", "Mark as Read", "Mark All as Read" },
		{ "Edit", "Mark All as Read" },
	}

	for _, path in ipairs(candidates) do
		local ok = app:selectMenuItem(path)
		if ok then
			return
		end
	end

	hs.alert.show("Outlook: couldn't find 'Mark All as Read' menu item")
end

hs.hotkey.bind({ "cmd", "shift" }, "R", hs.reload)

hs.alert.show("Hammerspoon config loaded ✅", 2)
