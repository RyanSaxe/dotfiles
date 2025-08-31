-- Simple Hammerspoon config: URL shortcuts + terminal switching
-- Focus an existing Chrome tab by domain; otherwise open a new one.

local sites = {
	-- key  = {domain, fallback URL}
	A = { "chatgpt.com", "https://chatgpt.com" },
	G = { "github.com", "https://github.com" },
	Y = { "youtube.com", "https://youtube.com" },
	M = { "outlook.com", "https://outlook.com" },
	S = { "google.com", "https://google.com" },
}

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

local function focusByDomainOrOpen(domain, url)
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

-- Create hotkeys for each site (Cmd+Shift+Letter)
for key, cfg in pairs(sites) do
	local domain, url = cfg[1], cfg[2]
	hs.hotkey.bind({ "cmd", "shift" }, key, function()
		focusByDomainOrOpen(domain, url)
	end)
end

-- Terminal focus (Cmd+Shift+T)
hs.hotkey.bind({ "cmd", "shift" }, "T", function()
	hs.application.launchOrFocus("Ghostty")
end)

-- Toggle between browser and terminal (Cmd+Shift+Delete)
hs.hotkey.bind({ "cmd", "shift" }, "delete", function()
	local chrome = hs.application.find("Google Chrome")
	local ghostty = hs.application.find("Ghostty")
	if chrome and chrome:isFrontmost() then
		if ghostty then
			ghostty:activate()
			hs.alert.show("Terminal")
		end
	else
		if chrome then
			chrome:activate()
			hs.alert.show("Browser")
		end
	end
end)

-- Reload config (Cmd+Shift+R)
hs.hotkey.bind({ "cmd", "shift" }, "R", hs.reload)

hs.alert.show("Hammerspoon loaded")
