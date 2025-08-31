# Global Claude Code Instructions

## Code Quality & Style

- **Atomic commits**: Make small, focused commits that do one thing well
- **Minimal comments**: Only add comments when absolutely necessary - prefer self-documenting code
- **Simple solutions**: Choose the simplest approach that works - avoid over-engineering
- **Follow existing patterns**: Always check existing code style and conventions before making changes

## Development Workflow

- **Read before writing**: Always examine existing code structure before making changes
- **Test your changes**: Run lints, tests, and builds when available
- **Clean code**: Prioritize readability and maintainability over cleverness

## Claude Code Best Practices

- **Use tools efficiently**: Batch multiple independent tool calls in single responses
- **Search smart**: Use Task tool for broad searches, direct tools for specific files
- **Stay focused**: Complete one task fully before moving to the next
- **Be concise**: Keep responses short and actionable

## Git Workflow

- **Meaningful messages**: Write clear commit messages explaining why, not what
- **Branch hygiene**: Keep branches focused and up-to-date with main
- **Review changes**: Always check `git diff` before committing

## Environment Assumptions

- Primary editor: neovim
- Shell: zsh with oh-my-zsh
- Package manager: homebrew (macOS)
- Git diff tool: delta
- Theme preference: dark mode across all tools