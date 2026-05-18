#!/usr/bin/env zsh
# verify.sh — structural check on a NEW skill folder produced by skill-builder.
#
# Usage:
#   tools/verify.sh path/to/new-skill/
#
# Reports `ok` / `warn` / `FAIL` per check. Exits 0 only if every check passes.
# Behavioural correctness is *not* checked here — that's Phases 1–4 of the
# skill-builder flow. This script catches the structural mistakes (missing
# sections, name/folder mismatch, runtime coupling back to skill-builder, etc.)
# that should never make it past scaffolding.
#
# Note: this script will FAIL if pointed at skill-builder/ itself, because
# skill-builder's docs reference `skill-builder/design-system` while documenting
# how new skills should NOT do so. That's expected. The script is for verifying
# skills produced BY skill-builder, not skill-builder itself.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  print -u2 "Usage: $0 <skill-folder>"
  exit 2
fi

SKILL_DIR="${1%/}"
SKILL_NAME="${SKILL_DIR:t}"
SKILL_FILE="$SKILL_DIR/SKILL.md"

PASS=0
FAIL=0
WARN=0

ok() {
  printf "  \e[32mok  \e[0m  %s\n" "$1"
  PASS=$((PASS + 1))
}
nope() {
  printf "  \e[31mFAIL\e[0m  %s\n" "$1"
  FAIL=$((FAIL + 1))
}
warn() {
  printf "  \e[33mwarn\e[0m  %s\n" "$1"
  WARN=$((WARN + 1))
}

print
print "Verifying $SKILL_DIR"
print

# ---- 1. SKILL.md exists -------------------------------------------------

if [[ -f "$SKILL_FILE" ]]; then
  ok "SKILL.md exists"
else
  nope "SKILL.md not found at $SKILL_FILE"
  exit 1
fi

# ---- 2. Frontmatter block ----------------------------------------------
# Extract everything between the first two `---` lines.

FM=$(awk '/^---[[:space:]]*$/{c++; if (c==2) exit; next} c==1' "$SKILL_FILE")

if [[ -z "$FM" ]]; then
  nope "no YAML frontmatter found at top of SKILL.md"
  exit 1
fi
ok "frontmatter block present"

# ---- 3. Required frontmatter fields ------------------------------------

FM_NAME=$(print -- "$FM" | awk -F': *' '/^name:/{print $2; exit}' | tr -d ' "'\''')
if [[ -n "$FM_NAME" ]]; then
  ok "frontmatter has name: $FM_NAME"
else
  nope "frontmatter missing 'name' field"
fi

if print -- "$FM" | grep -qE '^description:'; then
  ok "frontmatter has description"
else
  nope "frontmatter missing 'description' field"
fi

# ---- 4. name == folder name --------------------------------------------

if [[ "$FM_NAME" == "$SKILL_NAME" ]]; then
  ok "name matches folder name"
else
  nope "name '$FM_NAME' does not match folder name '$SKILL_NAME'"
fi

# ---- 5. Required sections ----------------------------------------------

for section in '## How to Run' '## Output Contract'; do
  if grep -qE "^${section}([[:space:]]|$)" "$SKILL_FILE"; then
    ok "section '${section}' present"
  else
    nope "missing required section '${section}'"
  fi
done

# ---- 6. Optional ## Alignment must not be empty if present -------------

if grep -qE '^## Alignment([[:space:]]|$)' "$SKILL_FILE"; then
  ALIGN_BODY=$(awk '
    /^## Alignment([[:space:]]|$)/ { in_section=1; next }
    in_section && /^## / { exit }
    in_section { print }
  ' "$SKILL_FILE" | tr -d '[:space:]')
  if [[ -n "$ALIGN_BODY" ]]; then
    ok "## Alignment section is non-empty"
  else
    nope "## Alignment section exists but is empty (delete the section instead)"
  fi
fi

# ---- 7. SKILL.md size sanity (soft cap) --------------------------------

LINES=$(wc -l < "$SKILL_FILE" | tr -d ' ')
if [[ $LINES -le 200 ]]; then
  ok "SKILL.md is $LINES lines (cap is 200)"
else
  warn "SKILL.md is $LINES lines (over 200 — push depth into references/)"
fi

# ---- 8. No runtime coupling back to skill-builder ----------------------

HITS=$(grep -rEln 'skill-builder/design-system|\.\./skill-builder/' "$SKILL_DIR" 2> /dev/null || true)
if [[ -z "$HITS" ]]; then
  ok "no runtime coupling to skill-builder/"
else
  nope "runtime references to skill-builder/ found in:"
  print -- "$HITS" | sed 's/^/        /'
fi

# ---- Summary -----------------------------------------------------------

print
printf "%d passed, %d failed, %d warned\n" "$PASS" "$FAIL" "$WARN"
[[ $FAIL -eq 0 ]]
