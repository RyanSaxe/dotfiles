-- Hammerspoon configuration for dotfiles
-- Website floating tabs keybinds

-- Helper function to open URL in a floating Chrome window
local function openFloatingWebsite(url, title)
    local chromeApp = hs.application.find("Google Chrome")
    if chromeApp then
        chromeApp:selectMenuItem({"File", "New Window"})
        hs.timer.doAfter(0.5, function()
            hs.eventtap.keyStrokes(url)
            hs.eventtap.keyStroke({"cmd"}, "return")
            
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
                        h = screenFrame.h * 0.7
                    }
                    window:setFrame(windowFrame)
                    window:focus()
                end
            end)
        end)
    else
        hs.application.launchOrFocus("Google Chrome")
        hs.timer.doAfter(1, function()
            openFloatingWebsite(url, title)
        end)
    end
end

-- Keybind definitions for floating website tabs
local websites = {
    {key = "g", url = "https://github.com", title = "GitHub"},
    {key = "s", url = "https://google.com", title = "Google"},
    {key = "a", url = "https://chatgpt.com", title = "ChatGPT"},
    {key = "y", url = "https://youtube.com", title = "YouTube"},
}

-- Bind Cmd+Shift+W followed by letter keys to open floating websites
local modal = hs.hotkey.modal.new({"cmd", "shift"}, "w")

function modal:entered()
    hs.alert.show("Website Mode - Press a letter key")
end

function modal:exited()
    hs.alert.closeAll()
end

-- Auto-exit after 3 seconds
modal.timeoutTimer = hs.timer.doAfter(3, function()
    modal:exit()
end)

-- Bind each website to its key
for _, site in ipairs(websites) do
    modal:bind("", site.key, function()
        modal:exit()
        openFloatingWebsite(site.url, site.title)
        hs.alert.show("Opening " .. site.title .. " in floating window")
    end)
end

-- Escape key to exit modal
modal:bind("", "escape", function()
    modal:exit()
end)

-- Show available keybinds
modal:bind("", "h", function()
    local help = "Website Keybinds:\n"
    for _, site in ipairs(websites) do
        help = help .. site.key .. " - " .. site.title .. "\n"
    end
    help = help .. "ESC - Cancel"
    hs.alert.show(help, 5)
end)

-- Reload Hammerspoon config
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "r", function()
    hs.reload()
end)
hs.alert.show("Hammerspoon config loaded")