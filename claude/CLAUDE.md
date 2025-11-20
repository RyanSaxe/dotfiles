# Memory

Do not forget anything in this file. It specifies global rules for all actions you take.

## Structure

This configuration uses a **skills-based architecture**:

- **skills/**: Auto-invoked by Claude based on context (language-specific rules, code practices)
- **references/**: Detailed documentation linked from skills and this file

## Code Quality & Style

- **Minimal comments**: Only when absolutely necessary - prefer self-documenting code
- **Simple solutions**: Simplest approach that works - avoid over-engineering
- **Follow existing patterns**: Match the style and structure of the existing codebase

**Further reading**: [Style Guide](references/style.md)

## Development Workflow

- **Atomic commits**: Single, self-contained change. Ask permission to commit when appropriate
- **Read before writing**: Examine existing code structure before making changes
- **Use TDD when appropriate**: Write tests first for features/bugs when it makes sense
- **Test your changes**: Feature isn't complete until tested and verified

**Further reading**: [Development Workflow](references/development.md), [Testing Guide](references/testing.md)

## Command Line Tools

- **File search**: `fd` (NOT `find`)
- **Content search**: `rg` / ripgrep (NOT `grep`)
- **Structural code search**: `sg` / ast-grep (for complex patterns)
- **Run Python tools**: `uvx <tool>` (runs without global install - great for one-off tools)
- **LSP diagnostics**: `lsp-check files/folders` (verify code health with respect to files you change)
- **Quick reference**: `tldr`
- **Detailed docs**: `--help` flag and `man` pages

## Environment

- **Shell**: zsh with oh-my-zsh
- **Package manager**: homebrew (macOS)
- **Python**: `uv` for dependencies/virtualenvs (unless project uses `poetry`)
- **Dotfiles**: `~/generic/dotfiles` (symlink mappings in `scripts/symlink.sh`)
- **Editor**: Neovim v0.11.4
