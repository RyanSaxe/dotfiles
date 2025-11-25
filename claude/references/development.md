# Development Workflow Guide

This document describes the development process, workflow practices, and
collaboration patterns.

## Core Workflow Principles

1. **Atomic commits**: One self-contained change per commit
2. **Read before writing**: Understand existing code before changing it
3. **Test your changes**: Features aren't complete until tested and verified
4. **Simple solutions first**: Start with the simplest approach that works
5. **Iterate and refine**: Perfect is the enemy of good

## Atomic Commits

### What is an Atomic Commit?

An atomic commit is a single, self-contained change that:

- Does one thing (and does it completely)
- Can be applied or reverted independently
- Doesn't break the project
- Has a clear, focused purpose

### When to Commit

Ask for permission to commit when:

- You've completed a self-contained change
- Tests pass
- The change is complete (not work-in-progress)

## Development Cycle

### 1. Understand Before Changing

**Always read existing code first:**

```bash
# Explore codebase structure
fd -e py . src/  # Find relevant files
rg "function_name" src/  # Search for usage
sg -p 'class $NAME' src/  # Structural search

# Read relevant files to understand current implementation
```

**Questions to ask:**

- How is this currently implemented?
- What patterns does the codebase use?
- Are there similar features to learn from?
- What tests already exist?

### 2. Plan the Approach

Before writing code:

1. **Clarify requirements**:
   - What needs to be built/fixed?
   - **Ask clarifying questions if anything is unclear**
   - Better to ask than assume and implement wrong solution

2. **Identify the simplest solution**: Start simple, refine later

3. **Consider existing patterns**: Match codebase style

4. **Plan testing strategy**: How will you verify it works?
   - For TDD: Write tests first (see step 3a below)
   - For standard flow: Write tests after implementation (see step 4)

### 3. Implement

**Standard implementation:**

Follow these guidelines:

- Follow existing code style and patterns (see [Style Guide](style.md))
- Write minimal comments (self-documenting code preferred)
- Use appropriate abstractions (but avoid over-engineering)
- Handle realistic error cases (see "Error Handling Balance" below)

**3a. Test-Driven Development (TDD) Alternative:**

When using TDD, **tests come first** (see
[TDD Skill](../skills/code/tdd/SKILL.md)):

1. Write failing test that defines behavior
2. Implement minimal code to pass test
3. Refactor while keeping tests green
4. Repeat

### 4. Test (for non-TDD workflow)

**Testing checklist:**

- [ ] Write tests for new functionality
- [ ] Run existing tests to ensure nothing broke
- [ ] Test happy path
- [ ] Test realistic error cases (see "Error Handling Balance" below)
- [ ] Run linters and type checkers according to the project configuration

```bash
# Python example
pytest
ruff check .
```

### 5. Review

Before committing:

```bash
# Review changes
git status
git diff

# Check for:
# - Unintended changes
# - Debug code left in
# - Proper file organization
```

### 6. Commit

```bash
# Stage relevant files
git add path/to/files

# Commit with a short, yet descriptive, message following the below format
git commit -m "Add user validation to registration endpoint

Validates email format and password strength during user registration.
Returns 400 with specific error messages for invalid inputs.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

**REQUIRED Commit Format:**

```
<type>: <short summary>

<optional body explaining why, not what. No more than two lines.>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Types:**

- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Code restructuring without behavior change
- `test`: Adding or updating tests
- `docs`: Documentation changes
- `chore`: Tooling, dependencies, etc.

## Debugging Workflow

### 1. Reproduce the Issue

- Create minimal test case
- Document steps to reproduce
- Verify it's actually a bug (not expected behavior)

### 2. Locate the Problem

```bash
# Search for relevant code
rg "function_name"
sg -p 'class $NAME'

# Check recent changes
git log --oneline -10
git blame path/to/file.py
```

### 3. Understand the Context

- Read surrounding code
- Check related tests
- Review documentation/comments
- Ask questions if needed

### 4. Fix and Verify

- Write test that reproduces bug (TDD approach)
- Implement fix
- Verify test passes
- Run full test suite
- Commit with clear message explaining the fix

## Refactoring Workflow

See [Clean Code Skill](../skills/code/clean/SKILL.md) for detailed refactoring
patterns and processes. Use this skill.

**Refactoring checklist:**

- [ ] Tests pass before refactoring
- [ ] Make small, incremental changes
- [ ] Run tests after each change
- [ ] Don't mix refactoring with feature work
- [ ] Commit refactoring separately from features

## Related Guides

- [Style Guide](style.md) - Code quality standards
- [Testing Guide](testing.md) - Testing practices
- [TDD Skill](../skills/code/tdd/SKILL.md) - Test-driven development
- [Clean Code Skill](../skills/code/clean/SKILL.md) - Refactoring patterns
- [Diagnostics Skill](../skills/code/diagnostics/SKILL.md) - Error checking
