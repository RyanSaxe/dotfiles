# Output Contracts

**When to read this:** when filling in the `## Output Contract` section of a new `SKILL.md` and choosing what shape the skill's outcome should take.

A skill's *outcome* is the thing that persists after the conversation ends. The Output Contract makes that outcome verifiable — without it, "did the skill work?" becomes a matter of opinion. Pick a shape from this catalog or extend it with a new one when nothing fits.

Every contract has three parts:

- **Outcome:** one sentence — what exists or changes after the skill runs.
- **Shape / schema:** how the outcome is structured (file format, commit message format, request payload, etc.).
- **Verification:** a concrete check — a command, a test, a visible field — that confirms success.

## File artifacts

### YAML / JSON data file

- **When to use:** structured outputs meant for downstream tools to consume (audit findings, review entries, generated config).
- **Naming / scope:** stable filename or stable directory + content-derived filename. Never overwrite by accident; use timestamps or content hashes when uniqueness matters.
- **Mandatory invariants:** the file parses; required top-level keys are present; values match documented types.
- **Verification recipe:** `python -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" path/to/file.yaml` (or `jq . path.json > /dev/null`). For richer shapes, ship a JSON Schema and validate with `check-jsonschema --schemafile schema.json path.json`.

### Self-contained HTML report

- **When to use:** human-consumed deliverables (review summary, audit report, longform explainer).
- **Naming / scope:** single `.html` file, or a small folder if the report wants its own CSS / JS / data alongside. All internal paths are relative; CDN-hosted libraries are fine (KaTeX, highlight.js, Chart.js, Lucide — see `design-system/preferences.md` § Recommended libraries).
- **Mandatory invariants:** the file (or folder) zips and unzips on another machine and still opens by double-clicking `index.html`. Renders identically across modern browsers.
- **Verification recipe:** `open report.html` (or `open <folder>/index.html`); confirm renders correctly. Then `zip -r /tmp/report.zip <folder>/`, unzip into `/tmp/test/`, open the unzipped entry point, confirm it still renders.

### Self-contained HTML app

- **When to use:** interactive viewers (filterable dashboards, diff viewers, multi-page presentations, code-review apps).
- **Naming / scope:** single folder containing `index.html` plus relative-path assets (`styles.css`, `script.js`, `data/`, etc.). CDN-hosted libraries via HTTPS are fine.
- **Mandatory invariants:** the folder zips and unzips on another machine; `index.html` opens by double-click; the primary interaction works (filter, navigate, toggle, edit).
- **Verification recipe:** `open <folder>/index.html`, complete one round-trip of the primary interaction. Then `zip -r /tmp/app.zip <folder>/`, unzip, open the unzipped `index.html`, confirm interactivity still works.

### Markdown document

- **When to use:** plain-text deliverables intended for humans (design docs, READMEs, plans).
- **Naming / scope:** single `.md` file with optional frontmatter for machine-readable metadata.
- **Mandatory invariants:** frontmatter parses (if present); required sections exist; relative links resolve.
- **Verification recipe:** parse frontmatter (`python -c "import yaml,re; …"` or any frontmatter linter); `grep -c '^## ' file.md` matches expected section count; `markdown-link-check file.md` if links are critical.

### Generated codebase patch

- **When to use:** suggested code edits delivered as a diff rather than applied directly.
- **Naming / scope:** unified diff (`*.patch`), optionally accompanied by a tiny apply script. Patch is rooted at repo top so `git apply` works without `--directory`.
- **Mandatory invariants:** patch applies cleanly to the documented base commit; tests still pass after applying.
- **Verification recipe:** `git apply --check path.patch` from the documented base, then apply and run the project's test suite.

## Non-file outcomes

### Git commit

- **When to use:** atomic-change skills (refactor a function, rename a symbol, bump a dependency).
- **Shape:** commit message in the project's documented format; diff scoped to one logical change; pre-commit hooks pass.
- **Mandatory invariants:** single commit; no unrelated files in the diff; hooks not skipped (`--no-verify` is a contract violation).
- **Verification recipe:** `git log -1 --format=%B` matches the format spec; `git diff --stat HEAD~1` shows only files within the documented scope; CI pre-push hooks pass.

### In-place refactor

- **When to use:** skills that rewrite code across multiple files without producing a separate artifact (clean-up passes, large-scale renames).
- **Shape:** the diff itself is the outcome. Document which files / symbols may change and which behavioral invariants must hold.
- **Mandatory invariants:** documented behavioral tests still pass; diff stays inside the declared scope.
- **Verification recipe:** project test suite passes; `git diff --name-only HEAD` is a subset of the declared scope; if the refactor is safety-critical, add a snapshot/golden-file check before and after.

### External side effect

- **When to use:** skills that post to an API, send a Slack message, open a PR, etc.
- **Shape:** the request payload (documented in the contract) and the response field that confirms acceptance (status code + canonical id, e.g. PR number).
- **Mandatory invariants:** request matches the documented payload; response acknowledged; no retries silently masking failure.
- **Verification recipe:** capture the response and assert on the success field (e.g. `gh pr view <number>` returns the new PR; Slack API returns `ok: true`). Follow up with a read to confirm the side effect actually landed.

## Choosing a shape

If multiple shapes plausibly fit, prefer the one with the cheapest verification — a parseable file beats a side effect, an atomic commit beats a sprawling refactor. Cheap verification means the skill is *trustworthy at a glance*, which means people actually use it.

If nothing fits, extend the catalog: add a new section in this file with the same three-part structure, then point your `SKILL.md`'s `## Output Contract` at it.
