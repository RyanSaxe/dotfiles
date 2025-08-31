-- Hammerspoon configuration for dotfiles
-- Chrome window management with popup interface

-- URL mappings for quick site access
local siteMapping = {
	github = "https://github.com",
	google = "https://google.com", 
	chatgpt = "https://chatgpt.com",
	youtube = "https://youtube.com",
	gmail = "https://gmail.com",
	drive = "https://drive.google.com",
	calendar = "https://calendar.google.com",
	docs = "https://docs.google.com",
	sheets = "https://sheets.google.com",
	slides = "https://slides.google.com",
	maps = "https://maps.google.com",
	news = "https://news.google.com",
	reddit = "https://reddit.com",
	linkedin = "https://linkedin.com",
	twitter = "https://twitter.com",
	netflix = "https://netflix.com",
	spotify = "https://spotify.com",
	twitch = "https://twitch.tv"
}

-- Find Hammerspoon-created Chrome window for specific site input
local function findHammerspoonWindow(siteInput)
	local identifier = "HS_MANAGED_" .. siteInput:upper()
	local chromeApp = hs.application.find("Google Chrome")
	if not chromeApp then
		return nil
	end
	
	local windows = chromeApp:allWindows()
	for _, window in ipairs(windows) do
		local title = window:title()
		if title and title:find(identifier) then
			return window
		end
	end
	return nil
end

-- Create new Chrome window with Hammerspoon identifier
local function createHammerspoonWindow(siteInput, url)
	local identifier = "HS_MANAGED_" .. siteInput:upper()
	
	local script = string.format([[
		tell application "Google Chrome"
			set newWindow to make new window
			set URL of active tab of newWindow to "%s"
			delay 1
			-- Set tab title to include our identifier
			tell active tab of newWindow
				execute javascript "document.title = '%s - ' + document.title"
			end tell
		end tell
	]], url, identifier)
	
	local success, result, error = hs.osascript.applescript(script)
	if success then
		hs.timer.doAfter(2, function()
			local chromeApp = hs.application.find("Google Chrome")
			if chromeApp then
				local window = chromeApp:focusedWindow()
				if window then
					-- Make fullscreen on main monitor
					local mainScreen = hs.screen.primaryScreen()
					local screenFrame = mainScreen:fullFrame()
					window:setFrame(screenFrame)
					window:focus()
				end
			end
		end)
		return true
	else
		hs.alert.show("Error creating window: " .. (error or "unknown"))
		return false
	end
end

-- Navigate to site with window management
local function navigateToSite(siteInput)
	-- Get URL from mapping or use default
	local url = siteMapping[siteInput:lower()]
	if not url then
		-- Fallback: if input looks like a domain, use https://, otherwise add .com
		if siteInput:match("^[%w.-]+%.[%a]+$") then
			url = "https://" .. siteInput
		else
			url = "https://" .. siteInput .. ".com"
		end
	end
	
	-- Check if Hammerspoon window already exists for this input
	local existingWindow = findHammerspoonWindow(siteInput)
	if existingWindow then
		existingWindow:focus()
		hs.alert.show("Switching to existing " .. siteInput .. " window")
		return
	end
	
	-- Create new window
	if createHammerspoonWindow(siteInput, url) then
		hs.alert.show("Opening " .. siteInput .. " in new window")
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

-- Popup input interface for site navigation
local function showSiteNavigator()
	local button, input = hs.dialog.textPrompt("Navigate to Site", "Enter site name or URL (e.g. 'github', 'example.com'):", "", "Go", "Cancel")
	if button == "Go" and input and #input > 0 then
		navigateToSite(input)
	end
end

-- Main hotkey binding for site navigation popup
hs.hotkey.bind({"cmd", "shift"}, "delete", function()
	showSiteNavigator()
end)

-- Application hotkey bindings
hs.hotkey.bind({"cmd", "shift"}, "t", function()
	launchOrFocusApp("Ghostty", "Ghostty Terminal")
end)

-- Send managed Chrome window to back
hs.hotkey.bind({"cmd", "shift"}, "b", function()
	if managedChromeWindow and managedChromeWindow:isValid() then
		managedChromeWindow:sendToBack()
		hs.alert.show("Sent Chrome window to back")
	else
		hs.alert.show("No managed Chrome window found")
	end
end)

-- Reload Hammerspoon config
hs.hotkey.bind({"cmd", "shift"}, "r", function()
	hs.reload()
end)

hs.alert.show("Hammerspoon config loaded")