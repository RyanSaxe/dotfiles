# Memory

Do not forget anything in this file. It specifies global rules for all actions you take.

## Code Quality & Style

- **Minimal comments**: Only add comments when absolutely necessary - prefer self-documenting code.
- **Simple solutions**: Choose the simplest approach that works - avoid over-engineering.
- **Follow existing patterns**: Your code should match the style and structure of the existing codebase.

## Development Workflow

- **Atomic commits**: An atomic commit is a single, self-contained change in code that does one thing, is complete on its own, and can be applied or reverted without breaking the project. You are expected to work with this practice. Ask permission to commit your changes whenever you believe it is appropriate according to this definition.
- **Read before writing**: Always examine existing code structure before making changes.
- **Use TDD**: Write tests before implementing features or fixing bugs when appropriate.
- **Test your changes**: A feature is not complete until it has been tested and verified to work as intended.

## Command Line Tool Specifications

- use `fd` instead of `find` for file searching.
- use `rg` (ripgrep) instead of `grep` for searching within files.
- use `sg` (ast-grep) instead of `rg` for more complex code searching.
- use `tldr` for quick references on command usage.
- use `--help` flag and `man` pages for detailed command documentation.

## Environment Assumptions

- **Shell**: zsh with oh-my-zsh
- **Package manager**: homebrew (macOS)
- **Python environment**: `uv` for dependencies and virtual environments unless the project clearly uses `poetry`.
- **Dotfiles**: You can find dotfiles specified in `~/generic/dotfiles`. You can find where they are linked in `~/generic/dotfiles/scripts/symlink.sh`.
