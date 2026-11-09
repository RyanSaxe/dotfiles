#!/bin/sh
# Byte-parity gate for the prompt collector (PLAN.md Phase 5): the rewritten
# zsh/prompt-segments.sh must emit exactly the bytes the shipped one did,
# fixture by fixture. Old = the script at $PROMPT_PARITY_OLD_REF (default:
# the last pre-rewrite commit that touched it); new = the working tree. Each
# fixture runs the new script twice — cold package cache, then warm — and
# diffs both runs against the old script's output.
#
# Commit dates are pinned so the relative AGE segment cannot drift between
# the old and new runs; everything lives in a throwaway mktemp tree with
# HOME/XDG_CACHE_HOME/TMPDIR/STARSHIP_CONFIG scoped to it and
# GIT_CEILING_DIRECTORIES fencing the fixture walk. Re-runnable; exits
# nonzero when any fixture diverges. PROMPT_PARITY_KEEP=1 keeps the tree.
set -eu

REPO=$(cd "$(dirname "$0")/../.." && pwd -P)
OLD_REF=${PROMPT_PARITY_OLD_REF:-c6584602c4e66f91201228d8728b0c579d40ac01}
NEW=$REPO/zsh/prompt-segments.sh

work=$(mktemp -d "${TMPDIR:-/tmp}/prompt-parity.XXXXXX")
work=$(cd "$work" && pwd -P)
if [ "${PROMPT_PARITY_KEEP:-}" = 1 ]; then
  trap 'printf "kept: %s\n" "$work"' EXIT
else
  trap 'rm -rf "$work"' EXIT
fi

git -C "$REPO" show "$OLD_REF:zsh/prompt-segments.sh" >"$work/old.sh"

export HOME="$work/home"
export XDG_CACHE_HOME="$work/cache"
export TMPDIR="$work/tmp"
export STARSHIP_CONFIG="$work/starship.toml"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_CEILING_DIRECTORIES="$work"
export GIT_AUTHOR_DATE='2020-01-01T00:00:00 +0000'
export GIT_COMMITTER_DATE='2020-01-01T00:00:00 +0000'
unset VIRTUAL_ENV
fx=$work/fx
mkdir -p "$HOME" "$XDG_CACHE_HOME" "$TMPDIR" "$fx" "$work/out"
# ${raw}/${version} are starship template placeholders, not shell expansions.
# shellcheck disable=SC2016
printf '[package]\nversion_format = "${raw}"\nformat = "v${version}"\n' \
  >"$STARSHIP_CONFIG"

g() { # $1 repo dir, rest: git args — identity pinned, config neutralized
  gdir=$1
  shift
  git -C "$gdir" -c user.email=parity@example.com -c user.name=parity "$@"
}

mk_repo() { # $1 dir -> repo with one pinned commit on main
  git init -q -b main "$1"
  echo content >"$1/file.txt"
  g "$1" add .
  g "$1" commit -qm base
}

mk_venv() { # $1 dir -> fake venv with executable python + pyvenv.cfg
  mkdir -p "$1/bin"
  touch "$1/bin/python"
  chmod +x "$1/bin/python"
  printf 'version = 3.12.4\n' >"$1/pyvenv.cfg"
}

# ---- fixtures ---------------------------------------------------------
mk_repo "$fx/clean"

mk_repo "$fx/dirty"
echo change >>"$fx/dirty/file.txt"

mk_repo "$fx/untracked"
touch "$fx/untracked/extra.txt"

mk_repo "$fx/ahead-origin"
git clone -q "$fx/ahead-origin" "$fx/ahead"
echo more >>"$fx/ahead/file.txt"
g "$fx/ahead" commit -aqm ahead

mk_repo "$fx/behind-origin"
git clone -q "$fx/behind-origin" "$fx/behind"
echo more >>"$fx/behind-origin/file.txt"
g "$fx/behind-origin" commit -aqm advance
g "$fx/behind" fetch -q origin

mk_repo "$fx/diverged-origin"
git clone -q "$fx/diverged-origin" "$fx/diverged"
echo more >>"$fx/diverged-origin/file.txt"
g "$fx/diverged-origin" commit -aqm advance
echo local >>"$fx/diverged/file.txt"
g "$fx/diverged" commit -aqm local
g "$fx/diverged" fetch -q origin

