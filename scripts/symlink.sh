#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ──────────────────────────────────────────────────────
# Dotfiles Symlink Manager
# Creates symlinks for all dotfiles with backup functionality
# ──────────────────────────────────────────────────────

# Colorized logging (matching install.sh style)
log() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }
success() { printf "\033[1;32m[OK  ]\033[0m %s\n" "$*"; }

# ──────────────────────────────────────────────────────
# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")/dotfiles"
BACKUP_DIR="$HOME/.dotfiles_backup_$(date +%Y%m%d_%H%M%S)"

# Dotfile mappings: source_path:target_path
declare -A DOTFILE_MAPPINGS=(
    ["nvim"]="$HOME/.config/nvim"
    ["bat/config"]="$HOME/.config/bat/config"
    ["bat/themes"]="$HOME/.config/bat/themes"
    ["ghostty/config"]="$HOME/.config/ghostty/config"
    ["zsh/zshrc"]="$HOME/.zshrc"
    ["zsh/fino-time-custom.zsh-theme"]="$HOME/.oh-my-zsh/custom/themes/fino-time-custom.zsh-theme"
    ["git/ignore"]="$HOME/.config/git/ignore"
)

# ──────────────────────────────────────────────────────
# Helper functions

backup_existing() {
    local target=$1
    if [[ -e "$target" && ! -L "$target" ]]; then
        log "Backing up existing $target"
        mkdir -p "$BACKUP_DIR/$(dirname "${target#$HOME/}")"
        cp -r "$target" "$BACKUP_DIR/${target#$HOME/}"
        return 0
    elif [[ -L "$target" ]]; then
        warn "Existing symlink found at $target - removing"
        rm "$target"
        return 0
    fi
    return 1
}

create_symlink() {
    local source=$1
    local target=$2
    
    # Create target directory if it doesn't exist
    mkdir -p "$(dirname "$target")"
    
    # Backup existing file/directory if needed
    backup_existing "$target"
    
    # Create the symlink
    if ln -sf "$source" "$target"; then
        success "✓ $target → $source"
        return 0
    else
        err "✗ Failed to create symlink: $target → $source"
        return 1
    fi
}

# ──────────────────────────────────────────────────────
# Main symlink function

symlink_dotfiles() {
    local failed=0
    
    log "Starting dotfiles symlinking..."
    log "Dotfiles directory: $DOTFILES_DIR"
    log "Backup directory: $BACKUP_DIR"
    echo
    
    # Verify dotfiles directory exists
    if [[ ! -d "$DOTFILES_DIR" ]]; then
        err "Dotfiles directory not found: $DOTFILES_DIR"
        exit 1
    fi
    
    # Create backup directory if we need it
    local backup_needed=false
    for mapping in "${!DOTFILE_MAPPINGS[@]}"; do
        local target="${DOTFILE_MAPPINGS[$mapping]}"
        if [[ -e "$target" && ! -L "$target" ]]; then
            backup_needed=true
            break
        fi
    done
    
    if [[ "$backup_needed" == true ]]; then
        mkdir -p "$BACKUP_DIR"
        log "Created backup directory: $BACKUP_DIR"
    fi
    
    # Process each dotfile mapping
    for mapping in "${!DOTFILE_MAPPINGS[@]}"; do
        local source="$DOTFILES_DIR/$mapping"
        local target="${DOTFILE_MAPPINGS[$mapping]}"
        
        if [[ ! -e "$source" ]]; then
            warn "Source not found, skipping: $source"
            continue
        fi
        
        if ! create_symlink "$source" "$target"; then
            ((failed++))
        fi
    done
    
    echo
    if ((failed == 0)); then
        success "✅ All dotfiles symlinked successfully!"
        if [[ -d "$BACKUP_DIR" ]]; then
            log "Backups saved to: $BACKUP_DIR"
        fi
    else
        err "❌ $failed symlinks failed"
        exit 1
    fi
}

# ──────────────────────────────────────────────────────
# Command line options

show_help() {
    cat << EOF
Dotfiles Symlink Manager

USAGE:
    $(basename "$0") [OPTIONS]

OPTIONS:
    -h, --help      Show this help message
    -l, --list      List all configured symlinks
    -d, --dry-run   Show what would be done without making changes
    -f, --force     Force overwrite existing symlinks

EXAMPLES:
    $(basename "$0")                 # Create all symlinks
    $(basename "$0") --list          # Show configured mappings
    $(basename "$0") --dry-run       # Preview changes

EOF
}

list_mappings() {
    log "Configured dotfile mappings:"
    echo
    for mapping in "${!DOTFILE_MAPPINGS[@]}"; do
        local source="$DOTFILES_DIR/$mapping"
        local target="${DOTFILE_MAPPINGS[$mapping]}"
        printf "  %-30s → %s\n" "$source" "$target"
    done
}

dry_run() {
    log "DRY RUN - showing what would be done:"
    echo
    
    for mapping in "${!DOTFILE_MAPPINGS[@]}"; do
        local source="$DOTFILES_DIR/$mapping"
        local target="${DOTFILE_MAPPINGS[$mapping]}"
        
        if [[ ! -e "$source" ]]; then
            warn "SKIP: Source not found - $source"
            continue
        fi
        
        if [[ -e "$target" && ! -L "$target" ]]; then
            log "BACKUP: $target → $BACKUP_DIR"
        elif [[ -L "$target" ]]; then
            warn "REMOVE: Existing symlink at $target"
        fi
        
        log "LINK: $target → $source"
    done
}

# ──────────────────────────────────────────────────────
# Main execution

main() {
    local dry_run_mode=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list)
                list_mappings
                exit 0
                ;;
            -d|--dry-run)
                dry_run_mode=true
                shift
                ;;
            -f|--force)
                # Force mode - could add logic to skip backup prompts
                shift
                ;;
            *)
                err "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    if [[ "$dry_run_mode" == true ]]; then
        dry_run
    else
        symlink_dotfiles
    fi
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi