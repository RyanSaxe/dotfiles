-- Hammerspoon config: Tab focusing automation for Leader Key
-- Focus an existing Chrome tab by domain; otherwise open a new one.
--
-- NOTE: Currently Chrome-only for simplicity and guaranteed instant performance.
-- Could be expanded to support other Chromium-based browsers (Arc, Brave, Edge)
-- by detecting default browser and swapping app name in AppleScript.
-- Firefox and Safari have different/limited AppleScript APIs.

-- Enable IPC so the 'hs' command-line tool can communicate with Hammerspoon
hs.ipc.cliInstall()

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

-- Reload config (Cmd+Shift+R)
hs.hotkey.bind({ "cmd", "shift" }, "R", hs.reload)

hs.notify.new({ title = "Hammerspoon", informativeText = "Config loaded" }):send()
