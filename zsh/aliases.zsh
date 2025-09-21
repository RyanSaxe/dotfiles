# Shared aliases for both minimal and full zsh configurations
# Basic aliases that are lightweight and commonly used

# Essential directory navigation
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Safety nets
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

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
alias grep='grep --color=auto'

# Quick edits
alias zshrc='$EDITOR ~/.zshrc'
alias vimrc='$EDITOR ~/.config/nvim/init.lua'

# Network and system info
alias myip='curl -s ipinfo.io/ip'
alias ports='netstat -tulanp'

# Development shortcuts
alias serve='python3 -m http.server'
alias prettyjson='python3 -m json.tool'