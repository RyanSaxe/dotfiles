-- Hammerspoon configuration for dotfiles
-- Generalized prefix system with website floating tabs and app launchers

-- Define the Hammerspoon prefix for all hotkeys
local prefix = {"cmd", "delete"}  -- cmd + backspace

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

-- Helper function to open URL in a floating Chrome window or bring existing to front
local function openOrFocusWebsite(url, title, urlPattern)
	-- First check if window already exists
	local existingWindow = findExistingWindow(urlPattern)
	if existingWindow then
		existingWindow:focus()
		hs.alert.show("Bringing " .. title .. " to front")
		return
	end
	
	-- Create new window if doesn't exist
	local chromeApp = hs.application.find("Google Chrome")
	if chromeApp then
		chromeApp:selectMenuItem({ "File", "New Window" })
		hs.timer.doAfter(0.5, function()
			hs.eventtap.keyStrokes(url)
			hs.eventtap.keyStroke({ "cmd" }, "return")

			-- Wait for page to load then make window floating
			hs.timer.doAfter(2, function()
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
					window:focus()
				end
			end)
		end)
	else
		hs.application.launchOrFocus("Google Chrome")
		hs.timer.doAfter(1, function()
			openOrFocusWebsite(url, title, urlPattern)
		end)
	end
end

-- Reusable application launcher function
local function launchOrFocusApp(appName, displayName)
	local app = hs.application.find(appName)
	if app and app:isFrontmost() then
		-- If app is already frontmost, just show alert
		hs.alert.show(displayName .. " already focused")
	elseif app then
		-- App exists but not frontmost, bring to front
		app:activate()
		hs.alert.show("Bringing " .. displayName .. " to front")
	else
		-- App doesn't exist, launch it
		hs.application.launchOrFocus(appName)
		hs.alert.show("Launching " .. displayName)
	end
end

-- Website definitions for floating tabs
local websites = {
	{ key = "g", url = "https://github.com", title = "GitHub", pattern = "github" },
	{ key = "s", url = "https://google.com", title = "Google", pattern = "google" },
	{ key = "a", url = "https://chatgpt.com", title = "ChatGPT", pattern = "chatgpt" },
	{ key = "y", url = "https://youtube.com", title = "YouTube", pattern = "youtube" },
}

-- Application definitions for launchers
local applications = {
	{ key = "t", appName = "Ghostty", displayName = "Ghostty Terminal" },
}

-- Bind website hotkeys with prefix
for _, site in ipairs(websites) do
	hs.hotkey.bind(prefix, site.key, function()
		openOrFocusWebsite(site.url, site.title, site.pattern)
	end)
end

-- Bind application hotkeys with prefix  
for _, app in ipairs(applications) do
	hs.hotkey.bind(prefix, app.key, function()
		launchOrFocusApp(app.appName, app.displayName)
	end)
end

-- Send all Chrome windows managed by Hammerspoon to back
hs.hotkey.bind(prefix, "b", function()
	local chromeApp = hs.application.find("Google Chrome")
	if chromeApp then
		local windows = chromeApp:allWindows()
		for _, window in ipairs(windows) do
			local title = window:title()
			if title then
				for _, site in ipairs(websites) do
					if string.find(string.lower(title), site.pattern) then
						window:sendToBack()
						break
					end
				end
			end
		end
		hs.alert.show("Sent Chrome website windows to back")
	else
		hs.alert.show("Chrome not running")
	end
end)

-- Reload Hammerspoon config
hs.hotkey.bind(prefix, "r", function()
	hs.reload()
end)

hs.alert.show("Hammerspoon config loaded")