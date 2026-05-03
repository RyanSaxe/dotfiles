---
description: Create a draft pull request (supports stacked PRs)
---

# Create Pull Request(s)

Analyze the current branch and create either a single PR or multiple stacked PRs based on the commits.

## Instructions

1. **Determine the base branch**:
   - Check upstream tracking: `git rev-parse --abbrev-ref --symbolic-full-name @{u}`
   - If no upstream, check common base: `git merge-base HEAD origin/main origin/master origin/develop 2>/dev/null | head -1`
   - Use `git branch -r --contains $(git merge-base HEAD origin/main)` to find the most likely base
   - Store as `BASE_BRANCH` variable for use throughout

2. **Analyze the branch commits**:
   - Run `git log --oneline $BASE_BRANCH..HEAD` to see all commits
   - Run `git diff $BASE_BRANCH...HEAD --stat` to see all changed files
   - For each commit, check `git show --stat <commit-hash>` to understand what files it touches

3. **Determine if stacking is beneficial**:
   - Look for commits that touch different subsystems/features
   - Check if commits can be logically grouped (e.g., "refactor X", "add feature Y", "fix bug Z")
   - Consider file dependencies - commits touching the same files usually belong together
   - If there are 3+ distinct logical changes, suggest stacking

4. **Ask the user about PR strategy**:
   Present analysis and ask:
   - "I've analyzed your commits and found [X distinct changes]. Would you like to:"
     a) Create a single PR with all changes
     b) Create stacked PRs (one for each logical change)
     c) Let me suggest a custom grouping

5. **For single PR**:
   - Follow the standard PR creation process
   - Push current branch and create draft PR: `gh pr create --draft --base $BASE_BRANCH`

6. **For stacked PRs**:

   a) **Plan the stack**:
      - Group commits by logical change
      - Determine dependencies (which changes depend on others)
      - Create a stacking order (independent changes first, dependent ones on top)

   b) **Create branches**:
      - For each logical group, create a branch from base: `git checkout -b <feature-name>-pr $BASE_BRANCH`
      - Use descriptive names like `refactor-auth-pr`, `add-logging-pr`, etc.

   c) **Apply commits**:
      - For independent PRs: cherry-pick relevant commits from the original branch
      - For dependent PRs:
        - Create from the previous PR's branch
        - Cherry-pick only the commits for this specific change
      - Use `git cherry-pick <commit-hash>` for each relevant commit

   d) **Verify correctness**:
      - After creating all branches, verify the combined changes match the original:

        ```bash
        # Create a test branch merging all PR branches
        git checkout -b verify-stack $BASE_BRANCH
        for branch in <all-pr-branches>; do
          git merge --no-ff $branch
        done
        # Compare with original branch
        git diff HEAD..<original-branch>
        # Should show no differences
        ```

   e) **Create the PRs with proper linking**:
      - Push each branch: `git push -u origin <branch-name>`
      - Create PRs in order:

        **For independent PRs**:

        ```bash
        gh pr create --draft --base $BASE_BRANCH --title "Title" --body "$(cat <<'EOF'
        ## Summary
        [Description of changes]

        ## Stack Information
        This is part 1 of N in a stack of PRs.

        **Full stack:**
        - [ ] #1 ← You are here
        - [ ] #2 (depends on #1)
        - [ ] #3 (depends on #2)

        **Merge order:** This PR can be merged independently.

        ## Test Plan
        [Testing approach]
        EOF
        )"
        ```

        **For dependent PRs**:

        ```bash
        gh pr create --draft --base <previous-pr-branch> --title "Title" --body "$(cat <<'EOF'
        ## Summary
        [Description of changes]

        ## Stack Information
        This is part 2 of N in a stack of PRs.

        **Dependencies:**
        - Depends on: #<previous-pr-number>
        - Base branch will be updated to $BASE_BRANCH after #<previous-pr-number> is merged

        **Full stack:**
        - [x] #1 (merged or ready)
        - [ ] #2 ← You are here
        - [ ] #3 (depends on this PR)

        **Merge order:** Merge #<previous-pr-number> first, then this PR.

        ## Test Plan
        [Testing approach]
        EOF
        )"
        ```

7. **Provide summary**:
   - List all created PRs with their URLs
   - Show the dependency graph visually:

     ```text
     Stack created successfully:

     BASE_BRANCH ($BASE_BRANCH)
        ├── PR #123: Database refactor (independent)
        ├── PR #124: Authentication feature (independent)
        └── PR #125: Logging system
                └── PR #126: Logging tests (depends on #125)

     Merge order: #123, #124, #125, #126 (or #123/#124 in any order, then #125, then #126)
     ```

   - Confirm that merging all PRs will achieve the same final state

## Example Workflow

If the branch has commits:

- `abc123 Add user authentication`
- `def456 Fix authentication tests`
- `ghi789 Refactor database connection`
- `jkl012 Add logging system`
- `mno345 Update logging tests`

Suggest grouping as:

1. **PR 1**: Database refactor (independent, base: $BASE_BRANCH)
   - `ghi789 Refactor database connection`
2. **PR 2**: Authentication feature (independent, base: $BASE_BRANCH)
   - `abc123 Add user authentication`
   - `def456 Fix authentication tests`
3. **PR 3**: Logging system (may depend on refactor, base: refactor-pr branch)
   - `jkl012 Add logging system`
   - `mno345 Update logging tests`

## Important Notes

- Always create PRs as **drafts** using `--draft` flag
- Always ensure the final merged state equals the original branch
- Preserve commit messages and authorship
- Handle merge conflicts appropriately
- If commits are too intertwined to separate cleanly, recommend a single PR
- For truly independent changes, create parallel PRs all based on $BASE_BRANCH
- For dependent changes, create a chain where each PR is based on the previous
- Include clear dependency information in PR bodies with links to related PRs
- Use checkboxes in PR descriptions to track merge progress through the stack
