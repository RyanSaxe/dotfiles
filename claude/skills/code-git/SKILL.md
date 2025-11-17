---
name: git
description: Git workflow patterns and commit practices. Use when committing changes, resolving conflicts, managing branches, or following atomic commit principles. Ensures clean git history.
---

## Quick Reference

**Atomic commit:**

- One logical change
- Tests pass before and after
- Can be reverted cleanly

**Commit message format:**

```
Add feature to handle user authentication

Implement JWT-based authentication with refresh tokens.
Includes middleware for protected routes.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Base branch:** Check repo's default (usually `main`, `master`, or `develop`)

**Related:**

- [Development workflow](../../../references/development.md) - Full workflow guidance
- [Style guide](../../../references/style.md) - Code quality standards

---

## Atomic Commits

**Definition:** A single, self-contained change that can stand alone.

**Characteristics:**

- **One logical change**: Don't mix refactoring with new features
- **Tests pass**: Before and after the commit
- **Can be reverted**: Without breaking other functionality
- **Self-contained**: Includes all related changes

### Good Atomic Commits

```bash
# Good - single feature
git commit -m "Add user authentication with JWT"

# Good - single bug fix
git commit -m "Fix null pointer in payment processing"

# Good - single refactoring
git commit -m "Extract validation logic into validator class"
```

### Bad Non-Atomic Commits

```bash
# Bad - mixed changes
git commit -m "Add feature X, fix bug Y, refactor Z"

# Bad - incomplete
git commit -m "WIP: partial implementation"

# Bad - too granular
git commit -m "Add opening brace"
git commit -m "Add closing brace"
```

---

## Pre-Commit Hooks

**Recommended:** Use pre-commit hooks to catch issues before committing.

### Common Pre-Commit Checks

- **Linting**: Run ruff, eslint, etc.
- **Formatting**: Run black, prettier, etc.
- **Type checking**: Run mypy, tsc, etc.
- **Tests**: Run relevant tests
- **Security**: Check for secrets, vulnerabilities

### If Repo Doesn't Have Hooks

When working in a repository without pre-commit hooks:

1. **Ask the user** if they want to set them up
2. **Offer to help** configure appropriate hooks for the project
3. **Suggest tools**:
   - Python: `pre-commit` framework
   - Node: `husky` + `lint-staged`
   - General: `.git/hooks/` scripts

**Example setup offer:**
> "This repo doesn't have pre-commit hooks. Would you like me to set up hooks for linting and testing? This helps catch issues before committing."

---

## Commit Messages

### Format

```
<type>: <subject>

<body (optional)>

<footer (optional)>
```

### Subject Line (First Line)

- **Imperative mood**: "Add feature" not "Added feature" or "Adds feature"
- **Capitalize first letter**: "Add" not "add"
- **No period at end**: "Add feature" not "Add feature."
- **~50 characters**: Short and descriptive
- **Describe what and why**: Not how (code shows how)

```bash
# Good
Add user authentication
Fix memory leak in image processing
Refactor database connection logic

# Bad
added user authentication  # Wrong tense
fix bug  # Too vague
refactored the database connection pooling and also fixed the memory issue  # Too long, multiple changes
```

### Body (Optional)

- Explain **why**, not what (code shows what)
- Wrap at 72 characters
- Separate from subject with blank line

```
Add caching layer for API responses

Without caching, every request hits the database causing slow response
times. This adds Redis caching with 5-minute TTL for read-only endpoints.

Performance testing shows 80% reduction in database load.
```

### Footer (For Claude Code Commits)

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## Branch Management

### Identifying Base Branch

Different repos use different base branches:

- `main` (most common for new repos)
- `master` (older repos)
- `develop` or `dev` (some workflows)

```bash
# Check default branch
git remote show origin | grep "HEAD branch"

# Or check current branch tracking
git branch -vv
```

**In this guide:** "base branch" refers to your repo's default branch.

### Branch Naming

```bash
# Feature branches
feature/user-authentication
feature/payment-integration

# Bug fixes
fix/null-pointer-in-checkout
fix/memory-leak

# Refactoring
refactor/extract-validation-logic
```

### Keep Branches Short-Lived

- Merge to base branch frequently (days, not weeks)
- Small, focused changes
- Easier to review and merge

### Sync with Base Branch Regularly

```bash
# Update your branch with latest base branch
git checkout main  # Or master, develop, etc.
git pull
git checkout feature/my-feature
git rebase main    # Or: git merge main
```

---

## Rebase vs Merge

### Use Rebase When

- **Updating feature branch** with latest base branch
- **Cleaning up local commits** before pushing
- **Linear history** is desired

```bash
# Rebase feature branch onto base branch
git checkout feature/my-feature
git rebase main  # Replace 'main' with your base branch
```

### Use Merge When

- **Integrating feature** into base branch (PR merge)
- **Preserving branch history** matters
- **Avoiding rewrite** of pushed commits

```bash
# Merge feature into base branch
git checkout main  # Or your base branch
git merge feature/my-feature
```

### Never Rebase Pushed Commits

Rewriting history that others depend on causes problems.

---

## Conflict Resolution

### When Conflicts Occur

```bash
# During merge or rebase
git status  # See conflicted files

# Edit files to resolve conflicts
# Look for <<<<<<< ======= >>>>>>> markers

# After resolving
git add resolved-file.txt
git rebase --continue  # If rebasing
git commit             # If merging
```

### Resolving Conflicts

1. **Understand both sides**: Read both versions
2. **Test after resolution**: Make sure code works
3. **Commit separately**: Don't mix conflict resolution with other changes

```bash
# After resolving conflicts
git add .
git rebase --continue

# Then make any additional changes in separate commit
git commit -m "Adjust formatting after merge"
```

---

## Common Workflows

### Starting New Feature

```bash
# Create and switch to feature branch
git checkout -b feature/new-feature

# Make changes and commit
git add .
git commit -m "Add new feature"

# Push to remote
git push -u origin feature/new-feature
```

### Updating Feature Branch

```bash
# Get latest changes from base branch
git checkout main  # Or master, develop, etc.
git pull

# Update feature branch
git checkout feature/my-feature
git rebase main  # Or: git merge main

# Force push if rebased (only if you haven't shared the branch)
git push --force-with-lease
```

### Before Pushing

```bash
# Check what you're about to push
git log origin/main..HEAD  # Replace 'main' with your base branch

# Run tests (or let pre-commit hooks do this)
pytest  # or your test command

# Check for issues
git status
git diff origin/main  # Replace with your base branch
```

---

## Git Hygiene

- **Commit often**: Small, logical commits
- **Pull before push**: Avoid conflicts
- **Review before commit**: `git diff --staged`
- **Write good messages**: Future you will thank you
- **Test before commit**: Don't break the base branch
- **Don't commit secrets**: Use .gitignore
- **Use pre-commit hooks**: Catch issues early

---

## Useful Commands

```bash
# Undo last commit (keep changes)
git reset --soft HEAD~1

# Undo last commit (discard changes)
git reset --hard HEAD~1

# Amend last commit
git commit --amend

# Interactive rebase (clean up commits)
git rebase -i HEAD~3

# Show commit history
git log --oneline --graph

# Show what changed
git diff
git diff --staged
git diff main..feature/branch  # Replace 'main' with base branch

# Stash changes temporarily
git stash
git stash pop
```

---

## Related Resources

- [Development workflow](../../../references/development.md) - Complete development process
- [Testing guide](../../../references/testing.md) - Test before committing
- [Style guide](../../../references/style.md) - Code quality standards
