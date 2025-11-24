return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      -- disabling lsps on my machine that I'm experimenting with
      ty = false,
      zuban = false,
      -- Three-LSP setup for optimal Python performance:
      -- 1. Ruff: Fast linting and syntax error diagnostics
      -- 2. Basedpyright: Type checking diagnostics only
      -- 3. Pyrefly: Fast completions, hover, and navigation (10x faster than pyright)

      -- Ruff: Handles linting diagnostics and syntax errors
      -- Formatting is handled separately by conform.nvim
      ruff = {
        on_attach = function(client, bufnr)
          -- Disable formatting capabilities - defer to conform.nvim
          client.server_capabilities.documentFormattingProvider = false
          client.server_capabilities.documentRangeFormattingProvider = false
          -- Disable hover - defer to Pyrefly
          client.server_capabilities.hoverProvider = false
        end,
        init_options = {
          settings = {
            showSyntaxErrors = true, -- Enable fast syntax error detection
            lineLength = 120,
            lint = {
              enable = true, -- Enable linting diagnostics (Ruff is extremely fast)
              -- Disable F821 to avoid duplication with basedpyright's reportUndefinedVariable
              -- (which must stay enabled for auto-import code actions)
              ignore = { "F821" }, -- undefined-name (basedpyright handles this + provides auto-import)
            },
            format = {
              args = { "--line-length=120" },
            },
            organizeImports = true, -- Used by conform.nvim for import organization
            -- Disable code action spam
            codeAction = {
              disableRuleComment = { enable = false },
              fixViolation = { enable = false },
            },
          },
        },
      },

      -- Basedpyright: Handles type checking diagnostics and hover documentation
      -- Most capabilities disabled to prevent overlap and improve performance
      basedpyright = {
        on_attach = function(client, bufnr)
          -- Disable everything except type checking diagnostics and hover
          client.server_capabilities.completionProvider = false
          client.server_capabilities.definitionProvider = false
          client.server_capabilities.documentHighlightProvider = false
          client.server_capabilities.documentSymbolProvider = false -- Prevents navic conflict with Pyrefly
          -- hoverProvider ENABLED - basedpyright provides more comprehensive type information
          client.server_capabilities.renameProvider = false
          client.server_capabilities.semanticTokensProvider = false
        end,
        settings = {
          basedpyright = {
            disableOrganizeImports = true, -- Defer to Ruff
            analysis = {
              inlayHints = {
                variableTypes = true,
                functionReturnTypes = true,
                genericTypes = true,
              },
              diagnosticMode = "openFilesOnly", -- Critical for performance
              exclude = { ".venv", "venv" },
              autoImportCompletions = false, -- Completions handled by Pyrefly
              autoSearchPaths = true,
              useLibraryCodeForTypes = true, -- Improves type inference by analyzing library source
              typeCheckingMode = "standard",
            },
            -- Disable checks that overlap with Ruff or hurt performance (20-40% performance improvement)
            -- Ruff overlaps (9 reports)
            reportUnusedImport = "none", -- Ruff F401 handles this
            reportUnusedVariable = "none", -- Ruff F841 handles this
            reportUnusedClass = "none", -- Ruff handles this
            reportUnusedFunction = "none", -- Ruff handles this
            reportDuplicateImport = "none", -- Ruff handles this
            reportWildcardImportFromLibrary = "none", -- Ruff F405 handles this
            reportRedeclaration = "none", -- Ruff F811 handles this
            reportImplicitStringConcatenation = "none", -- Ruff ISC001/ISC002 handles this
            reportConstantRedefinition = "none", -- Ruff handles this
            -- Performance-expensive (1 report)
            reportImportCycles = "none", -- Explicitly noted as slow in basedpyright docs
            -- Optional strictness - reduces noise (6 reports)
            reportOptionalSubscript = "none", -- Generates noise, strictNullChecks-like behavior
            reportOptionalMemberAccess = "none",
            reportOptionalCall = "none",
            reportOptionalIterable = "none",
            reportOptionalContextManager = "none",
            reportOptionalOperand = "none",
            -- Keep reportUndefinedVariable enabled (needed for auto-import code actions)
          },
        },
      },

      -- Pyrefly: Handles completions, go-to-definition, and semantic tokens
      -- Significantly faster than pyright/basedpyright for these operations
      pyrefly = {
        on_attach = function(client, bufnr)
          -- Disable unnecessary capabilities - focus on completions and navigation
          client.server_capabilities.codeActionProvider = false
          client.server_capabilities.documentSymbolProvider = false
          client.server_capabilities.hoverProvider = false -- Defer to basedpyright for comprehensive hover
          client.server_capabilities.inlayHintProvider = false
          client.server_capabilities.referenceProvider = false
          client.server_capabilities.signatureHelpProvider = false
        end,
        -- Pyrefly uses sensible defaults, minimal configuration needed
        settings = {},
      },
    },
  },
}
