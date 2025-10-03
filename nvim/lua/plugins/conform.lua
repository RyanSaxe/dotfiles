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

    -- Black configuration with line length 120
    opts.formatters.black = {
      prepend_args = { "--line-length", "120", "--skip-magic-trailing-comma" },
    }

    -- Ruff format configuration with line length 120
    opts.formatters.ruff_format = {
      prepend_args = { "--line-length", "120" },
    }

    -- isort configuration with line length 120 and black compatibility
    opts.formatters.isort = {
      prepend_args = { "--line-length", "120", "--profile", "black" },
    }

    return opts
  end,
}
