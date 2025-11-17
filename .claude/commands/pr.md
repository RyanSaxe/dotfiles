---
description: Create a draft pull request
---

# Task

Create a pull request following the standard Claude Code PR workflow, with these customizations:

## Customizations

1. **Always create as DRAFT**: Use `--draft` flag with `gh pr create`
2. **Format guidance**: Follow git skill format for title and body structure

## Standard PR Workflow

Follow the built-in Claude Code PR process:

1. Run `git status`, `git diff main...HEAD`, and `git log main..HEAD` to understand all changes
2. Analyze the FULL branch history (all commits, not just latest)
3. Draft PR title (concise, imperative, ~50 chars)
4. Draft PR body with:
   - Summary section (2-3 key bullets)
   - Test Plan section (actionable test steps)
5. Push branch if needed: `git push -u origin $(git branch --show-current)`
6. Create PR: `gh pr create --draft --title "..." --body "..."`
7. Return PR URL to user

## Key Point

**ALWAYS use `--draft` flag.** User will mark as ready for review when appropriate.

---

That's it! Let Claude Code do its normal thorough analysis and PR creation, just make it a draft.
