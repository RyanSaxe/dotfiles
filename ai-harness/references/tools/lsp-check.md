# `lsp-check`

`lsp-check` collects diagnostics from the language servers configured in
Neovim. Use it when editor diagnostics are relevant but unavailable or easier
to inspect as a single report.

Run it against the smallest useful set of files:

```sh
lsp-check src/module tests/test_module.py
lsp-check src/module --detailed --min-severity WARN
lsp-check src/module --detailed --source pyright
```

Avoid `lsp-check .` unless the entire repository is intentionally in scope.
The tool respects `.gitignore`, refuses multiple Git roots, and caps the number
of files by default. See `lsp-check --help` for timing, filtering, and JSON
output options.

The canonical executable is `ai-harness/tools/lsp-check.zsh`. Installation links
that file into `~/.local/bin`; the harness homes do not own copies.
