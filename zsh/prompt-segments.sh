#!/bin/dash
# Every prompt fact, gathered in ONE spawn per prompt. Three sequential git
# commands cover everything git knows — `status --porcelain=v2 --branch` for
# branch/ahead-behind/dirty, one combined rev-parse for paths and the
# detached short head, `log -1` for age — and each visible segment prints as
# a NAME<US>value line for the _prompt_segments precmd (.zshrc) to export as
# _PROMPT_SEG_* vars; the starship template renders those through native
# env_var modules, in-process. Starship spawns nothing at render time — the
# old custom modules cost two login-zsh spawns each, ~79ms per prompt.
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

# The prompt must never contend for index.lock or rewrite the index behind
# a running git command; `status` below would otherwise do both. Same
# setting starship uses for its own git calls. Output is unaffected.
GIT_OPTIONAL_LOCKS=0
export GIT_OPTIONAL_LOCKS

# Directory names may contain glob characters; collapse() word-splits paths.
# The package probe below is the one spot that needs globbing and re-enables
# it locally.
set -f

# One combined rev-parse answers: in a repo at all (top stays empty outside
# one, and inside .git/ or a bare repo where nothing prints), where the root
# is, where we are inside it, and the short head for detached display. In a
# repo with no commits yet the trailing `--short HEAD` fails AFTER toplevel
# and prefix printed — the partial output is exactly the partial truth
# (shorthead stays empty). --abbrev-ref must NOT join this command: that
# mode sticks to later args.
rp="$(git rev-parse --show-toplevel --show-prefix --short HEAD 2>/dev/null)"
top='' prefix='' shorthead=''
if [ -n "$rp" ]; then
  {
    read -r top
    read -r prefix
    read -r shorthead
  } <<EOF
$rp
EOF
fi
in_repo=false
[ -n "$top" ] && in_repo=true

# Branch, ahead/behind, and dirtiness from one status call. Header lines
# (`# branch.*`) always precede entries, so the first non-header line means
# a dirty tree and ends the parse. `branch.ab +A -B` appears only when an
# upstream is set AND its ref resolves — absent, ahead/behind stay 0, which
# matches the old script's failed `rev-list @{u}...HEAD` (no arrows, plain
# branch color). `branch.head` is `(detached)` on a detached HEAD, where the
# old `git branch --show-current` printed nothing.
branch='' ahead=0 behind=0 dirty=false age=''
if [ "$in_repo" = true ]; then
  st="$(git status --porcelain=v2 --branch 2>/dev/null)"
  while IFS= read -r line; do
    case "$line" in
    '# branch.head '*) branch="${line#"# branch.head "}" ;;
    '# branch.ab '*)
      ab="${line#"# branch.ab "}"
      ahead="${ab%% *}" ahead="${ahead#+}"
      behind="${ab#* }" behind="${behind#-}"
      ;;
    '#'*) ;;
    ?*)
      dirty=true
      break
      ;;
    esac
  done <<EOF
$st
EOF
  [ "$branch" = '(detached)' ] && branch=''
  # Time since last commit; empty (hidden) while a repo has no commits yet.
  age="$(git log -1 --format=%cr 2>/dev/null)"
fi

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
  # Branch: named, or short hash when detached.
  [ -n "$branch" ] || branch="$shorthead"
  if [ "$behind" -gt 0 ]; then
    emit BRANCH_BEHIND "$branch"
  else
    emit BRANCH "$branch"
  fi
  # Ahead/behind arrows: the same counts as the branch color, the same
  # default symbols native git_status printed, nothing when synced.
  if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
    emit ARROWS '⇕'
  elif [ "$ahead" -gt 0 ]; then
    emit ARROWS '⇡'
  elif [ "$behind" -gt 0 ]; then
    emit ARROWS '⇣'
  fi
  if [ -n "$age" ]; then
    emit AGE "${age% ago}"
  fi
  if [ "$dirty" = true ]; then emit DIRTY '✗'; else emit CLEAN '✓'; fi
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
  if [ ! -x "$VIRTUAL_ENV/bin/python" ]; then
    # A deleted or half-built venv can stay exported until the next cd;
    # green here would claim a working interpreter that is gone.
    emit PROJ_BAD "${venv_proj##*/}"
  elif [ "$(cd "$venv_proj" 2>/dev/null && pwd -P)" = "$anchor" ]; then
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

