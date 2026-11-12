# Lightweight, commonly used aliases.

# Essential directory navigation
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Git shortcuts (minimal set)
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline'

# Common utilities
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'

# System utilities
alias df='df -h'
alias du='du -h'
# apt installs bat's binary as batcat to avoid clashing with bacula-console.
command -v batcat >/dev/null 2>&1 && alias bat='batcat'
# ...and fd as fdfind, clashing with fdclone. Same rename, same remedy.
command -v fdfind >/dev/null 2>&1 && alias fd='fdfind'
# alias grep='grep --color=auto' -- commenting due to claude using grep a lot


# Quick edits
alias zshrc='$EDITOR ~/.zshrc'

# Network and system info
alias myip='curl -s ipinfo.io/ip'
