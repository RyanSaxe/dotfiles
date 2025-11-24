-- Auto-detect Python formatters based on pyproject.toml configuration
-- Supports: black, ruff, isort

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
              if content:match("%[tool%.ruff") or
                 content:match("%[tool%.black") or
                 content:match("%[tool%.isort") then
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

    -- Configure Python formatters
    opts.formatters_by_ft = opts.formatters_by_ft or {}
    opts.formatters_by_ft.python = get_python_formatters

    -- Configure individual formatter settings
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

    return opts
  end,
}