# ---- package version: probe-first walk with an mtime-keyed cache -------
# Walk from here up to the repo root; the deepest level that yields a
# version wins (the same winner as the old spawn-starship-at-every-level
# walk). A level with no manifest costs only [ -f ] checks — zero spawns.
# A level WITH manifests keys a cache entry on their batched mtimes (one
# stat spawn); a hit answers with zero further spawns, and only a miss runs
# `starship module package` there — so a prompt costs one starship spawn
# per manifest level per content change, not N+1 spawns every time. An
# empty cached value means "manifest present but starship prints no
# version" — remembered so the walk continues upward without respawning.
#
# Cache: ${XDG_CACHE_HOME:-~/.cache}/dotfiles/pkg-versions.tsv, one
# dir<TAB>key<TAB>value line per manifest dir ever visited (tiny; safe to
# delete any time), rewritten atomically via mktemp+mv on a miss.
#
# The manifest list mirrors what starship 1.26.0's package module reads
# (src/modules/package.rs; https://starship.rs/config/#package). DRIFT
# RISK: this probe decides where starship even runs, so a manifest format
# a newer starship learns stays invisible here until this list learns it
# too. `stat -nf` is BSD/macOS (all one line, no per-file newline).
PKG_MANIFESTS='package.json deno.json deno.jsonc jsr.json jsr.jsonc
Cargo.toml pyproject.toml setup.cfg composer.json gradle.properties
build.gradle Project.toml mix.exs Chart.yaml pom.xml meson.build shard.yml
v.mod vpkg.json build.sbt daml.yaml pubspec.yaml DESCRIPTION galaxy.yml'

pkg=''
if [ "$in_repo" = true ]; then
  cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/pkg-versions.tsv"
  tab="$(printf '\t')"
  nl="$(printf '\nx')" nl="${nl%x}"
  d="$pwd_p"
  while :; do
    set --
    # The unquoted expansion is deliberate: the list word-splits on spaces.
    # shellcheck disable=SC2086
    for m in $PKG_MANIFESTS; do
      [ -f "$d/$m" ] && set -- "$@" "$d/$m"
    done
    set +f
    for m in "$d"/*.nimble; do # nim is the one glob-named manifest
      [ -f "$m" ] && set -- "$@" "$m"
    done
    set -f
    if [ $# -gt 0 ]; then
      key="$(stat -nf '%N=%m;' -- "$@" 2>/dev/null)"
      val='' hit=false
      if [ -f "$cache_file" ]; then
        while IFS="$tab" read -r cdir ckey cval; do
          if [ "$cdir" = "$d" ]; then
            [ "$ckey" = "$key" ] && {
              hit=true
              val="$cval"
            }
            break
          fi
        done <"$cache_file"
      fi
      if [ "$hit" = false ]; then
        val="$(cd "$d" && starship module package 2>/dev/null)"
        val="${val%%"$nl"*}"
        cache_dir="${cache_file%/*}"
        mkdir -p "$cache_dir"
        tmpf="$(mktemp "$cache_dir/.pkg-versions.XXXXXX")" && {
          {
            if [ -f "$cache_file" ]; then
              while IFS= read -r cline; do
                case "$cline" in
                "$d$tab"*) ;;
                *) printf '%s\n' "$cline" ;;
                esac
              done <"$cache_file"
            fi
            printf '%s\t%s\t%s\n' "$d" "$key" "$val"
          } >"$tmpf"
          mv -f "$tmpf" "$cache_file"
        }
      fi
      if [ -n "$val" ]; then
        pkg="$val"
        break
      fi
    fi
    [ "$d" = "$top" ] && break
    case "$d" in */*) d="${d%/*}" ;; *) break ;; esac
    [ -n "$d" ] || break
  done
fi
if [ -n "$pkg" ]; then
  emit PKG "$pkg"
fi
