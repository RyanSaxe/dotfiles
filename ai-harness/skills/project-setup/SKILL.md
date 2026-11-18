---
name: project-setup
description: Use when the user starts a new repository or project, or asks to bring an existing one in line with their setup, such as moving it off Prettier, ESLint or markdownlint. Sets up uv or npm, prek hooks, one CI workflow, the README and AGENTS.md, and for an existing repository lists the gaps first and fixes the ones the user approves, in one pull request.
---

# Project setup

This skill sets up a repository the way the user works. For a new project,
ask the questions below, write the files, run the checks and open a pull
request. For an existing project, list where it differs from the rules
below, and change what the user approves in one pull request.

## Ask first

Ask these in one message, and skip any that the request or the repository
already answers:

1. Is the repository public or private, and which license does it use?
2. What is it: a Python package or app, a web site, a Node CLI, notebooks,
   or something else?
3. Does it ship to other people's machines? If it does, which operating
   systems and which Python or Node versions does CI test, and does a merge
   release it or does a person?
4. Does work land on main, or on develop, with release pull requests into
   main?
5. What may agents do here without asking, such as merge pull requests,
   approve workflow runs or release?

## Templates

`templates/` holds the files to start from. Each is named without its
leading dot, so that prek and the formatters don't read it here.

| Template                 | Copy to                       | For           |
| ------------------------ | ----------------------------- | ------------- |
| `pre-commit-config.yaml` | `.pre-commit-config.yaml`     | every project |
| `check.yml`              | `.github/workflows/check.yml` | every project |
| `editorconfig`           | `.editorconfig`               | every project |
| `rumdl.toml`             | `.rumdl.toml`                 | every project |
| `pyproject.toml`         | the end of `pyproject.toml`   | Python        |
| `oxfmtrc.json`           | `.oxfmtrc.json`               | web and Node  |
| `oxlintrc.json`          | `.oxlintrc.json`              | web and Node  |

In the first three, blank lines separate the blocks. A block whose comment
starts with a stack, such as `# Python` or `# Web`, is for that stack, and
every other block is for every project. Keep the blocks the project needs
and delete the rest.

Then bring the pinned versions up to date. `prek update` moves each hook to
its newest release. `check.yml` needs the newest prek, the newest major
version of each action and the current Node LTS by hand.
`gh api repos/OWNER/REPO/releases/latest` prints a repository's newest
release.

## Python

Run Python through uv only, with `uv run`, `uv add` and `uv sync`, never
`python` or `pip`. A standalone script is a PEP 723 file whose first line is
`#!/usr/bin/env -S uv run --script`.

For a package or an app:

1. Run `uv init --lib` for a library, or `uv init --package` for an app or
   a command-line tool. Each writes `src/<pkg>/`, `.python-version` and the
   `uv_build` backend. For a tool that ships, set `requires-python` to the
   oldest Python that CI tests.
2. Run `uv add --dev pytest ruff ty`, and add `tests/`. `uv.lock` is
   committed.
3. Append `templates/pyproject.toml` to `pyproject.toml`. It sets ruff's
   line length to 120 and selects every rule, with a comment on each rule it
   ignores. Give each ignore you add a comment of its own.
4. Run `byor init --package style --no-gate`. byor's own skill covers the
   details. The gate stays off because it adds a workflow and hooks beside
   prek's.

The `style` package holds the user's Python rules, so keep them out of the
project's config and AGENTS.md. byor checks each file the agent edits, and
`byor agent-check` checks the whole project, so run it before each commit.

ruff formats, ruff lints with `--fix`, and ty checks types. A project needs
no other Python check. Notebooks are committed without their outputs, which
nbstripout removes, and ruff and ty check them too.

## Web and Node

- Use npm with a committed `package-lock.json`, and set `"type": "module"`
  in `package.json`.
- Start from the framework's own scaffold, such as `npm create vite`, and
  delete its demo files.
- oxfmt formats and oxlint lints, in place of Prettier and ESLint. Install
  them with `npm install --save-dev --save-exact oxfmt oxlint`.
- Code that goes through a build step is TypeScript with `"strict": true`,
  and the template's `tsc` hook checks its types. A framework with its own
  check, such as `astro check`, runs it from that hook instead.
- `npm test` runs the tests, with `node --test` or the framework's own
  runner, such as Vitest with Vite.
- A framework's file type, such as `.astro`, goes in the `files` pattern of
  each web hook. oxfmt skips the type unless `.oxfmtrc.json` turns it on,
  as `"astro": true` does.

## Every project

- The dotfiles install uv, prek and Node on every computer. A tool that
  only this project needs lives in the project: in the uv `dev` group, in
  npm's `devDependencies` or in a prek hook. A project never gets its own
  Nix flake.
- rumdl formats and lints Markdown, and rewraps every paragraph at 80
  columns. Its fixes change only layout, and it reports the rest. It
  replaces markdownlint by choice, although one person wrote nearly all of
  it.