mk_repo "$fx/detached"
g "$fx/detached" checkout -q --detach

mk_repo "$fx/noupstream" # no remote at all

mk_repo "$fx/gone-origin" # upstream configured but its ref no longer resolves
git clone -q "$fx/gone-origin" "$fx/gone"
g "$fx/gone" update-ref -d refs/remotes/origin/main

git init -q -b main "$fx/nocommits"

mk_repo "$fx/subdir"
mkdir -p "$fx/subdir/a/b/c/d" # deep enough that SUBDIR collapses

mk_repo "$fx/mroot"
printf '{ "name": "root", "version": "1.2.3" }\n' >"$fx/mroot/package.json"
g "$fx/mroot" add .
g "$fx/mroot" commit -qm manifest

mk_repo "$fx/mdeep" # deepest manifest wins over the root one
printf '{ "name": "root", "version": "9.9.9" }\n' >"$fx/mdeep/package.json"
mkdir -p "$fx/mdeep/packages/app" "$fx/mdeep/packages/lib"
printf '{ "name": "app", "version": "2.0.0" }\n' \
  >"$fx/mdeep/packages/app/package.json"
printf '{ "name": "lib" }\n' >"$fx/mdeep/packages/lib/package.json"
g "$fx/mdeep" add .
g "$fx/mdeep" commit -qm manifests

mk_repo "$fx/venvok"
mk_venv "$fx/venvok/.venv"

mk_repo "$fx/venvbad"
mk_venv "$fx/otherproj/.venv"

mkdir -p "$fx/plain/nested"

# ---- old-vs-new(cold)-vs-new(warm) diff per fixture -------------------
fails=0

run_collector() { # $1 rundir, $2 script, $3 outfile, $4 VIRTUAL_ENV or ''
  (
    cd "$1" || exit 1
    if [ -n "$4" ]; then
      VIRTUAL_ENV=$4
      export VIRTUAL_ENV
    fi
    exec dash "$2" >"$3" 2>/dev/null
  )
}

check() { # $1 name, $2 rundir, $3 VIRTUAL_ENV or ''
  out=$work/out/$1
  run_collector "$2" "$work/old.sh" "$out.old" "$3"
  rm -f "$XDG_CACHE_HOME/dotfiles/pkg-versions.tsv"
  run_collector "$2" "$NEW" "$out.cold" "$3"
  run_collector "$2" "$NEW" "$out.warm" "$3"
  ok=true
  diff -u "$out.old" "$out.cold" >"$out.diff-cold" || ok=false
  diff -u "$out.old" "$out.warm" >"$out.diff-warm" || ok=false
  if [ "$ok" = true ]; then
    printf 'PASS %s\n' "$1"
  else
    fails=$((fails + 1))
    printf 'FAIL %s\n' "$1"
    cat "$out.diff-cold" "$out.diff-warm"
  fi
}

check clean "$fx/clean" ''
check dirty "$fx/dirty" ''
check untracked-only "$fx/untracked" ''
check ahead "$fx/ahead" ''
check behind "$fx/behind" ''
check diverged "$fx/diverged" ''
check detached "$fx/detached" ''
check no-upstream "$fx/noupstream" ''
check upstream-gone "$fx/gone" ''
check no-commits "$fx/nocommits" ''
check subdir "$fx/subdir/a/b/c/d" ''
check manifest-root "$fx/mroot" ''
check manifest-subdir "$fx/mdeep/packages/app" ''
check manifest-subdir-versionless "$fx/mdeep/packages/lib" ''
check venv-ok "$fx/venvok" "$fx/venvok/.venv"
check venv-mismatch "$fx/venvbad" "$fx/otherproj/.venv"
check outside-repo "$fx/plain/nested" ''
check home-dir "$HOME" ''

if [ "$fails" -gt 0 ]; then
  printf '%d fixture(s) diverged\n' "$fails"
  exit 1
fi
printf 'all fixtures byte-identical (old %s vs working tree, cold+warm)\n' \
  "$(git -C "$REPO" rev-parse --short "$OLD_REF")"
