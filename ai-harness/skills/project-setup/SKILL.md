---
name: project-setup
description: Use when the user starts a new repository or asks to clean up or bring an existing one in line with their setup across Python, Web/TypeScript/React, Markdown, Rust, Go, Lua, Notebooks, Shell and Nix, such as moving off Prettier, ESLint, Black, Flake8, mypy or markdownlint. Sets up toolchains, prek hooks, one CI workflow, BYOR packages, README and AGENTS.md, and runs a zero-ratchet cleanup audit and single PR for existing repositories.
---

# Project setup

This skill sets up a repository the way the user works across nine stacks:
Python, Web/TypeScript/React, Markdown, Rust, Go, Lua, Notebooks, Shell and
Nix. It has two modes:

- **New project:** ask the questions below, write the files, run the checks and
  open a pull request.
- **Cleanup mode (zero-ratchet):** audit an existing repository with
  `scripts/audit.py`, review the gap table with the user, and bring the
  repository into line in one pull request with ordered atomic commits.

## Ask first

Ask these in one message, and skip any that the request or the repository
already answers:

1. Is the repository public or private, and which license does it use?
2. What is it: a Python package or app, a web site, a Node CLI, a Rust crate, a
   Go module, a Lua project, notebooks, shell scripts, a Nix flake, or a mix?
3. Does it ship to other people's machines? If it does, which operating systems
   and language versions does CI test, and does a merge release it or does a
   person?
4. Does work land on main, or on develop, with release pull requests into main?
5. What may agents do here without asking, such as merge pull requests, approve
   workflow runs or release?

## Templates

`templates/` holds 11 starter files named without their leading dots so prek and
formatters do not read them here. Every disabled rule or non-default choice
carries a comment explaining why.

| Template                 | Copy to                       | For           |
| ------------------------ | ----------------------------- | ------------- |
| `pre-commit-config.yaml` | `.pre-commit-config.yaml`     | every project |
| `check.yml`              | `.github/workflows/check.yml` | every project |
| `editorconfig`           | `.editorconfig`               | every project |
| `rumdl.toml`             | `.rumdl.toml`                 | every project |
| `pyproject.toml`         | the end of `pyproject.toml`   | Python        |
| `oxfmtrc.json`           | `.oxfmtrc.json`               | web and Node  |
| `oxlintrc.json`          | `.oxlintrc.json`              | web and Node  |
| `cargo-lints.toml`       | the end of `Cargo.toml`       | Rust          |
| `golangci.yml`           | `.golangci.yml`               | Go            |
| `stylua.toml`            | `stylua.toml`                 | Lua           |
| `emmyrc.json`            | `.emmyrc.json`                | Lua           |

In `pre-commit-config.yaml`, `check.yml` and `editorconfig`, blank lines
separate the blocks. A block whose comment starts with a stack, such as
`# Python` or `# Rust`, is for that stack, and every other block is for every
project. Keep the blocks the project needs and delete the rest.

Bring pinned versions up to date after copying. `prek update` moves each hook to
its newest release. Update `check.yml` pins (prek, GitHub Actions, Node LTS,
`golangci-lint`, `stylua`, `emmylua_check`) and the `ast-grep-cli` version by
hand. `gh api repos/OWNER/REPO/releases/latest` prints a repository's newest
release.

## Layer ownership

Keep each concern in one layer so hooks, CI and agent feedback never duplicate
or fight each other:

- **prek and `check.yml`** own hard correctness, formatting, type checks,
  lockfile freshness and the inline 1,000-line hard cap (`max-file-lines`) on
  source files. When `.byor/rules/project/` exists, keep the pinned `ast-grep`
  hook in `.pre-commit-config.yaml` so CI enforces repo-owned rules without
  requiring BYOR on runners.
- **BYOR** owns the agent edit loop (`--no-gate`, never `gate: true`). Wire
  every project with the `craft` package plus its stack package when one exists
  (`python` or `web`). The old `style` package is retired; replace it with
  `craft` plus the stack package.

## Cross-language parity standard

Every stack enforces the same eight hygiene dimensions through its native
tooling so quality does not drop when switching languages:

- **Complexity:** small, flat functions calibrated per language's metric.
- **Nesting depth:** capped at 4 levels (`PLR1702`, `max-depth`, `nestif`,
  Clippy's quadratic cognitive penalty).
- **Parameter cap:** short positional signatures (`PLR0917 <= 2` in Python,
  `max-params <= 3` in JS/TS, `revive` `argument-limit: 5` in Go).
- **Strict types:** `ty`, `oxlint-tsgolint` (`"strict": true`), `rustc`,
  `go`/`staticcheck`, strict `emmylua_check`.
- **Control-flow hygiene:** no shadowed bindings, redundant branches, implicit
  coercion, or swallowed errors.
- **Dead code:** unused bindings, unreachable code, and unused Nix inputs
  (`deadnix --fail`).
- **Formatting:** one canonical formatter per stack, auto-fixing in hooks.
- **Lockfiles:** committed and verified in hooks (`uv.lock`,
  `package-lock.json`, `Cargo.lock`, `go.sum`, `flake.lock`).

### Complexity equivalence across languages

Raw thresholds differ because each analyzer counts different constructs:

- **Python (`C901 <= 8`, `PLR0912 <= 10`, `PLR1702 <= 4`):** 6 is the
  human-ideal ceiling and >10 is poor; 8 is the agent-assisted benchmark.
  Ruff's `C901` ignores boolean `and`/`or`.
- **JS/TS (`complexity <= 10`, `max-depth <= 4`, `max-nested-callbacks <= 3`):**
  `oxlint` counts `&&`, `||`, `??` and `?:`, so 10 matches Python's 8.
- **Go (`cyclop <= 10`, `gocognit <= 15`, `nestif <= 4`):** accounts for
  idiomatic `if err != nil` branches alongside cognitive complexity.
- **Rust (`clippy::cognitive_complexity <= 15` via `clippy.toml`):** quadratic
  nesting penalty makes 15 equivalent to ~8-10 cyclomatic complexity.
- **Lua (`luacheck --no-config --only 561 --max-cyclomatic-complexity 10`):**
  runs in ~0.23s for complexity alone and pairs with strict `emmylua_check`;
  skip `selene` and full `luacheck` static analysis.

## Python

Run Python through uv only, with `uv run`, `uv add` and `uv sync`, never
`python` or `pip`. A standalone script is a PEP 723 file whose first line is
`#!/usr/bin/env -S uv run --script`.

For a package or an app:

1. Run `uv init --lib` for a library, or `uv init --package` for an app or a
   command-line tool. Each writes `src/<pkg>/`, `.python-version` and the
   `uv_build` backend. For a tool that ships, set `requires-python` to the
   oldest Python that CI tests.
2. Run `uv add --dev pytest ruff ty`, and add `tests/`. Commit `uv.lock`;
   `uv-lock-check` keeps it in sync with `pyproject.toml`.
3. Append `templates/pyproject.toml` to `pyproject.toml`. It sets Ruff's line
   length to 120, enables `select = ["ALL"]`, sets `C901 <= 8`, `PLR0912 <= 10`,
   `PLR1702 <= 4`, caps positional parameters at two (`PLR0917` via
   `max-positional-args = 2`), bans relative imports, and bans `typing.cast`,
   `typing_extensions.cast`, `unittest`, `unittest.mock` and dynamic `importlib`
   APIs via `TID251`. Give each ignore you add a comment of its own.
4. Run `byor init --packages craft python --no-gate`.

Ruff formats and lints with `--fix`, and `ty` checks types. A project needs no
other Python linter or type checker. Notebooks are committed without their
outputs, which `nbstripout` removes, and Ruff and `ty` check them too.

## Web and Node

- Use npm with a committed `package-lock.json`, and set `"type": "module"` in
  `package.json`.
- Start from the framework's own scaffold, such as `npm create vite`, and delete
  its demo files.
- `oxfmt` formats and `oxlint` lints, replacing Prettier and ESLint. Install
  them with `npm install --save-dev --save-exact oxfmt oxlint`. `.oxfmtrc.json`
  keeps `oxfmt` off Markdown, which `rumdl` formats.
- `.oxlintrc.json` enables `typescript`, `unicorn`, `oxc` and `import` (add
  `react` and `jsx-a11y` for React repos; drop `typescript` and its rules for
  pure JS), sets `correctness`, `suspicious` and `perf` to `"error"`, and
  enforces `complexity` (10), `max-depth` (4), `max-nested-callbacks` (3),
  `max-params` (3), `curly`, `import/no-cycle`, `eqeqeq`, `no-var`,
  `prefer-const`, `no-param-reassign`, `no-nested-ternary`, `no-else-return`,
  `no-lonely-if`, `unicorn/no-negated-condition`, no `as` assertions, no `any`,
  no `!` non-null assertions, exhaustive `switch` checks,
  `typescript/no-misused-promises` and
  `typescript/explicit-function-return-type`. CLI entrypoints may opt out of
  `no-console`.
- For TypeScript projects (`"strict": true`), install `oxlint-tsgolint` with
  `--save-dev --save-exact` and add `--type-aware --type-check` to the `oxlint`
  hook so `oxlint` checks types in place of a separate `tsc` hook. A framework
  with its own checker, such as `astro check`, keeps a hook for that instead.
- CLIs or test harnesses that intentionally await inside a loop may turn off
  `no-await-in-loop` in `.oxlintrc.json` with a comment explaining why.
- For static HTML sites or templates that need HTML lint rules beyond `oxfmt`,
  install `markuplint` and keep the `# Static HTML` hook block.
- `npm test` runs the tests, with `node --test` or the framework's own runner,
  such as Vitest with Vite.
- A framework's file type, such as `.astro`, goes in the `files` pattern of each
  web hook. `oxfmt` skips the type unless `.oxfmtrc.json` turns it on, as
  `"astro": true` does.
- Run `byor init --packages craft web --no-gate`.

## Rust

- `cargo fmt --all` formats, `cargo clippy --all-targets -- -D warnings` lints,
  and `cargo metadata --locked --format-version 1` verifies `Cargo.lock`.
- Append `templates/cargo-lints.toml` to `Cargo.toml` (or place it under
  `[workspace.lints.*]` in a workspace) to forbid `unsafe_code`, warn on
  `clippy::pedantic` and `cognitive_complexity`, deny `unwrap_used` and warn on
  `expect_used`. Add `cognitive-complexity-threshold = 15` in `clippy.toml`.
- Run `cargo test --locked` in CI. For shipped crates, consider adding
  `cargo machete` or `cargo deny check` to the CI `test` job.
- Run `byor init --package craft --no-gate`.

## Go

- Copy `templates/golangci.yml` to `.golangci.yml`. It uses `golangci-lint` v2
  with `gofumpt` and `goimports` under `formatters`, `standard` plus `cyclop`
  (10), `gocognit` (15), `nestif` (4), `revive` (`argument-limit: 5`), `gosec`,
  `errcheck`, `errorlint` and `staticcheck` under `linters`, and uncapped issue
  reporting (`max-issues-per-linter: 0`, `max-same-issues: 0`,
  `uniq-by-line: false`).
- prek runs `golangci-lint fmt`, `golangci-lint run` and `go mod tidy -diff`. CI
  installs `golangci-lint` with `install-only: true` so prek runs it once, and
  runs `go test -race ./...`.
- For a tiny single-package helper where `.golangci.yml` is overkill, use
  `gofmt -w` and `go vet ./...` instead.
- Run `byor init --package craft --no-gate`.

## Lua

- Copy `templates/stylua.toml` to `stylua.toml` and `templates/emmyrc.json` to
  `.emmyrc.json` (switching `runtime.version` to `"Lua5.4"` for standalone Lua,
  or adding host globals like `"vim"` for Neovim). `.emmyrc.json` promotes the
  local type, nil-check, control-flow and dead-code diagnostics to `"error"`.
- prek runs `stylua`, `emmylua_check .` and
  `luacheck --no-config --only 561 --max-cyclomatic-complexity 10` (complexity
  only; skip `selene` and full `luacheck` static analysis). Add `busted` or
  `nvim --clean --headless` test commands to the CI `test` job when tests exist.
- Run `byor init --package craft --no-gate`.

## Shell

- `shfmt --write --indent 2` formats POSIX sh, bash and dash scripts (excluding
  `*.zsh`, since `shfmt` has no zsh dialect).
- `shellcheck` lints every sh, bash and dash script; `zsh -n` checks syntax on
  `*.zsh` files and scripts with a `zsh` shebang.
- Give every executable or checked shell script an explicit shebang so tools
  know its dialect without guessing.

## Nix

- `nixfmt` formats every `.nix` file.
- `deadnix --fail` catches unused bindings and arguments.
- `statix check` catches Nix anti-patterns and repeated attribute keys.
- Keep `flake.lock` committed and run `nix build` / `nix eval` checks in CI.

## Every project

- The dotfiles install uv, prek, Node, Rust, Go and Lua formatters on every
  computer. A tool that only one project needs lives in that project: in the uv
  `dev` group, in npm's `devDependencies` or in a prek hook. A project never
  gets its own Nix flake.
- `rumdl` formats and lints Markdown, and rewraps every paragraph at 80 columns.
  Its fixes change only layout, and it reports the rest. It replaces
  `markdownlint`.
- Formatter settings live in the project's own files (`pyproject.toml`,
  `.oxfmtrc.json`, `.rumdl.toml`, `.golangci.yml`, `stylua.toml`), which both
  hooks and editors read. `.editorconfig` mirrors their line lengths and
  indents.
