# Backup Directory

This directory contains backups of files that were replaced during symlink creation.

## How to Restore Backups

1. Check RESTORE_INSTRUCTIONS.txt for the mapping of backup files to their original locations
2. To restore a backup, copy it back to its original location:
   
   Example:
   If RESTORE_INSTRUCTIONS.txt shows:
   /path/to/dotfiles/backups/.zshrc_20240824_143022 → /Users/username/.zshrc
   
   Then run:
   cp /path/to/dotfiles/backups/.zshrc_20240824_143022 /Users/username/.zshrc

## File Naming Convention

Backup files are named: {original_basename}_{YYYYMMDD_HHMMSS}

Examples:
- .zshrc_20240824_143022 (backed up on Aug 24, 2024 at 14:30:22)
- config_20240824_143045 (backed up on Aug 24, 2024 at 14:30:45)

## Notes

- This directory is automatically ignored by git
- RESTORE_INSTRUCTIONS.txt is automatically updated each time a backup is created
- Backups are only created for real files/directories, not existing symlinks