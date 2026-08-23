# Environment variable loading functions
# Automatically loads .env file from dotfiles directory

# Load environment variables from .env file
_load_dotenv() {
  # Get the dotfiles directory (parent of zsh dir)
  # This works whether called from symlinked location or actual location
  local zshrc_real="$(readlink -f ~/.zshrc 2>/dev/null || readlink ~/.zshrc)"
  local dotfiles_dir="${zshrc_real:h:h}"
  local env_file="${dotfiles_dir}/.env"

  # Check if .env file exists
  if [[ -f "$env_file" ]]; then
    # Read and export each valid assignment, including a final line without a
    # newline. The optional `export` prefix is syntax, not part of the key.
    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ '^[[:space:]]*(export[[:space:]]+)?([[:alpha:]_][[:alnum:]_]*)[[:space:]]*=(.*)$' ]]; then
        key="${match[2]}"
        value="${match[3]}"
        # Remove quotes from value if present
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        # Export the variable
        export "$key"="$value"
      fi
    done < "$env_file"
  fi
}

# Initialize environment loading
env_init() {
  _load_dotenv
}
