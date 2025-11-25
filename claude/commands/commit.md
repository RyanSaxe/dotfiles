---
allowed-tools:
  Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git diff:*)
description: Create an atomic git commit with proper formatting
---

# Task

The goal of this command is to help create very clean git commit histories by
making it incredibly easy to create atomic commits, even when working in ways
that are not fully atomic.

Follow these steps:

## 1. Review Changes

```bash
git status
git diff
```

Analyze the changes to understand what was modified.

## 2. Verify Atomic Commit

Ensure changes represent ONE logical change:

- ✅ Single feature, bug fix, or refactoring
- ✅ Tests would pass before and after
- ✅ Can be reverted cleanly
- ❌ Mixed changes (feature + refactor)
- ❌ Incomplete work (WIP)

If the commit is not atomic, present the user with a plan and options for what
to do. Such that you can correctly make sure the commit(s) you write here will
be atomic.

## 3. Draft Commit Message

Create message following this REQUIRED format:

```
<Concise first line summary>

<OPTIONAL: 1-2 SHORT sentences or bullets explaining what/why>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**First line rules:**

- Imperative mood: "Add" not "Added"
- Capitalize first letter
- No period at end
- ~50 characters max

**Body rules:**

- 1-2 sentences max, or a few bullets
- NO multi-paragraph essays
- Brief explanation of what/why

## 4. Add Files and Commit

```bash
# Add relevant files
git add <files>

# Commit with heredoc
git commit -m "$(cat <<'EOF'
<First line summary>

<Short body>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

# Verify
git log -1
```

## 5. Handle Pre-commit Hooks

If pre-commit hooks modify files:

- Check if commit is yours: `git log -1 --format='%an %ae'`
- Check not pushed: `git status` shows "Your branch is ahead"
- If both true: amend commit with modified files
- Otherwise: create NEW commit

Additionally, if the pre-commit hook has failures that were not auto-fixed,
immediately go into planning mode and give the user a plan for how you intend to
fix those failures. The last item in that plan should be to commit.
