# Vi mode configuration and cursor management
# Sets up vi keybindings with visual cursor feedback

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
      echo -ne '\e[1 q'  # Block cursor for command mode
    elif [[ ${KEYMAP} == main ]] ||
         [[ ${KEYMAP} == viins ]] ||
         [[ ${KEYMAP} = '' ]] ||
         [[ $1 = 'beam' ]]; then
      echo -ne '\e[5 q'  # Beam cursor for insert mode
    fi
  }
  zle -N zle-keymap-select

  # Initialize line editor in insert mode with beam cursor
  zle-line-init() {
      zle -K viins
      echo -ne "\e[5 q"
  }
  zle -N zle-line-init

  # Set initial cursor to beam
  echo -ne '\e[5 q'

  # Ensure beam cursor on command execution
  preexec() { echo -ne '\e[5 q' ;}
}
