-- Formatter configuration for multiple languages
-- Python: Auto-detects black/ruff/isort based on pyproject.toml
-- Lua: stylua (respects .stylua.toml if present)
-- Shell: shfmt for bash/sh/zsh scripts
-- JSON: prettier for consistent formatting
-- Markdown: markdownlint for style enforcement (no line wrapping)
-- Web (JS/TS/CSS/HTML): prettier for consistent formatting

return {
  "stevearc/conform.nvim",
  opts = function(_, opts)
    -- Helper function to check if a tool is configured in pyproject.toml
    local function has_tool_in_pyproject(tool_name)
      local root = vim.fn.getcwd()
      local pyproject_path = root .. "/pyproject.toml"

      -- Check if pyproject.toml exists
      local file = io.open(pyproject_path, "r")
      if not file then
        return false
      end

      -- Read the file and check for [tool.{tool_name}] section
      local content = file:read("*all")
      file:close()

      -- Simple pattern matching for [tool.toolname] sections
      return content:match("%[tool%." .. tool_name .. "%]") ~= nil
    end

    -- Helper function to detect if project has any formatter configuration
    -- This checks for various config files that formatters auto-detect
    local function has_formatter_config()
      -- Check for various formatter config files
      local config_files = {
        "ruff.toml",
        ".ruff.toml",
        "pyproject.toml",
        ".isort.cfg",
        "setup.cfg",
        ".editorconfig",
      }

      -- Use vim.fs.find to search upward from current directory
      local found = vim.fs.find(config_files, {
        upward = true,
        stop = vim.fn.expand("~"), -- Stop at home directory
        path = vim.fn.getcwd(),
      })

      -- If we found config files, check if they contain formatter settings
      if #found > 0 then
        for _, file_path in ipairs(found) do
          if file_path:match("pyproject%.toml$") then
            -- For pyproject.toml, check if it has any formatter tool sections
            local file = io.open(file_path, "r")
            if file then
              local content = file:read("*all")
              file:close()
              -- Check for any formatter tool sections
              if content:match("%[tool%.ruff") or content:match("%[tool%.black") or content:match("%[tool%.isort") then
                return true
              end
            end
          else
            -- For other config files, their mere presence indicates config
            return true
          end
        end
      end

      return false
    end

    -- Function to determine which formatters to use for Python
    local function get_python_formatters()
      local formatters = {}

      -- Check for formatters in order of precedence
      local has_black = has_tool_in_pyproject("black")
      local has_ruff = has_tool_in_pyproject("ruff")
      local has_isort = has_tool_in_pyproject("isort")

      -- If black is configured, use black for formatting
      if has_black then
        table.insert(formatters, "black")
      -- Otherwise, if ruff is configured, use ruff for formatting
      elseif has_ruff then
        table.insert(formatters, "ruff_format")
      end

      -- Handle import sorting
      if has_isort then
        -- isort should run before the formatter
        table.insert(formatters, 1, "isort")
      elseif has_ruff and not has_black then
        -- ruff can also organize imports, but only if we're using ruff for formatting
        table.insert(formatters, 1, "ruff_organize_imports")
      end

      -- Fallback to ruff if nothing is detected (ruff is more common nowadays)
      if #formatters == 0 then
        formatters = { "ruff_organize_imports", "ruff_format" }
      end

      return formatters
    end

    -- ══════════════════════════════════════════════════════════════════════════
    -- Formatter assignments by filetype
    -- ══════════════════════════════════════════════════════════════════════════
    opts.formatters_by_ft = opts.formatters_by_ft or {}

    -- Python: Dynamic detection based on project config (see get_python_formatters above)
    opts.formatters_by_ft.python = get_python_formatters

    -- Lua: stylua is the de facto standard, respects .stylua.toml if present
    opts.formatters_by_ft.lua = { "stylua" }

    -- Shell scripts: shfmt handles bash, sh, and zsh
    -- Note: shfmt uses Google's shell style guide by default
    opts.formatters_by_ft.sh = { "shfmt" }
    opts.formatters_by_ft.bash = { "shfmt" }
    opts.formatters_by_ft.zsh = { "shfmt" }

    -- JSON/JSONC: prettier provides consistent formatting
    -- JSONC is JSON with comments (used in VSCode configs, tsconfig, etc.)
    opts.formatters_by_ft.json = { "prettier" }
    opts.formatters_by_ft.jsonc = { "prettier" }

    -- Markdown: markdownlint with --fix for auto-formatting
    -- Does NOT wrap lines (markdown is read with word wrap enabled)
    opts.formatters_by_ft.markdown = { "markdownlint" }

    -- Web development: prettier handles JS, TS, CSS, HTML, and variants
    -- Uses project's .prettierrc if present, otherwise sensible defaults
    opts.formatters_by_ft.javascript = { "prettier" }
    opts.formatters_by_ft.javascriptreact = { "prettier" }
    opts.formatters_by_ft.typescript = { "prettier" }
    opts.formatters_by_ft.typescriptreact = { "prettier" }
    opts.formatters_by_ft.css = { "prettier" }
    opts.formatters_by_ft.html = { "prettier" }
    opts.formatters_by_ft.vue = { "prettier" }
    opts.formatters_by_ft.svelte = { "prettier" }
    opts.formatters_by_ft.astro = { "prettier" }

    -- ══════════════════════════════════════════════════════════════════════════
    -- Individual formatter settings
    -- ══════════════════════════════════════════════════════════════════════════
    opts.formatters = opts.formatters or {}

    -- Black configuration with conditional line length
    -- Only apply line-length if no project config exists
    opts.formatters.black = {
      append_args = function(self, ctx)
        if has_formatter_config() then
          -- Let black auto-detect from project config
          return {}
        else
          -- Apply user's default line length
          return { "--line-length", "120" }
        end
      end,
    }

    -- Ruff format configuration with conditional line length
    -- We need to rebuild the full args list for ruff_format since it uses 'args' not 'append_args'
    opts.formatters.ruff_format = {
      args = function(self, ctx)
        local base_args = { "format", "--stdin-filename", "$FILENAME", "-" }

        if not has_formatter_config() then
          -- Insert line-length after 'format' but before other args
          table.insert(base_args, 2, "--line-length")
          table.insert(base_args, 3, "120")
        end
        -- If project has config, ruff will auto-detect settings

        return base_args
      end,
    }

    -- Ruff organize imports configuration (no line-length needed for imports)
    -- But we keep this for consistency and potential future options
    opts.formatters.ruff_organize_imports = {
      args = { "check", "--select", "I", "--fix", "--stdin-filename", "$FILENAME", "-" },
    }

    -- isort configuration with conditional line length and black profile
    opts.formatters.isort = {
      append_args = function(self, ctx)
        if has_formatter_config() then
          -- Let isort auto-detect from project config (.isort.cfg, pyproject.toml, etc.)
          return {}
        else
          -- Apply user's defaults: line-length 120 and black compatibility
          return { "--line-length", "120", "--profile", "black" }
        end
      end,
    }

    -- shfmt configuration for shell scripts
    -- -i 2: Use 2-space indentation (consistent with most style guides)
    -- -ci: Indent switch cases
    -- -bn: Binary operators at start of line (for line continuation)
    -- -sr: Redirect operators with space (> file instead of >file)
    opts.formatters.shfmt = {
      prepend_args = { "-i", "2", "-ci", "-bn", "-sr" },
    }

    -- prettier configuration for JSON
    -- Uses project's .prettierrc if present, otherwise sensible defaults
    -- No special args needed for JSON formatting

    -- markdownlint configuration
    -- --fix: Auto-fix fixable issues
    -- --config: Use the dotfiles markdownlint config
    opts.formatters.markdownlint = {
      prepend_args = { "--fix", "--config", vim.fn.expand("~/.config/nvim/.markdownlint.yaml") },
    }

    return opts
  end,
}