- Commit messages follow Conventional Commits, such as
  `feat(cli): print the result as JSON`.
- No dependency bots: no Dependabot or Renovate config.
- Commit no generated files, except output that takes long to make again.
- Plans and session notes go in `agent-notes/`, which the global git ignore
  keeps out of every repository.

## Hooks and CI

- `.pre-commit-config.yaml` is the one list of checks. prek runs it before each
  commit, and CI runs the same `prek run --all-files`.
- Hooks only format and lint, and each formatter fixes files instead of only
  reporting them. Tests run in CI.
- Every hook and tool has a pinned version: a hook's `rev`, a version in
  `uv.lock`, `package-lock.json` or `Cargo.lock`, or a version in `check.yml`.
- Every rule a config turns off, and every exception, has a comment that says
  why.
- One workflow, `check.yml`, runs checks and tests on pushes to main and on pull
  requests. Its `check` job runs prek, and its `test` job runs tests. It runs
  without manual approval.
- A tool that ships to other people's machines runs its tests on every operating
  system it supports, and on the oldest and newest language versions it
  supports, as a matrix in the `test` job.
- A release publishes to PyPI, npm or crates.io through trusted publishing, with
  `id-token: write` and no token, from a `release.yml` that runs on a push to
  main or by hand, as the user chose, and runs tests before publishing. Ask the
  user to register the trusted publisher.
