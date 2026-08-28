# The one install command, runnable from anywhere. A function rather
# than a script on PATH so there is no wrapper to deploy and nothing to
# go stale: it resolves the repo the same way env.zsh does -- through
# the ~/.zshrc symlink -- and hands every argument to install.sh.
#
#   dotfiles-install                    converge (interactive prompts)
#   dotfiles-install --non-interactive  converge, assume yes, no input
#   dotfiles-install upgrade            bump packages, before/after summary
#   dotfiles-install links              relink only
dotfiles-install() {
  local zshrc_real="$(readlink -f ~/.zshrc 2>/dev/null || readlink ~/.zshrc)"
  local dotfiles_dir="${zshrc_real:h:h}"
  if [[ ! -x "$dotfiles_dir/install.sh" ]]; then
    echo "dotfiles-install: no install.sh under $dotfiles_dir" >&2
    return 1
  fi
  (cd "$dotfiles_dir" && ./install.sh "$@")
}
