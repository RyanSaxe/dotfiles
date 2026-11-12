# The shell's colors: fzf, zsh's ghost text, and the hints other tools read.
# zsh re-reads this file when `theme` changes it.
{ t, mode, ... }:
{
  "shell-colors.zsh" = ''
    # Tells terminal programs which mode this is.
    export COLORFGBG='${if mode == "dark" then "15;0" else "0;15"}'
    # delta reads bat's theme only from here.
    export BAT_THEME="dotfiles-${mode}"
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=${t.faint}'
    # Naming the mode stops fzf asking the terminal, whose answer leaks into
    # tmux popups as text.
    typeset -ga FZF_THEME_COLORS=(
      "--color=${mode},bg+:${t.raised},bg:${t.background},border:${t.border}"
      "--color=fg:${t.text},fg+:${t.text},hl:${t.accent},hl+:${t.second}"
      "--color=info:${t.info},prompt:${t.accent},pointer:${t.second}"
      "--color=marker:${t.ok},spinner:${t.second},header:${t.muted}"
    )
    export FZF_DEFAULT_OPTS="''${FZF_THEME_COLORS[*]}"
  '';
}
