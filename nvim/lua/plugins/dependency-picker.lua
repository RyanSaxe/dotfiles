-- Dependency Picker: Smart dependency navigation for multiple languages
-- Custom local plugin for searching within project dependencies and standard libraries

return {
  "LazyVim/LazyVim",
  event = "VeryLazy",
  init = function()
    local dep_picker = require("dependency-picker")

    -- Configure detector selection logic:
    -- Prefer Neovim detector when "nvim" appears in the file path
    dep_picker.setup({
      enabled_languages = nil, -- All languages enabled by default
      select_detector = function(matching_detectors, context)
        -- If "nvim" is anywhere in the absolute path, prefer Neovim detector
        if context.bufpath:match("nvim") then
          for _, match in ipairs(matching_detectors) do
            if match.detector.name == "Neovim" then
              return match
            end
          end
        end
        -- Default: return first match
        return matching_detectors[1]
      end,
    })
  end,
  keys = {
    {
      "<leader>ps",
      function()
        require("dependency-picker").smart_grep()
      end,
      desc = "Smart grep: auto-detect dependency from filetype",
    },
    {
      "<leader>pS",
      function()
        require("dependency-picker").manual_search("grep")
      end,
      desc = "Manual grep: select language then dependency",
    },
    {
      "<leader>pf",
      function()
        require("dependency-picker").smart_files()
      end,
      desc = "Smart file search: auto-detect dependency from filetype",
    },
    {
      "<leader>pF",
      function()
        require("dependency-picker").manual_search("files")
      end,
      desc = "Manual file search: select language then dependency",
    },
    {
      "<leader>pb",
      function()
        require("dependency-picker").smart_search_stdlib("grep")
      end,
      desc = "Smart stdlib grep: auto-detect language stdlib",
    },
    {
      "<leader>pB",
      function()
        require("dependency-picker").manual_search_stdlib("grep")
      end,
      desc = "Manual stdlib grep: select language stdlib",
    },
    {
      "<localleader>/",
      function()
        require("dependency-picker").smart_grep()
      end,
      desc = "Grep in dependency (filetype-specific)",
    },
    {
      "<localleader>f",
      function()
        require("dependency-picker").smart_files()
      end,
      desc = "Search files in dependency (filetype-specific)",
    },
  },
}
