# Global BYOR configuration

This directory is the portable source for my global BYOR setup. It includes:

- global Python safety rules in `rules/`;
- the opt-in `style` package in `packages/style/`;
- the scripts used by the package checks in `scripts/`; and
- the BYOR configuration in `config.yml`.

The machine-specific repository registry is intentionally not included.

## Install on another machine

From the repository root, after installing BYOR:

```zsh
mkdir -p ~/.config/byor
cp -R byor/. ~/.config/byor/
cp sgconfig.yml ~/sgconfig.yml
byor doctor
```

The `config.yml` file enables the `style` package as the default package for
new BYOR repositories. The package's checks refer to the installed paths under
`~/.config/byor/scripts/`, so keep the directory layout intact.
