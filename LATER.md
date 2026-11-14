# What the setup doesn't do yet

Each of these is set up by hand, or not at all yet.

- **Rex and Claude Code on a Mac.** Rex Beta.app comes from Superlogical's
  download and Claude Code from its own installer, and each updates itself.
  A switch writes the settings of both. On the Linux box, the home switch
  installs them, Rex's server from Rex's flake and Claude Code from nixpkgs.
- **Tailscale and Google Chrome on a Mac.** Both are installed by hand.
  Tailscale gives the pair hub its address, and a Mac switch already starts
  it at login. mermaid-cli needs Google Chrome to draw its diagrams. Either
  could become a cask in `modules/darwin/homebrew.nix`.
- **Chrome in light mode.** Chrome builds its theme from the extension in
  `~/.config/theme/chrome` only when it starts, so after `theme light` it
  keeps its dark colors until it restarts. Its `BrowserThemeColor` policy
  would let Chrome follow macOS's mode itself, but a policy set with
  `defaults write` is only recommended, and a mandatory one needs a
  configuration profile. Neither has been tried with Chrome on this Mac.
- **The work Mac.** It's on hold. It has no host file, and the `work` role
  turns nothing on.
