# Shared aliases for both minimal and full zsh configurations
# Basic aliases that are lightweight and commonly used

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
alias free='free -h'
# alias grep='grep --color=auto' -- commenting due to claude using grep a lot

# Development tools
alias lsp-check='~/generic/dotfiles/scripts/lsp-check'
alias nvim-clean='~/generic/dotfiles/scripts/nvim-clean.sh'
alias diagnose='uvx ty check --output-format concise --no-progress --color never --exit-zero | rg -o "(error|warning)\[[^]]+\]" | sort | uniq -c | sort -nr | awk "{print \$2 \": \" \$1}"'

# Quick edits
alias zshrc='$EDITOR ~/.zshrc'

# Network and system info
alias myip='curl -s ipinfo.io/ip'
alias ports='netstat -tulanp'

# special local tools

alias pptx='uvx --refresh --from ~/work/Reusable/ppt-generator ppt'
