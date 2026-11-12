# Vi mode configuration and cursor management
# Sets up vi keybindings with visual cursor feedback

# Cursor-shape escapes are terminal control bytes: without the tty guard
# they contaminate captured output (any script parsing a `zsh -ic ...`
# result would see them).
_vi_cursor_block() {
  if [[ -t 1 ]]; then
    echo -ne '\e[1 q'
  fi
}

_vi_cursor_beam() {
  if [[ -t 1 ]]; then
    echo -ne '\e[5 q'
  fi
}

# Initialize vi mode
vi_mode_init() {
  # Enable vi mode
  set -o vi

  # Vi mode configuration
  export KEYTIMEOUT=1

  # Better vi mode indicator - changes cursor shape based on mode
  function zle-keymap-select {
    if [[ ${KEYMAP} == vicmd ]] ||
       [[ $1 = 'block' ]]; then
      _vi_cursor_block # Block cursor for command mode
    elif [[ ${KEYMAP} == main ]] ||
         [[ ${KEYMAP} == viins ]] ||
         [[ ${KEYMAP} = '' ]] ||
         [[ $1 = 'beam' ]]; then
      _vi_cursor_beam # Beam cursor for insert mode
    fi
  }
  zle -N zle-keymap-select

  # Initialize line editor in insert mode with beam cursor
  zle-line-init() {
      zle -K viins
      _vi_cursor_beam
  }
  zle -N zle-line-init

  # Set initial cursor to beam
  _vi_cursor_beam

  # Ensure beam cursor on command execution
  preexec() { _vi_cursor_beam ;}
}
