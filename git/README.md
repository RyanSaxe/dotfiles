# Git Configuration

Git configuration with Hunk as the primary interactive diff pager, delta as a
stable fallback, TokyoNight theme integration, and useful aliases.

## Features

- **Hunk pager** - Review-first terminal diff UI for `git diff`, `git show`,
  and agent-note workflows
- **Delta fallback** - Syntax-highlighted side-by-side diffs for fallback
  aliases and `git add -p`
- **zdiff3 merge style** - Enhanced conflict markers showing original, ours,
  and theirs
- **Auto-setup remote** - Automatically sets up remote tracking for new branches
- **Rebase by default** - Pull with rebase instead of merge
- **Useful aliases** - Common git shortcuts

## Configuration Highlights

### Diff & Merge

```gitconfig
[core]
    pager = hunk pager
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
- `git ddiff` → run `git diff` through delta
- `git dshow` → run `git show` through delta
- `git hwatch` → open `hunk diff --watch`

## Global Ignore

The `ignore` file defines patterns to exclude globally across all repositories
(e.g., `.DS_Store`, editor files, etc.).

## Customization

Edit `config` to:

- Add new aliases
- Modify Hunk or delta fallback pager options
- Change merge conflict style
- Update user name/email

Edit `ignore` to add global gitignore patterns.