- With a develop branch, develop is the default branch, CI also runs on pushes
  to it, and a release is a pull request from develop into main.

## Docs

Follow the `repo-docs` and `write-well` skills when writing or revising docs:

- **README as intro and hook:** sell the project in about one screen, with a
  sharp upfront pitch that piques interest, a high-level architecture diagram
  or visual, a fast quick start and links into `docs/` instead of duplicating
  manuals. Keep a root `LICENSE` file rather than a redundant `## License` stub
  in the README. Keep prose concise: never a dry stub and never a bloated wall
  of text. A feature gets no section of its own.
  [pair's README](https://github.com/RyanSaxe/pair#readme) follows this layout.
- **Diagrams as light/dark `<picture>` SVGs:** commit `-light.svg` and
  `-dark.svg` pairs inside `<picture>` (`<source media="(prefers-color-scheme: dark)" srcset="..."><img ...>`)
  instead of fenced `mermaid` blocks, which GitHub's mobile apps render as raw
  code. Add a diagram only where it helps, use system typography with
  `role="img"` and `aria-label`, and visually verify rendered PNGs in both light
  and dark modes so no text clips or overlaps.
- **Leave out qualifiers and filler:** no list of platforms when every platform
  works, no status banners, and no features that do not exist yet.
- **Diátaxis in `docs/`:** for multi-doc repositories, separate
  `docs/getting-started/` (crisp first-run tutorials), `docs/guides/` (lean task
  recipes without background theory), `docs/concepts/` (focused prose discussion
  without filler), `docs/reference/` (terse lookup tables) and
  `docs/contributing/` when needed, with `docs/README.md` as the index and
  images in `assets/` or `docs/assets/`. Skip unused directories rather than
  creating empty stubs.
- **README vs `AGENTS.md`:** the README is for using the project, and
  `AGENTS.md` is for changing it. `AGENTS.md` has:
  - the setup, the modules, and the project's own rules for the code and the
    tests
  - the exact check commands
  - the branch model, how a release happens, and what agents may do without
    asking
  - that commit messages follow Conventional Commits
  - to ask before adding a dependency
  - to add no backwards-compatibility shims before the first release

  Do not put prose rules in `AGENTS.md` that linters or hooks already enforce,
  and do not add a rule-to-enforcer table.
- Planned work that has not started goes in a committed `BACKLOG.md`, and the
  pull request that does an entry removes it.
- Skills for working on this repository go in `.agents/skills/NAME/SKILL.md`.

## Mode 1: New project

1. Ask the questions in "Ask first".
2. Unless the GitHub repository exists, create it with `gh repo create`, public
   or private as the user said. Push a first commit to main, with the license if
   it has one (`gh api licenses/mit --jq .body` prints MIT). With a develop
   branch, push develop at the same commit and make it the default with
   `gh repo edit --default-branch develop`. Build the rest on a branch from the
   default branch.
3. Set up each stack's toolchain, `.gitignore` and BYOR (`--no-gate` with
   `craft` plus stack packages). Put the license in `pyproject.toml`,
   `package.json` or `Cargo.toml`. Commit.
