# What the setup doesn't do yet

Each of these is set up by hand, or not at all yet.

- **Rex and Claude Code.** Rex Beta.app comes from Superlogical's download on a
  Mac and Claude Code from its own installer on both macOS and Linux, and each
  updates itself. A switch writes the settings of both, installs Antigravity CLI
  via its own installer on personal computers, and on Linux installs Rex's
  server from Rex's flake.
- **Tailscale and Google Chrome on a Mac.** Both are installed by hand.
  Tailscale gives the pair hub its address, and a Mac switch already starts it
  at login. mermaid-cli needs Google Chrome to draw its diagrams. Either could
  become a cask in `modules/darwin/homebrew.nix`.
- **The work Mac.** It's on hold. It has no host file, and the `work` role turns
  nothing on.
