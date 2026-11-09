# Global BYOR configuration

This directory is the portable source for my global BYOR setup. It includes:

- global Python safety rules in `rules/`;
- the opt-in `style` package in `packages/style/`;
- the scripts used by the package checks in `scripts/`; and
- the BYOR configuration in `config.yml`.

The machine-specific repository registry is intentionally not included.

## Install on another machine

Nothing manual: the extras tier deploys this directory
(`./install.sh` → tiers/extras.yaml). `~/.config/byor` becomes a real
directory holding the machine-specific `repos.yml`, with `config.yml`,
`rules/`, `scripts/`, and `packages/` symlinked back into the repo — so
an edit on any machine reaches the others on the next pull, and a rule
written with `byor add` lands in the repo the moment it is saved.
`~/sgconfig.yml` links here too (ast-grep resolves its `ruleDirs`
relative to the file's location). Run `byor doctor` afterwards.

The `config.yml` file enables the `style` package as the default package for
new BYOR repositories. The package's checks refer to the installed paths under
`~/.config/byor/scripts/`, so keep the directory layout intact.