- Formatter settings live in the project's files, `pyproject.toml`,
  `.oxfmtrc.json` and `.rumdl.toml`, which the hook and the editor both
  read. `.editorconfig` mirrors their line lengths and indents.
- Commit messages follow Conventional Commits, such as
  `feat(cli): print the result as JSON`.
- No dependency bots: no Dependabot or Renovate config.
- Commit no generated files, except output that takes long to make again.
- Plans and session notes go in `agent-notes/`, which the global git ignore
  keeps out of every repository.

## Hooks and CI

- `.pre-commit-config.yaml` is the one list of checks. prek runs it before
  each commit, and CI runs the same `prek run --all-files`.
- The hooks only format and lint, and each formatter fixes the files instead
  of only reporting them. Tests run in CI.
- Every hook and tool has a pinned version: a hook's `rev`, a version in
  `uv.lock` or `package-lock.json`, or a version in `check.yml`.
- Every rule a config turns off, and every exception, has a comment that
  says why.
- One workflow, `check.yml`, runs the checks and the tests, on pushes to
  main and on pull requests. Its `check` job runs prek, and its other jobs
  run the tests. It runs without manual approval.
- A tool that ships to other people's machines runs its tests on every
  operating system it supports, and on the oldest and the newest Python or
  Node it supports, as a matrix in the `test` job.
- A release publishes to PyPI or npm through trusted publishing, with
  `id-token: write` and no token, from a `release.yml` that runs on a push
  to main or by hand, as the user chose, and runs the tests before it
  publishes. The user registers the workflow as a trusted publisher on PyPI
  or npm, so ask them to.
- With a develop branch, develop is the default branch, CI also runs on
  pushes to it, and a release is a pull request from develop into main.

## Docs

- The README sells the project to developers in one screen: a tagline, a
  picture or a video, Get started, How it works with one diagram, links to
  the docs, and the license. A feature gets no section of its own.
  [pair's README](https://github.com/RyanSaxe/pair#readme) follows this
  layout.
- A diagram is a custom SVG with a light and a dark version in a
  `<picture>`, never Mermaid. Add an image only where it helps.
- Leave out qualifiers and filler: no list of platforms when every platform
  works, no status banners, and no features that don't exist yet.
- Longer docs go in `docs/`, in `getting-started/`, `concepts/`, `guides/`,
  `reference/` and `contributing/`, with `docs/README.md` as the index and
  images in `docs/assets/`.
- The README is for using the project, and AGENTS.md is for changing it.
  AGENTS.md has:
  - the setup, the modules, and the project's own rules for the code and the
    tests
  - the exact check commands
  - the branch model, how a release happens, and what agents may do without
    asking
  - that commit messages follow Conventional Commits
  - to ask before adding a dependency
  - to add no backwards-compatibility shims before the first release
- Planned work that hasn't started goes in a committed `BACKLOG.md`, and
  the pull request that does an entry removes it.
- Skills for working on this repository go in `.agents/skills/NAME/SKILL.md`.

## Set up a new project

1. Ask the questions above.
2. Unless the GitHub repository exists, create it with `gh repo create`,
   public or private as the user said. Push a first commit to main, with
   the license if it has one. `gh api licenses/mit --jq .body` prints the
   MIT license, and other license IDs work the same way. With a develop
   branch, push develop at the same commit and make it the default with
   `gh repo edit --default-branch develop`. Build the rest on a branch from
   the default branch.
3. Set up each stack's toolchain and `.gitignore`. Put the license in the
   `license` field of `pyproject.toml` or `package.json`. Commit.
4. Copy the templates, and stage everything with `git add`, since prek
   checks only the files git knows. Run `prek install`, then
   `prek run --all-files` until it passes, then the tests. Commit.
5. Write the README's tagline, Get started and license, and add its
   picture, diagram and docs links once there is something to show. Write
   AGENTS.md. Commit.
6. For a project that ships, write `release.yml` and commit it.
7. Open a pull request into the default branch.

## Bring an existing project in line

1. Read the repository's config files, workflows, README, AGENTS.md and
   docs, and compare them with each rule above.
2. Ask the user what the repository doesn't answer.
3. List the gaps in a table, with the files each one changes and how, and
   ask the user which to fix.
4. Fix the approved gaps on one branch, one commit each, and open one pull
   request.

To move a project off Prettier, ESLint or markdownlint, convert its config,
then delete the old tool's config, its dependency and its CI steps:

- `npx oxfmt --migrate=prettier` writes `.oxfmtrc.json` from the Prettier
  config and `.prettierignore`. oxfmt honors `prettier-ignore` comments, so
  they stay.
- `npx @oxlint/migrate` writes `.oxlintrc.json` from the ESLint config.
- `rumdl import FILE` writes `.rumdl.toml` from a markdownlint config.

Then change each setting the template also has to the template's value, and
keep the rest. Fix what a newly enabled rule finds, or turn the rule off with
a comment saying why. Reformat the whole repository in a commit of its own,
so that the other commits show only what they change.

Renaming a workflow or a job changes the names that branch rulesets require
and that `workflow_run` triggers name, so update those too.