4. Copy the templates for the detected stacks, stage everything with `git add`
   (since prek checks tracked files), run `prek install`, then
   `prek run --all-files` until it passes, then run the tests. Commit.
5. Write the README's opening pitch and quick start (add pictures, diagrams and
   docs links once there is something to show) and write `AGENTS.md`. Commit.
6. For a project that ships, write `release.yml` and commit it.
7. Open a pull request into the default branch.

## Mode 2: Cleanup mode (zero-ratchet)

Use this mode for any existing repository.

1. Run the read-only audit script first:

   ```sh
   uv run --script <skill-dir>/scripts/audit.py /path/to/repo
   ```

   Pass `--json` when you want structured data. Read the repository's workflows,
   config files, `README.md` and `AGENTS.md` alongside the audit output.

2. Present the gap table to the user in one message, showing the files each
   change touches and asking about anything ambiguous, including any intentional
   misfit-rule overrides (such as `no-await-in-loop` in a CLI or keeping an
   extra workflow).

3. Enforce zero ratcheting: never add per-file legacy overrides, baselines or
   ignore lists to defer violations. Fix every finding cleanly. If one oversized
   or risky rule would force a large refactor outside the cleanup scope, keep
   that rule out of the cleanup pull request and record a dedicated follow-up
   item in `BACKLOG.md`.

4. Land all approved changes on one branch in one pull request, using four
   ordered atomic commits:
   1. **Migrate tooling and wire BYOR:** convert and delete legacy tooling
      configs, dependencies and hooks (Prettier, ESLint, Husky, lint-staged,
      Biome, markdownlint, Black, isort, Flake8, pylint, mypy, pyright,
      `.luacheckrc` / `selene`, Python `pre-commit`, Dependabot/Renovate).
      Install the canonical tools and wire BYOR with `--no-gate` and `craft`
      plus the stack packages.
   2. **Pure reformat:** run only the formatters (`prek run` formatter hooks or
      the formatters directly) with no logic edits. When the repository
      preserves commit history, record this commit's SHA in
      `.git-blame-ignore-revs`.
   3. **Fix findings:** fix every remaining lint, type and 1,000-line file-cap
      finding cleanly so `prek run --all-files`, `byor agent-check` and all
      tests pass.
   4. **Consolidate CI and docs:** consolidate `.github/workflows/check.yml` and
      `.pre-commit-config.yaml`, update `AGENTS.md` (pruning prose rules tools
      now enforce, with no rule-to-enforcer table), fill approved README/docs
      gaps, and update branch ruleset required check names and any
      `workflow_run` triggers when workflow or job names change.

### Migrating off Prettier, ESLint and markdownlint

Convert the existing config before deleting the old tool's config, dependency
and CI steps:

- `npx oxfmt --migrate=prettier` writes `.oxfmtrc.json` from the Prettier config
  and `.prettierignore`. `oxfmt` honors `prettier-ignore` comments, so they
  stay.
- `npx @oxlint/migrate` writes `.oxlintrc.json` from the ESLint config.
- `rumdl import FILE` writes `.rumdl.toml` from a markdownlint config.

Then update each setting the template also sets to the template's value, merge
the template's `ignorePatterns` with the converted ones instead of dropping
them, and remove any per-file legacy suppression blocks rather than ratcheting
them forward.
