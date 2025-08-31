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

-- Global reference to the managed Chrome window
local managedChromeWindow = nil

-- Get or create the managed Chrome window
local function getManagedChromeWindow()
	-- Check if we have a valid reference and window still exists
	if managedChromeWindow and managedChromeWindow:isValid() then
		return managedChromeWindow
	end
	
	-- Try to find an existing Chrome window to use
	local chromeApp = hs.application.find("Google Chrome")
	if chromeApp then
		local windows = chromeApp:allWindows()
		if #windows > 0 then
			-- Use the first available window
			managedChromeWindow = windows[1]
			setupChromeWindow(managedChromeWindow)
			return managedChromeWindow
		end
	end
	
	-- No Chrome or windows found, create new one
	hs.application.launchOrFocus("Google Chrome")
	hs.timer.doAfter(2, function()
		chromeApp = hs.application.find("Google Chrome")
		if chromeApp then
			local windows = chromeApp:allWindows()
			if #windows > 0 then
				managedChromeWindow = windows[1]
				setupChromeWindow(managedChromeWindow)
			end
		end
	end)
	
	return nil
end

-- Setup Chrome window as fullscreen on main monitor
function setupChromeWindow(window)
	if not window then return end
	
	local mainScreen = hs.screen.primaryScreen()
	local screenFrame = mainScreen:fullFrame()
	
	-- Make fullscreen on main monitor
	window:setFrame(screenFrame)
	window:focus()
end

-- Find existing tab with matching site input
local function findExistingTab(siteInput)
	local script = string.format([[
		tell application "Google Chrome"
			set foundTab to false
			set foundWindow to ""
			set foundTabIndex to 0
			
			repeat with w from 1 to count of windows
				repeat with t from 1 to count of tabs of window w
					set tabURL to URL of tab t of window w
					set tabTitle to title of tab t of window w
					
					-- Check if this tab was created by our system for this input
					if tabTitle contains "hs_managed_%s" or tabURL contains "%s" then
						set foundTab to true
						set foundWindow to w
						set foundTabIndex to t
						exit repeat
					end if
				end repeat
				if foundTab then exit repeat
			end repeat
			
			if foundTab then
				set active tab index of window foundWindow to foundTabIndex
				set index of window foundWindow to 1
				return "found"
			else
				return "not_found"
			end if
		end tell
	]], siteInput, siteInput)
	
	local success, result = hs.osascript.applescript(script)
	return success and result == "found"
end

-- Navigate to site in managed Chrome window
local function navigateToSite(siteInput)
	-- Get URL from mapping or use default
	local url = siteMapping[siteInput:lower()]
	if not url then
		-- Fallback: if input looks like a domain, use https://, otherwise use the input as-is
		if siteInput:match("^[%w.-]+%.[%a]+$") then
			url = "https://" .. siteInput
		else
			url = "https://" .. siteInput .. ".com"
		end
	end
	
	-- Check if tab already exists for this input
	if findExistingTab(siteInput) then
		hs.alert.show("Switched to existing " .. siteInput .. " tab")
		return
	end
	
	-- Get or create the managed window
	local window = getManagedChromeWindow()
	
	-- Open in new tab with identifier
	local script = string.format([[
		tell application "Google Chrome"
			activate
			if (count of windows) = 0 then
				make new window
			end if
			set targetWindow to window 1
			set newTab to make new tab at end of tabs of targetWindow
			set URL of newTab to "%s"
			set title of newTab to "hs_managed_%s - " & title of newTab
			set active tab index of targetWindow to (count of tabs of targetWindow)
		end tell
	]], url, siteInput)
	
	local success, result, error = hs.osascript.applescript(script)
	if success then
		hs.alert.show("Opening " .. siteInput)
		-- Ensure window is properly configured after navigation
		hs.timer.doAfter(1, function()
			local chromeApp = hs.application.find("Google Chrome")
			if chromeApp then
				local windows = chromeApp:allWindows()
				if #windows > 0 then
					managedChromeWindow = windows[1]
					setupChromeWindow(managedChromeWindow)
				end
			end
		end)
	else
		hs.alert.show("Error opening " .. siteInput .. ": " .. (error or "unknown"))
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
	local inputModal = hs.textPrompt.new()
	inputModal:title("Navigate to Site")
	inputModal:informativeText("Enter site name or URL (e.g. 'github', 'example.com')")
	inputModal:defaultText("")
	inputModal:callback(function(result, input)
		if result == hs.textPrompt.buttonTypes.ok and input and #input > 0 then
			navigateToSite(input)
		end
	end)
	inputModal:show()
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