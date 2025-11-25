# Git Configuration

Git configuration with delta for syntax-highlighted diffs, TokyoNight theme
integration, and useful aliases.

## Features

- **Delta integration** - Syntax-highlighted side-by-side diffs with TokyoNight
  Night theme
- **zdiff3 merge style** - Enhanced conflict markers showing original, ours, and
  theirs
- **Auto-setup remote** - Automatically sets up remote tracking for new branches
- **Rebase by default** - Pull with rebase instead of merge
- **Useful aliases** - Common git shortcuts

## Configuration Highlights

### Diff & Merge

```gitconfig
[core]
    pager = delta --side-by-side --syntax-theme=tokyonight_night
[interactive]
    diffFilter = delta --color-only
[merge]
    conflictStyle = zdiff3
```

### Workflow Settings

```gitconfig
[push]
    autoSetupRemote = true    # Auto-track remote branches
[pull]
    rebase = true             # Rebase instead of merge
[init]
    defaultBranch = main
```

### Aliases

- `git co` → `checkout`
- `git br` → `branch`
- `git ci` → `commit`
- `git st` → `status`
- `git unstage` → `reset HEAD --`
- `git last` → `log -1 HEAD`
- `git lg` → `log --oneline --graph --decorate --all`

## Global Ignore

The `ignore` file defines patterns to exclude globally across all repositories
(e.g., `.DS_Store`, editor files, etc.).

## Customization

Edit `config` to:

- Add new aliases
- Modify delta display options (remove `--side-by-side` for unified diffs)
- Change merge conflict style
- Update user name/email

Edit `ignore` to add global gitignore patterns.
