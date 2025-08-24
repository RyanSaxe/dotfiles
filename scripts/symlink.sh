#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ──────────────────────────────────────────────────────
# Dotfiles Symlink Manager
# Creates symlinks for all dotfiles with version control management
# ──────────────────────────────────────────────────────

# Colorized logging (matching install.sh style)
log() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }
success() { printf "\033[1;32m[OK  ]\033[0m %s\n" "$*"; }

# ──────────────────────────────────────────────────────
# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

# Load dotfile mappings from config file
DOTFILE_MAPPINGS=()
while IFS= read -r line; do
  DOTFILE_MAPPINGS[${#DOTFILE_MAPPINGS[@]}]="$line"
done < "$DOTFILES_DIR/config/symlinks.txt"

# ──────────────────────────────────────────────────────
# Helper functions

create_symlink() {
    local source=$1
    local target=$2
    
    # Create target directory if it doesn't exist
    mkdir -p "$(dirname "$target")"
    
    # Handle existing files/symlinks safely
    if [[ -e "$target" || -L "$target" ]]; then
        if [[ -L "$target" ]]; then
            # It's a symlink, safe to remove
            rm -f "$target"
        else
            # It's a real file/directory, back it up
            local timestamp=$(date +%Y%m%d_%H%M%S)
            local backup_name="$(basename "$target")_${timestamp}"
            local backup_path="$DOTFILES_DIR/backups/$backup_name"
            mv "$target" "$backup_path"
            
            # Create restore instructions
            echo "$backup_path → $target" >> "$DOTFILES_DIR/backups/RESTORE_INSTRUCTIONS.txt"
            warn "Backed up existing file to $backup_path"
        fi
    fi
    
    # Create the symlink (use -n for BSD/macOS compatibility)
    if ln -sfn "$source" "$target"; then
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
    echo
    
    # Verify dotfiles directory exists
    if [[ ! -d "$DOTFILES_DIR" ]]; then
        err "Dotfiles directory not found: $DOTFILES_DIR"
        exit 1
    fi
    
    # Process each dotfile mapping
    for mapping in "${DOTFILE_MAPPINGS[@]}"; do
        IFS=: read -r src_path target_path <<<"$mapping"
        local source="$DOTFILES_DIR/$src_path"
        local target="$target_path"
        
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

EXAMPLES:
    $(basename "$0")                 # Create all symlinks
    $(basename "$0") --list          # Show configured mappings
    $(basename "$0") --dry-run       # Preview changes

EOF
}

list_mappings() {
    log "Configured dotfile mappings:"
    echo
    for mapping in "${DOTFILE_MAPPINGS[@]}"; do
        IFS=: read -r src_path target_path <<<"$mapping"
        local source="$DOTFILES_DIR/$src_path"
        local target="$target_path"
        printf "  %-30s → %s\n" "$source" "$target"
    done
}

dry_run() {
    log "DRY RUN - showing what would be done:"
    echo
    
    for mapping in "${DOTFILE_MAPPINGS[@]}"; do
        IFS=: read -r src_path target_path <<<"$mapping"
        local source="$DOTFILES_DIR/$src_path"
        local target="$target_path"
        
        if [[ ! -e "$source" ]]; then
            warn "SKIP: Source not found - $source"
            continue
        fi
        
        if [[ -e "$target" || -L "$target" ]]; then
            if [[ -L "$target" ]]; then
                warn "REMOVE: Existing symlink at $target"
            else
                warn "BACKUP: Existing file at $target"
            fi
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