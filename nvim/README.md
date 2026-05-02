# Neovim Configuration

LazyVim-based Neovim configuration with extensive customizations for Python development, Git workflows, Obsidian note-taking, and TokyoNight Night theme integration.

## Features

- **LazyVim base** - Modern Neovim distribution with sensible defaults
- **TokyoNight Night theme** - Heavily customized with Pokemon-themed dashboard
- **Python development** - basedpyright LSP, robust linting/formatting, virtual environment integration
- **Git workflows** - CodeDiff, mini.diff, gitsigns with smart toggling
- **Obsidian integration** - Full note-taking workflow with custom task picker
- **Blink completion** - Fast completion engine with Copilot integration
- **Custom pickers** - Dependency navigation across multiple languages
- **Tmux integration** - Seamless pane navigation between Neovim and Tmux

## Configuration Structure

```text
nvim/
├── lua/
│   ├── config/
│   │   ├── autocmds.lua         # Auto-commands
│   │   ├── keymaps.lua          # Custom keybindings
│   │   ├── lazy.lua             # Lazy.nvim bootstrap
│   │   └── options.lua          # Vim options
│   ├── plugins/                 # Plugin specifications (organized by category)
│   │   ├── ai/                  # AI-powered tools (Sidekick)
│   │   ├── completion/          # Blink.cmp, Copilot
│   │   ├── extra/               # Miscellaneous plugins (Buffergolf)
│   │   ├── git/                 # CodeDiff, mini.diff
│   │   ├── lsp/                 # LSP configs, linting, formatting
│   │   ├── markdown/            # Obsidian, render-markdown, bullets, todo-comments
│   │   ├── navigation/          # Flash, vim-tmux-navigator, file/buffer/dependency navigation
│   │   ├── snacks/              # Snacks.nvim plugins (dashboard, picker, scratch, toggle)
│   │   └── ui/                  # Lualine, bufferline, noice, which-key, colorscheme, visual enhancements
│   ├── custom/                  # Custom modules
│   │   ├── git/                 # Git diff utilities
│   │   ├── obsidian/            # Obsidian task picker
│   │   ├── snacks/              # Snacks.nvim customizations
│   │   ├── visual/              # Visual mode utilities
│   │   └── todos.lua            # TODO comment tracking
│   └── dependency-picker/       # Multi-language dependency navigation
└── init.lua                     # Entry point
```

## Key Plugin Highlights

### LSP & Completion

- **basedpyright** - Python type checking and LSP
- **blink.cmp** - Fast completion engine
- **copilot.lua** - GitHub Copilot integration (disabled in markdown)
- **conform.nvim** - Code formatting
- **nvim-lint** - Linting integration

### Git

- **codediff.nvim** - VSCode-style side-by-side diffs, git difftool/mergetool support
- **mini.diff** - Inline git hunks
- **gitsigns.nvim** - Git signs in gutter

### UI

- **lualine.nvim** - Statusline with Git info, diagnostics, LSP status
- **bufferline.nvim** - Buffer tabs at top
- **noice.nvim** - Enhanced UI for messages, cmdline, and popover
- **which-key.nvim** - Keybinding hints

### Obsidian

- **obsidian.nvim** - Obsidian vault integration
- **render-markdown.nvim** - Markdown rendering
- **Custom task picker** - Search and manage TODO items across notes

### Navigation

- **flash.nvim** - Fast motion plugin
- **vim-tmux-navigator** - Seamless Neovim ↔ Tmux pane navigation
- **dependency-picker** - Navigate dependencies in Python, JS, Rust, Go, Ruby, Lua, Neovim

## Custom Keybindings

Key mappings beyond LazyVim defaults (see `lua/config/keymaps.lua`):

### Visual Mode

- `J` - Move selected lines down
- `K` - Move selected lines up

### Terminal Mode

- `<Esc>` - Enter normal mode

### Git Diff (see `lua/plugins/git/`)

Lowercase = pick branch (base branch highlighted), Uppercase = pick commit (with diff preview)

- `<leader>gdo` - Overlay diff (pick branch) - inline hunks via mini.diff
- `<leader>gdO` - Overlay diff (pick commit)
- `<leader>gdf` - File diff (pick branch) - side-by-side via codediff
- `<leader>gdF` - File diff (pick commit)
- `<leader>gda` - All files diff (pick branch) - codediff explorer
- `<leader>gdA` - All files diff (pick commit)
- `\t` - Toggle CodeDiff inline / side-by-side layout
- `\=` - Equalize CodeDiff layout
- `\h` / `\l` - Shrink / grow current CodeDiff window width
- `\j` / `\k` - Shrink / grow current CodeDiff window height

### Toggles

- `<leader>tp` - Toggle basedpyright diagnostic mode (openFilesOnly ↔ workspace)

### Quit / Session

- `<leader>qr` - Restart Neovim and restore the current layout/context via a temporary session

### Obsidian (see `lua/plugins/obsidian.lua`)

- `<leader>ot` - Open Obsidian task picker
- `<leader>on` - Create new note
- `<leader>os` - Search notes
- `<leader>ol` - Insert link

### Dependency Navigation (see `lua/plugins/dependency-picker.lua`)

- `<leader>ps` - Smart dependency grep (auto-detect language)
- `<leader>pS` - Manual dependency grep (choose language)
- `<leader>pf` - Smart dependency files
- `<leader>pF` - Manual dependency files
- `<leader>pb` - Smart stdlib search
- `<leader>pB` - Manual stdlib search

## Custom Features

### Pokemon Dashboard

The dashboard displays a random Pokemon sprite with matching TokyoNight colors. Colors sync with Tmux statusline via cached color files in `~/.cache/`.

### Dependency Picker

Multi-language dependency navigation supporting:

- **Neovim** - Plugin directories (lazy.nvim, packer, vim-plug)
- **Python** - site-packages, stdlib
- **JavaScript/TypeScript** - node_modules
- **Go** - GOMODCACHE
- **Rust** - cargo registry
- **Ruby** - gem directories
- **Lua** - luarocks, lua_modules

See `lua/dependency-picker/README.md` for detailed usage.

### Git Diff Utilities

Custom modules in `lua/custom/git/` provide:

- **pickers.lua** - Snacks.nvim pickers for commit/branch selection with diff previews
- **diff.lua** - CodeDiff integration for file and all-files diffs
- **utils.lua** - Git helpers (fetch, branch detection, file content at refs)

## TODO

### Bugs

- [ ] In rare scenarios, the `u` command for undo doesn't work and requires restart

### Simple

- [x] Change completion priority: Tab always cycles blink completions, Shift+Tab takes Copilot suggestion
- [x] Generalize Obsidian task picker to work with any markdown directory (not just Obsidian vault)
- [x] Explore alternative background colors - consider picker-style blended opacity or full black (#000000) for seamless Mac edges
- [ ] Extract dependency-picker into standalone plugin for distribution
- [x] Cleanup which-key: organize groups, add proper names and icons, reduce LazyVim default clutter
- [ ] Revisit markdown setup: linting, formatting, blink integration, frontmatter handling for Claude/Obsidian
- [x] Reorganize plugins from flat structure to organized folders by category

### Unclear How Hard

- [ ] Comprehensive LSP/Conform linting review and optimization
- [ ] Properly configure SonarLint - integrate with lsp-check beyond Python
- [ ] Revisit snippets: find optimal UX that doesn't clutter completion menu

### Complex

- [ ] Deep dive into Python LSP ecosystem - prepare for 'ty' release, support pyproject.toml-specified LSPs
- [ ] Optimize git workflow UX across snacks.nvim gh module, codediff, mini.diff, gh-dash, lazygit
- [x] Make Snacks dashboard perfectly centered regardless of odd/even row counts (dynamic statusline toggle absorbs extra row)
- [ ] Set up Jupyter notebook integration with nice UI and cell execution
  - Research molten.nvim (image rendering, output display) vs vim-slime (simpler REPL approach) vs jupytext (convert .ipynb to .py)
  - Configure image rendering in terminal (kitty graphics protocol, sixel, or ueberzug fallback)
  - Set up cell markers (# %% style) with syntax highlighting and folding
  - Add keybindings for cell execution, cell navigation, kernel management
  - Consider quarto.nvim or otter.nvim for enhanced LSP support in code cells
  - Integrate output display (inline images, dataframes, plots) with TokyoNight theming

## Customization

### Adding Plugins

Create new files in `lua/plugins/` following LazyVim conventions:

```lua
return {
  "author/plugin-name",
  opts = {
    -- plugin options
  },
}
```

### Modifying Keybindings

Edit `lua/config/keymaps.lua` or add keybindings to individual plugin specs.

### Changing Theme Colors

Edit `lua/plugins/colorscheme.lua` - all TokyoNight color customizations are defined there.

### Python LSP Settings

Edit `lua/plugins/python.lua` for basedpyright configuration and Python-specific settings.
