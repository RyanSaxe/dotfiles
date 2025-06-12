# 💤 LazyVim Anywhere I Go

This repo is setup to ensure I can have the exact same setup on any server or computer. It contains my neovim configuration and automation to ensure I can install all the things I normally depend on with a script so I don't have to worry about it. Eventually this may grow beyond just neovim and also contain a variety of other utilities and tools as well.

## Installation Instructions

```bash
git clone https://github.com/RyanSaxe/lazy.nvim ~/.config/nvim
cd ~/.config/nvim
./scripts/install.sh
nvim
```

Note that this may not perfectly get you there. For example, to get sonarlint working, you will need to do the following extra steps:

1. Open Neovim and run `:MasonInstall sonarlint-language-server`
2. Ensure your system points to the right version of Java. The script above will install openjdk@17, but you may need to set the `JAVA_HOME` environment variable to point to it for sonarlint to work properly.
