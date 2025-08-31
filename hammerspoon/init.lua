-- Hammerspoon configuration for dotfiles
-- Direct hotkey bindings for websites and applications

-- Helper function to find existing Chrome window with specific URL pattern
local function findExistingWindow(urlPattern)
	local chromeApp = hs.application.find("Google Chrome")
	if not chromeApp then
		return nil
	end
	
	local windows = chromeApp:allWindows()
	for _, window in ipairs(windows) do
		local title = window:title()
		if title and string.find(string.lower(title), urlPattern) then
			return window
		end
	end
	return nil
end

-- Helper function to open URL in Chrome using AppleScript (avoids duplicate tabs)
local function openOrFocusWebsite(url, title, urlPattern)
	-- First check if window already exists
	local existingWindow = findExistingWindow(urlPattern)
	if existingWindow then
		existingWindow:focus()
		hs.alert.show("Bringing " .. title .. " to front")
		return
	end
	
	-- Use AppleScript to open URL properly
	local script = string.format([[
		tell application "Google Chrome"
			activate
			open location "%s"
		end tell
	]], url)
	
	local success, result, error = hs.osascript.applescript(script)
	if success then
		hs.alert.show("Opening " .. title)
		-- Wait for page to load then make window floating
		hs.timer.doAfter(3, function()
			local window = hs.application.frontmostApplication():focusedWindow()
			if window then
				-- Set window to floating size and position
				local screen = window:screen()
				local screenFrame = screen:frame()
				local windowFrame = {
					x = screenFrame.x + screenFrame.w * 0.2,
					y = screenFrame.y + screenFrame.h * 0.15,
					w = screenFrame.w * 0.6,
					h = screenFrame.h * 0.7,
				}
				window:setFrame(windowFrame)
			end
		end)
	else
		hs.alert.show("Error opening " .. title .. ": " .. (error or "unknown"))
	end
end

-- Helper function to launch or focus applications
local function launchOrFocusApp(appName, displayName)
	local app = hs.application.find(appName)
	if app and app:isFrontmost() then
		hs.alert.show(displayName .. " already focused")
	elseif app then
		app:activate()
		hs.alert.show("Bringing " .. displayName .. " to front")
	else
		hs.application.launchOrFocus(appName)
		hs.alert.show("Launching " .. displayName)
	end
end

-- Website hotkey bindings
hs.hotkey.bind({"cmd", "shift"}, "g", function()
	openOrFocusWebsite("https://github.com", "GitHub", "github")
end)

hs.hotkey.bind({"cmd", "shift"}, "s", function()
	openOrFocusWebsite("https://google.com", "Google", "google")
end)

hs.hotkey.bind({"cmd", "shift"}, "a", function()
	openOrFocusWebsite("https://chatgpt.com", "ChatGPT", "chatgpt")
end)

hs.hotkey.bind({"cmd", "shift"}, "y", function()
	openOrFocusWebsite("https://youtube.com", "YouTube", "youtube")
end)

-- Application hotkey bindings
hs.hotkey.bind({"cmd", "shift"}, "t", function()
	launchOrFocusApp("Ghostty", "Ghostty Terminal")
end)

-- Send all managed Chrome windows to back
hs.hotkey.bind({"cmd", "shift"}, "b", function()
	local chromeApp = hs.application.find("Google Chrome")
	if chromeApp then
		local patterns = {"github", "google", "chatgpt", "youtube"}
		local windowsSent = 0
		local windows = chromeApp:allWindows()
		
		for _, window in ipairs(windows) do
			local title = window:title()
			if title then
				for _, pattern in ipairs(patterns) do
					if string.find(string.lower(title), pattern) then
						window:sendToBack()
						windowsSent = windowsSent + 1
						break
					end
				end
			end
		end
		
		if windowsSent > 0 then
			hs.alert.show("Sent " .. windowsSent .. " Chrome windows to back")
		else
			hs.alert.show("No matching Chrome windows found")
		end
	else
		hs.alert.show("Chrome not running")
	end
end)

-- Reload Hammerspoon config
hs.hotkey.bind({"cmd", "shift"}, "r", function()
	hs.reload()
end)

hs.alert.show("Hammerspoon config loaded")