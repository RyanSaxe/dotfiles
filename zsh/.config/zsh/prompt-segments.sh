#!/bin/dash
# Every prompt fact, gathered in ONE spawn per prompt. Git queries run as
# parallel jobs (total ~= the slowest, not the sum) and each visible segment
# prints as a NAME<US>value line for the _prompt_segments precmd (.zshrc) to
# export as _PROMPT_SEG_* vars; the starship template renders those through
# native env_var modules, in-process. Starship spawns nothing at render time
# — the old custom modules cost two login-zsh spawns each, ~79ms per prompt.
#
# dash, not zsh: the one deliberate exception to the zsh scripts convention
# (AGENTS.md). This runs on every prompt, and a dash spawn is ~1ms where a
# login zsh is ~13ms — spawn cost is the entire reason this script exists.
#
# A segment hides by never being emitted; the precmd unsets the whole
# namespace first. Never emit an empty value: an exported-but-empty var
# still renders its module's connector words ("in ", "on ", ...).

# Paths from git are canonical; $PWD and $VIRTUAL_ENV keep whatever spelling
# they were reached through (symlinks, foreign casing on macOS's
# case-insensitive FS). Comparisons against git paths use canonical
# spellings on both sides — display of non-repo paths stays logical.
pwd_p="$(pwd -P)"

# Directory names may contain glob characters; collapse() word-splits paths.
set -f

tmp="${TMPDIR:-/tmp}/prompt-seg.$$"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT

# One combined rev-parse replaces the eight scattered probes the old custom
# modules ran. --abbrev-ref must NOT join it: that mode sticks to later args,
# so the detached-HEAD hash comes from --short and the branch name from the
# parallel --show-current below.
git rev-parse --is-inside-work-tree --show-toplevel --show-prefix --short HEAD \
  >"$tmp/rp" 2>/dev/null &
rp_pid=$!

git branch --show-current >"$tmp/br" 2>/dev/null &
br_pid=$!
git rev-list --left-right --count '@{u}...HEAD' >"$tmp/lr" 2>/dev/null &
lr_pid=$!
git log -1 --format=%cr >"$tmp/age" 2>/dev/null &
age_pid=$!
git status --porcelain >"$tmp/st" 2>/dev/null &
st_pid=$!

wait "$rp_pid"
in_repo=false top='' prefix='' shorthead=''
if [ -s "$tmp/rp" ]; then
  {
    read -r in_repo
    read -r top
    read -r prefix
    read -r shorthead
  } <"$tmp/rp"
fi

