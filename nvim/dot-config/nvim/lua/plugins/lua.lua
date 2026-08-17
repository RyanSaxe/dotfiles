-- Lua is held to the same standard as the typed languages: `no-unknown`
-- at `Any!` means nothing may have an uninferable type. The editor gets
-- exactly the libraries CI gets, from lua/luals.lua, so a warning here is
-- a warning there — the property the whole gate depends on.
--
-- These live in lua_ls settings rather than `.luarc.json` because
-- `.luarc.json` cannot name machine-specific paths, and LuaLS gives it
-- precedence over client settings: a `workspace.library` there would
-- silently win over the resolved one.
return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      lua_ls = {
        settings = {
          Lua = {
            runtime = { version = "LuaJIT" },
            workspace = {
              library = require("luals").libraries(),
              checkThirdParty = false,
            },
            diagnostics = {
              neededFileStatus = { ["no-unknown"] = "Any!" },
              -- Warn about our code, never about the libraries.
              libraryFiles = "Disable",
            },
          },
        },
      },
    },
  },
}
