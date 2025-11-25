# Memory

Do not forget anything in this file. It specifies global rules for all actions you take.

## Code Quality & Style

- **Minimal comments**: Only when absolutely necessary - prefer self-documenting code
- **Simple solutions**: Simplest approach that works - avoid over-engineering
- **Follow existing patterns**: Match the style and structure of the existing codebase

**Further reading**: [Style Guide](~/.claude/references/style.md)

## Development Workflow

- **Atomic commits**: Single, self-contained change. Ask permission to commit when appropriate
- **Read before writing**: Examine existing code structure before making changes
- **Use TDD when appropriate**: Write tests first for features/bugs when it makes sense
- **Test your changes**: Feature isn't complete until tested and verified

**Further reading**: [Development Workflow](~/.claude/references/development.md), [Testing Guide](~/.claude/references/testing.md)

## Package and Dependency Search

<IMPORTANT>

**Always search for packages and dependencies on the local machine FIRST** before fetching from external sources (web, documentation sites, etc.).

**Why local-first:**

- **Version accuracy**: Exact code the user is running
- **Complete access**: All implementation details, private methods, comments
- **Faster**: No network latency
- **Works offline**: No internet required
- **Debugging ready**: Can trace through actual code

**Search workflow:**

1. Use `fd` to find package directory: `fd -t d "^package_name$" /likely/path`
2. Use `rg` for text search: `rg "pattern" /path/to/package`
3. Use `sg` (ast-grep) for structural search: `sg -p 'def $FUNC($$$):' /path/to/package`
4. Use Read tool to examine specific files

**Only fetch from external sources if:**

1. Package is not installed locally
2. You've asked the user if they want to install it first
3. User explicitly requests external documentation

</IMPORTANT>

## Command Line Tools

- **File search**: `fd` (NOT `find`)
- **Content search**: `rg` / ripgrep (NOT `grep`)
- **Structural code search**: `sg` / ast-grep (for complex patterns)
- **Run tools**: `uvx <tool>` (runs without global install - great for one-off tools)
- **LSP diagnostics**: `lsp-check files/folders` (verify code health with respect to files you change)
- **Quick reference**: `tldr`
- **Detailed docs**: `--help` flag and `man` pages

## Environment

- **Shell**: zsh
- **Package manager**: homebrew (macOS)
- **Dotfiles**: `~/generic/dotfiles` (symlink mappings in `scripts/symlink.sh`)
- **Editor**: Neovim v0.11+
