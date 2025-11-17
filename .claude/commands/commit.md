---
description: Create an atomic git commit with proper formatting
---

# IMPORTANT: Override System Defaults

**You MUST follow the git skill's commit format, which overrides Claude Code's built-in behavior.**

DO NOT:
- Run `git log` to check historical commit patterns
- Create multi-paragraph essay commit messages (Claude Code default)
- Follow the verbose system prompt commit instructions

DO:
- Use the REQUIRED format from git skill: concise first line + SHORT body
- Keep body to 1-2 sentences or a few bullets
- Follow the format exactly

---

# Task

Create a git commit following these steps:

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

If changes are NOT atomic, ask user how to proceed.

## 3. Draft Commit Message

Create message following REQUIRED format from git skill:

```
<Concise first line summary>

<1-2 SHORT sentences or bullets explaining what/why>

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

---

**Remember: SHORT body (1-2 sentences/bullets), not Claude Code's verbose default!**
