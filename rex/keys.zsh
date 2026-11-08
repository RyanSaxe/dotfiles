#!/bin/zsh
# Lists the keys init.lua binds, then Rex's default Mac shortcuts, in fzf.
# $1 is the app's client ID: the app titles its own actions and `rex actions`
# titles init.lua's.
titles=$({
  rex ${1:+-C "$1"} actions --json
  rex actions --json
} | jq -s '[.[].actions[] | {(.name): .title}] | add')
{
  rex keymap --json | jq -r --argjson t "$titles" '
    .bindings[]
    | [(.keys | join(" ")), ($t[.action] // .action) + (.args // {} | to_entries | map(" \(.key)=\(.value)") | join("")), "init.lua"]
    | join("\t")'
  awk -F'\t' '{ print $1 "\t" $2 "\tRex" }' "${0:A:h}/default-keys.tsv"
} | column -t -s $'\t' | fzf --prompt='Keys: ' --no-sort --layout=reverse
