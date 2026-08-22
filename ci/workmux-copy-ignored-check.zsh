#!/usr/bin/env zsh

set -euo pipefail

repo_root="${0:A:h:h}"
helper="$repo_root/workmux/bin/workmux-copy-ignored"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/workmux-copy-ignored.XXXXXX")"
trap 'rm -rf -- "$fixture_root"' EXIT

# Commit hooks inherit Git variables for the repository being committed. Clear
# them before operating on this independent fixture repository.
git_local_env_vars=("${(@f)$(git rev-parse --local-env-vars)}")
unset "${git_local_env_vars[@]}"

source_root="$fixture_root/source"
worktree_root="$fixture_root/worktree"

git init -q "$source_root"
git -C "$source_root" config user.email test@example.com
git -C "$source_root" config user.name Test

print -rl -- '.env' 'data/' 'ignored files/' >"$source_root/.gitignore"
print -r -- 'tracked' >"$source_root/tracked.txt"
git -C "$source_root" add .gitignore tracked.txt
git -C "$source_root" commit -qm 'Initialize fixture'

mkdir -p "$source_root/data/nested" "$source_root/ignored files"
print -r -- 'secret' >"$source_root/.env"
print -r -- 'training data' >"$source_root/data/nested/train.csv"
print -r -- 'spaced path' >"$source_root/ignored files/example.txt"
print -r -- 'leave behind' >"$source_root/untracked.txt"

git -C "$source_root" worktree add -q -b fixture "$worktree_root"
WM_PROJECT_ROOT="$source_root" WM_WORKTREE_PATH="$worktree_root" "$helper"

cmp "$source_root/.env" "$worktree_root/.env"
cmp "$source_root/data/nested/train.csv" "$worktree_root/data/nested/train.csv"
cmp "$source_root/ignored files/example.txt" "$worktree_root/ignored files/example.txt"
[[ ! -e "$worktree_root/untracked.txt" ]]
[[ ! -L "$worktree_root/.env" ]]

print -r -- 'changed later' >"$source_root/.env"
[[ "$(<"$worktree_root/.env")" == 'secret' ]]

print -r -- 'workmux-copy-ignored-check: ok'
