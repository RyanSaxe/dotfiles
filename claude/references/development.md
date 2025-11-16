# Development Workflow Guide

This document describes the development process, workflow practices, and collaboration patterns.

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

### Examples

**Good atomic commits:**
- "Add user authentication to login endpoint"
- "Fix null pointer error in payment processing"
- "Refactor database connection handling for better error recovery"
- "Add unit tests for email validation"

**Bad commits (not atomic):**
- "Fix bugs and add features" (multiple things)
- "WIP" (incomplete, breaks project)
- "Update files" (unclear purpose)
- "Part 1 of 3 for feature X" (not self-contained)

### When to Commit

Ask for permission to commit when:
- You've completed a self-contained change
- Tests pass
- The change is complete (not work-in-progress)
- You can describe it in one clear sentence

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

When using TDD, **tests come first** (see [TDD Skill](../skills/code/tdd/SKILL.md)):
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
- [ ] Run linters and type checkers

```bash
# Python example
pytest
ruff check .
lsp-check .  # Check for diagnostics
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

# Commit with descriptive message
git commit -m "Add user validation to registration endpoint

Validates email format and password strength during user registration.
Returns 400 with specific error messages for invalid inputs.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

## Error Handling Balance

### Handle Realistic Cases, Not Every Possible Edge Case

**Good error handling:**
- Validates inputs that users can reasonably provide incorrectly
- Handles expected failure cases (missing files, network errors)
- Fails fast with clear error messages
- Focuses on realistic scenarios

**Bad error handling (code smell):**
- Excessive validation for unrealistic scenarios
- Defensive checks for things that "can't happen"
- Nested validation that duplicates checks
- Paranoid type checking when type system handles it

### Examples

```python
# Good: Balanced error handling
def withdraw(account: Account, amount: float) -> None:
    if amount <= 0:
        raise ValueError("Amount must be positive")
    if amount > account.balance:
        raise ValueError("Insufficient funds")
    account.balance -= amount

# Bad: Excessive validation (code smell)
def withdraw(account: Account, amount: float) -> None:
    if account is None:
        raise ValueError("Account cannot be None")  # Type system handles this
    if not isinstance(amount, (int, float)):
        raise TypeError("Amount must be numeric")  # Type hints handle this
    if amount <= 0:
        raise ValueError("Amount must be positive")
    if amount > account.balance:
        raise ValueError("Insufficient funds")
    if amount > 1000000:
        raise ValueError("Amount too large")  # Unrealistic edge case
    if account.balance < 0:
        raise ValueError("Account corrupted")  # "Can't happen" defensive check
    if not hasattr(account, 'balance'):
        raise AttributeError("Invalid account")  # Already checked above
    account.balance -= amount
```

### Guidelines

**Do validate:**
- User inputs (emails, passwords, amounts)
- External data (API responses, file contents)
- Business rules (balance checks, age requirements)

**Don't validate:**
- Things your type system guarantees
- "Impossible" states (unless debugging)
- Every conceivable edge case (focus on realistic ones)
- Same thing multiple times

**Remember:** A billion validation checks is itself a code smell. Good code has focused, meaningful error handling.

## Git Workflow

### Commit Messages

**Format:**
```
<type>: <short summary>

<optional body explaining why, not what>

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

**Good commit messages:**
- "feat: Add password reset functionality"
- "fix: Handle null values in user profile display"
- "refactor: Extract database connection logic into separate module"
- "test: Add integration tests for payment processing"

**Bad commit messages:**
- "Update code"
- "Fix bug"
- "Changes"
- "WIP"

### Branch Workflow

**Create feature branches:**
```bash
# Create and switch to feature branch
git checkout -b feature/user-authentication

# Or for bug fixes
git checkout -b fix/null-pointer-error
```

**Keep branches focused:**
- One feature or fix per branch
- Branch from main/master
- Keep branches short-lived (days, not weeks)

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

### 4. Fix and Verify

- Write test that reproduces bug (TDD approach)
- Implement fix
- Verify test passes
- Run full test suite
- Commit with clear message explaining the fix

## Refactoring Workflow

See [Clean Code Skill](../skills/code/clean/SKILL.md) for detailed refactoring patterns and processes.

**Refactoring checklist:**
- [ ] Tests pass before refactoring
- [ ] Make small, incremental changes
- [ ] Run tests after each change
- [ ] Don't mix refactoring with feature work
- [ ] Commit refactoring separately from features

## LSP Diagnostics

Use `lsp-check` to verify code health before committing:

```bash
# Check for errors
lsp-check .

# Detailed output with specific severity
lsp-check . --detailed --min-severity WARN

# See [Diagnostics Skill](../skills/code/diagnostics/SKILL.md) for full guide
```

## Related Guides

- [Style Guide](style.md) - Code quality standards
- [Testing Guide](testing.md) - Testing practices
- [TDD Skill](../skills/code/tdd/SKILL.md) - Test-driven development
- [Clean Code Skill](../skills/code/clean/SKILL.md) - Refactoring patterns
- [Diagnostics Skill](../skills/code/diagnostics/SKILL.md) - Error checking
