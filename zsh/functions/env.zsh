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
    # Read and export each non-comment line as an environment variable
    while IFS='=' read -r key value; do
      # Skip comments and empty lines
      if [[ ! "$key" =~ ^[[:space:]]*# ]] && [[ -n "$key" ]]; then
        # Remove leading/trailing whitespace from key
        key="$(echo "$key" | xargs)"
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