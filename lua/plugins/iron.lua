return {
  "Vigemus/iron.nvim",
  config = function()
    local iron = require("iron.core")
    local common = require("iron.fts.common")

    iron.setup({
      config = {
        -- Whether a repl should be discarded or not
        scratch_repl = true,
        -- Your repl definitions come here
        repl_definition = {
          sh = {
            -- Can be a table or a function that
            -- returns a table (see below)
            command = { "zsh" },
          },
          python = {
            command = { "ipython", "--no-autoindent" },
            format = common.bracketed_paste_python,
            block_dividers = { "# %%", "#%%" },
          },
        },
        repl_filetype = function(bufnr, ft)
          return ft
          -- or return a string name such as the following
          -- return "iron"
        end,
        -- How the repl window will be displayed
        -- See below for more information
        repl_open_cmd = { require("iron.view").split.vertical.rightbelow("%40") },
      },
      -- Iron doesn't set keymaps by default anymore.
      -- You can set them here or manually add keymaps to the functions in iron.core
      keymaps = {
        toggle_repl = "<leader>zy",
        send_motion = "<leader>zsc",
        visual_send = "<leader>zsc",
        send_file = "<leader>zsf",
        send_line = "<leader>zsl",
        send_mark = "<leader>zsm",
        mark_motion = "<leader>zmc",
        mark_visual = "<space>mc",
        remove_mark = "<space>md",
        cr = "<space>s<cr>",
        interrupt = "<leader>zi",
        exit = "<leader>zq",
        clear = "<leader>zc",
      },
      -- If the highlight is on, you can change how it looks
      -- For the available options, check nvim_set_hl
      highlight = {
        italic = true,
      },
      ignore_blank_lines = true, -- ignore blank lines when sending visual select lines
    })

    -- iron also has a list of commands, see :h iron-commands for all available commands
    vim.keymap.set("n", "<space>rs", "<cmd>IronRepl<cr>")
    vim.keymap.set("n", "<space>rr", "<cmd>IronRestart<cr>")
    vim.keymap.set("n", "<space>rf", "<cmd>IronFocus<cr>")
    vim.keymap.set("n", "<space>rh", "<cmd>IronHide<cr>")
  end,
}