# Package version: probe every level from here to the repo root AT ONCE and
# take the deepest hit — same winner as a serial walk at a fraction of the
# wall time. Manifest detection stays starship's (`starship module package`,
# all ~15 formats); this script never learns a manifest name. The guards —
# canonical start, strictly shortening d, break at empty — keep the walk
# from ever leaving the repo or looping.
if [ "$in_repo" = true ]; then
  (
    d="$pwd_p" i=0
    while :; do
      (cd "$d" && starship module package >"$tmp/pkg.$i") &
      [ "$d" = "$top" ] && break
      case "$d" in */*) d="${d%/*}" ;; *) break ;; esac
      [ -n "$d" ] || break
      i=$((i + 1))
    done
    wait
    j=0
    while [ "$j" -le "$i" ]; do
      if [ -s "$tmp/pkg.$j" ]; then
        cp "$tmp/pkg.$j" "$tmp/pkg"
        break
      fi
      j=$((j + 1))
    done
  ) &
  pkg_pid=$!
fi

# An unfinished job's file reads as empty — which is a MEANING here (clean
# tree, no upstream, no commits) — so every remaining git job must complete
# before anything below reads its file. The pkg walk keeps running alongside;
# it is waited for last, right before PKG emits.
wait "$br_pid" "$lr_pid" "$age_pid" "$st_pid"

emit() { # $1 name, $2 value — a hidden segment is simply never emitted
  [ -n "$2" ] || return 0
  printf '%s\037%s\n' "$1" "$2"
}

home_tilde() { # $1: path -> ~-abbreviated
  case "$1" in
  "$HOME") printf '~' ;;
  "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
  *) printf %s "$1" ;;
  esac
}

collapse() { # $1: path, $2: max segments -> first/…/last/two
  path=$1 max=$2
  oldifs=$IFS
  IFS=/
  # The unquoted expansion is deliberate: word splitting IS the segment count.
  # shellcheck disable=SC2086
  set -- $path
  IFS=$oldifs
  if [ $# -gt "$max" ]; then
    first=$1
    shift $(($# - 2))
    printf '%s/…/%s/%s' "$first" "$1" "$2"
  else
    printf %s "$path"
  fi
}

if [ "$in_repo" = true ]; then
  # WHERE: repo-relative path, hidden at the root itself, where the repo's
  # parent directory shows instead.
  prefix="${prefix%/}"
  if [ -n "$prefix" ]; then
    emit SUBDIR "$(collapse "$prefix" 3)"
  else
    p="${top%/*}"
    [ -n "$p" ] || p=/
    emit REPO_PARENT "$(home_tilde "$p")"
  fi
  # Branch: named, or short hash when detached (mirrors the old
  # `git branch --show-current | grep . || git rev-parse --short HEAD`).
  branch=''
  [ -s "$tmp/br" ] && read -r branch <"$tmp/br"
  [ -n "$branch" ] || branch="$shorthead"
  ahead=0 behind=0
  if [ -s "$tmp/lr" ]; then
    # left = upstream-only commits (behind), right = ours (ahead)
    read -r behind ahead <"$tmp/lr"
  fi
  if [ "$behind" -gt 0 ]; then
    emit BRANCH_BEHIND "$branch"
  else
    emit BRANCH "$branch"
  fi
  # Ahead/behind arrows: the same rev-list counts as the branch color, the
  # same default symbols native git_status printed, nothing when synced.
  if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
    emit ARROWS '⇕'
  elif [ "$ahead" -gt 0 ]; then
    emit ARROWS '⇡'
  elif [ "$behind" -gt 0 ]; then
    emit ARROWS '⇣'
  fi
  # Time since last commit; hidden while a repo has no commits yet.
  if [ -s "$tmp/age" ]; then
    read -r age <"$tmp/age"
    emit AGE "${age% ago}"
  fi
  if [ -s "$tmp/st" ]; then emit DIRTY '✗'; else emit CLEAN '✓'; fi
elif [ "$PWD" != "$HOME" ]; then
  # Outside any repo: line 1 shows the parent of the current folder; the
  # folder's own name sits on line 2. Hidden at ~ itself.
  p="${PWD%/*}"
  [ -n "$p" ] || p=/
  emit DIR_PLAIN "$(collapse "$(home_tilde "$p")" 4)"
fi

# ---- line 2: project name as the venv status light --------------------
anchor="${top:-$pwd_p}"
if [ -n "$VIRTUAL_ENV" ]; then
  venv_proj="${VIRTUAL_ENV%/*}"
  # $VIRTUAL_ENV keeps its activation-time spelling — resolve it before
  # comparing, or a matching venv reads as an impostor.
  if [ "$(cd "$venv_proj" 2>/dev/null && pwd -P)" = "$anchor" ]; then
    emit PROJ_OK "${anchor##*/}"
  else
    emit PROJ_BAD "${venv_proj##*/}"
  fi
  # The venv interpreter's version straight from pyvenv.cfg — no
  # interpreter launch, no sed/head/cut spawns. Both `version = ` and
  # `version_info = ` forms appear in the wild.
  if [ -f "$VIRTUAL_ENV/pyvenv.cfg" ]; then
    pyv=''
    while IFS= read -r line; do
      case "$line" in
      version" "*=* | version=* | version_info*=*)
        pyv="${line#*=}"
        pyv="${pyv# }"
        break
        ;;
      esac
    done <"$VIRTUAL_ENV/pyvenv.cfg"
    if [ -n "$pyv" ]; then
      maj="${pyv%%.*}"
      rest="${pyv#*.}"
      emit PYVERSION "$maj.${rest%%.*}"
    fi
  fi
elif [ "$in_repo" = true ]; then
  emit PROJ_PLAIN "${anchor##*/}"
elif [ "$PWD" = "$HOME" ]; then
  emit DIR_NAME '~'
else
  name="${PWD##*/}"
  [ -n "$name" ] || name="$PWD" # at /, the basename is the path itself
  emit DIR_NAME "$name"
fi

[ -n "${pkg_pid:-}" ] && wait "$pkg_pid"
if [ -s "$tmp/pkg" ]; then
  read -r pkg <"$tmp/pkg"
  emit PKG "$pkg"
fi
