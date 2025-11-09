#!/usr/bin/env zsh
# Generate color palette database for pokemon-colorscripts
# - Prominent: Most saturated + bright (dark bg) or saturated + dark (light bg) + FREQUENT
# - Bright:    Lightest with minimal color (dark bg) or darkest with minimal color (light bg)
# - Dim:       Grayscale or desaturated for secondary text
#
# All selections favor colors that appear frequently in the sprite for cleaner look.
# Outputs Lua table entry, optionally updating the database file.

# ------------------------- Strict mode & env -------------------------
set -eu
set -o pipefail

# Ensure /usr/local/bin is on PATH if it exists (macOS/Homebrew default)
[[ -d /usr/local/bin ]] && PATH="/usr/local/bin:$PATH"
export PATH

# ------------------------- Usage & helpers --------------------------
usage() {
  cat <<'EOF'
Usage: generate-pokemon-colors <pokemon_name> [--shiny|-s] [--form|-f FORM] [--update-db]
       generate-pokemon-colors --clear  # Clear all entries from database

Examples:
  generate-pokemon-colors pikachu
  generate-pokemon-colors snorlax --shiny
  generate-pokemon-colors meowth --form alola
  generate-pokemon-colors bulbasaur --update-db  # Updates the lua database file
  generate-pokemon-colors --clear                # Clears all pokemon entries

Flags:
  --update-db  Update nvim/lua/custom/visual/pokemon-colors.lua with generated entry
  --clear      Clear all pokemon entries from the database file
EOF
  exit 1
}

fail() { print -r -- "Error: $*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command '$1' not found in PATH"
}

# Perl math wrapper (replaces bc for cross-platform compatibility)
perlcalc() { perl -e "print ($*)"; }

# Integer abs
iabs() { local x=$1; (( x < 0 )) && x=$(( -x )); print -r -- "$x"; }

# ------------------------- Args -------------------------------------
POKEMON_NAME=""
SHINY=0
FORM_VALUE=""
UPDATE_DB=0
CLEAR_DB=0

[[ $# -eq 0 ]] && usage
while [[ $# -gt 0 ]]; do
  case "$1" in
    --shiny|-s) SHINY=1; shift ;;
    --form|-f)
      [[ -n ${2-} ]] || { print -r -- "Error: --form needs a value"; usage; }
      FORM_VALUE="$2"; shift 2 ;;
    --update-db) UPDATE_DB=1; shift ;;
    --clear) CLEAR_DB=1; shift ;;
    --help|-h) usage ;;
    -*)
      fail "Unknown flag '$1'"
      ;;
    *)
      if [[ -z "$POKEMON_NAME" ]]; then
        POKEMON_NAME="$1"; shift
      else
        fail "Unexpected argument '$1'"
      fi
      ;;
  esac
done

# Handle clear mode - doesn't need a pokemon name
if (( CLEAR_DB )); then
  SCRIPT_DIR="${0:A:h}"
  DB_FILE="${SCRIPT_DIR}/pokemon-colors.lua"

  if [[ ! -f "$DB_FILE" ]]; then
    fail "Database file not found: $DB_FILE"
  fi

  # Create a new empty database file with just the structure
  print -r -- "return {" > "$DB_FILE"
  print -r -- "}" >> "$DB_FILE"

  print -r -- "Cleared all pokemon entries from $DB_FILE"
  exit 0
fi

[[ -n "$POKEMON_NAME" ]] || usage

# ------------------------- Dependencies -----------------------------
need pokemon-colorscripts
need perl
need sort
need awk

# ------------------------- Run command ------------------------------
# Build command as an array (zsh: no word-splitting issues)
typeset -a cmd
cmd=(pokemon-colorscripts -n "$POKEMON_NAME" --no-title)
(( SHINY ))      && cmd+=("--shiny")
[[ -n "$FORM_VALUE" ]] && cmd+=("--form" "$FORM_VALUE")

# Capture output; don't abort if pokemon-colorscripts returns nonzero
OUTPUT="$("${cmd[@]}" 2>&1 || true)"

# ------------------------- Extract colors (order-preserving + frequency) --------
# Match ANSI 38;2;R;G;B or 48;2;R;G;B, preserve all occurrences for frequency
ALL_COLORS_RAW=$(
  print -r -- "$OUTPUT" \
  | perl -ne 'while(/[34]8;2;(\d+);(\d+);(\d+)/g){print "$1,$2,$3\n"}'
)

[[ -n "$ALL_COLORS_RAW" ]] || fail "No colors found in pokemon-colorscripts output for '$POKEMON_NAME'"

# Total occurrences for percentage calculation
TOTAL_COLOR_COUNT=$(print -r -- "$ALL_COLORS_RAW" | wc -l | tr -d ' ')

# Get unique colors with counts, sorted by frequency (descending)
COLORS_WITH_COUNTS=$(print -r -- "$ALL_COLORS_RAW" | sort | uniq -c | sort -rn)

# Extract unique colors in order-preserving manner (first occurrence)
UNIQUE_COLORS=$(print -r -- "$ALL_COLORS_RAW" | awk '!seen[$0]++')

# ------------------------- Color math -------------------------------
# Luminance (0..255) – simple weighted sRGB (fast, stable)
calc_luminance() {
  local r=$1 g=$2 b=$3
  perlcalc "0.299*$r + 0.587*$g + 0.114*$b"
}

# HSL saturation percent (0..100), computed on 0..1 scaled channels
# S = 0 if delta==0 else delta / (1 - |2L - 1|)
calc_saturation() {
  local r=$1 g=$2 b=$3
  # Use perl for all the calculations including max/min/abs
  perl -e '
    use strict;
    use List::Util qw(max min);
    my ($r, $g, $b) = @ARGV;
    my ($rf, $gf, $bf) = ($r/255, $g/255, $b/255);
    my $max = max($rf, $gf, $bf);
    my $min = min($rf, $gf, $bf);
    my $delta = $max - $min;

    if ($delta == 0) {
      print "0";
      exit;
    }

    my $lightness = ($max + $min) / 2;
    my $denom = 1 - abs(2 * $lightness - 1);

    if ($denom == 0) {
      print "0";
      exit;
    }

    my $sat = ($delta / $denom) * 100;
    # clamp
    $sat = 0 if $sat < 0;
    $sat = 100 if $sat > 100;
    printf "%.2f", $sat;
  ' "$r" "$g" "$b"
}

# HSL hue (0..360 degrees), calculated from RGB
# Returns hue angle in degrees, or 0 if no hue (grayscale)
calc_hue() {
  local r=$1 g=$2 b=$3
  perl -e '
    use strict;
    use List::Util qw(max min);
    my ($r, $g, $b) = @ARGV;
    my ($rf, $gf, $bf) = ($r/255, $g/255, $b/255);
    my $max = max($rf, $gf, $bf);
    my $min = min($rf, $gf, $bf);
    my $delta = $max - $min;

    if ($delta == 0) {
      print "0";  # No hue for grayscale
      exit;
    }

    my $hue = 0;
    if ($max == $rf) {
      $hue = 60 * ((($gf - $bf) / $delta) % 6);
    } elsif ($max == $gf) {
      $hue = 60 * ((($bf - $rf) / $delta) + 2);
    } else {
      $hue = 60 * ((($rf - $gf) / $delta) + 4);
    }

    # Normalize to 0..360
    $hue += 360 if $hue < 0;
    printf "%.2f", $hue;
  ' "$r" "$g" "$b"
}

# Calculate minimum angular distance between two hues (in degrees)
# Returns value between 0 and 180 degrees
calc_hue_distance() {
  local hue1=$1 hue2=$2
  perlcalc "do { my \$d = abs($hue1 - $hue2); \$d > 180 ? 360 - \$d : \$d }"
}

# Grayscale check: all components within 15
is_grayscale() {
  local r=$1 g=$2 b=$3
  local d1 d2 d3
  d1=$(iabs $(( r - g )))
  d2=$(iabs $(( g - b )))
  d3=$(iabs $(( r - b )))
  (( d1 <= 15 && d2 <= 15 && d3 <= 15 )) && return 0 || return 1
}

# RGB -> #RRGGBB
rgb_to_hex() { printf "#%02X%02X%02X" "$1" "$2" "$3"; }

# Get frequency percentage for a color
get_color_percentage() {
  local color=$1
  local count=$(print -r -- "$COLORS_WITH_COUNTS" | grep "^[[:space:]]*[0-9]*[[:space:]]*$color$" | awk '{print $1}')
  if [[ -z "$count" ]]; then
    print -r -- "0"
  else
    perlcalc "($count * 100.0) / $TOTAL_COLOR_COUNT"
  fi
}

# ------------------------- Build arrays -----------------------------
typeset -a ALL_COLORS  # "r,g,b"
typeset -a LUM         # numeric strings
typeset -a SAT         # numeric strings
typeset -a PCT         # percentage of sprite
typeset -a IS_GRAY     # "0"/"1"
typeset -a HEXS        # "#RRGGBB"

# Read UNIQUE_COLORS lines: r,g,b
while IFS=',' read -r r g b; do
  # sanity clamp [0,255]
  (( r < 0 )) && r=0; (( r > 255 )) && r=255
  (( g < 0 )) && g=0; (( g > 255 )) && g=255
  (( b < 0 )) && b=0; (( b > 255 )) && b=255

  local_lum="$(calc_luminance "$r" "$g" "$b")"
  local_sat="$(calc_saturation "$r" "$g" "$b")"
  local_pct="$(get_color_percentage "$r,$g,$b")"

  ALL_COLORS+=("$r,$g,$b")
  LUM+=("$local_lum")
  SAT+=("$local_sat")
  PCT+=("$local_pct")
  if is_grayscale "$r" "$g" "$b"; then
    IS_GRAY+=("1")
  else
    IS_GRAY+=("0")
  fi
  HEXS+=("$(rgb_to_hex "$r" "$g" "$b")")
done <<< "$UNIQUE_COLORS"

# ------------------------- Selection helpers ------------------------
# Numeric comparison helper using perl
perlcmp() {
  # Returns: 0 if $1 > $2, 1 otherwise
  perl -e 'exit($ARGV[0] > $ARGV[1] ? 0 : 1)' "$1" "$2"
}

# Deterministic tie-breaker: prefer higher score, then higher frequency, then lexicographically smallest HEX
better_score() {
  # args: scoreA scoreB pctA pctB hexA hexB -> return 0 if A > B, 1 otherwise
  local a=$1 b=$2 pa=$3 pb=$4 ha=$5 hb=$6
  if perlcmp "$a" "$b"; then return 0
  elif perlcmp "$b" "$a"; then return 1
  else
    # Tie on score, check frequency
    if perlcmp "$pa" "$pb"; then return 0
    elif perlcmp "$pb" "$pa"; then return 1
    else
      # Tie on frequency, use hex
      [[ "$ha" < "$hb" ]] && return 0 || return 1
    fi
  fi
}

require_idx() { local idx=$1 label=$2; [[ $idx -ge 0 ]] || fail "No suitable color found for '$label'"; }

# ------------------------- Pickers (dark bg) -------------------
# Dark prominent: Most saturated + bright + FREQUENT
# "the thing that has the absolute most color AND brightness" + takes up a lot of image
DARK_PROMINENT_IDX=-1; DARK_PROMINENT_SCORE="0"
for i in {1..$#ALL_COLORS}; do
  IFS=',' read -r r g b <<< "${ALL_COLORS[$i]}"
  local_sat="${SAT[$i]}"
  local_lum="${LUM[$i]}"
  local_pct="${PCT[$i]}"

  # Need high saturation, brightness, and frequency
  # Avoid very dark colors (need contrast on dark bg)
  if perlcmp "$local_lum" "50" && perlcmp "$local_sat" "30" && perlcmp "$local_pct" "2"; then
    # Score: saturation + brightness + frequency bonus
    # Heavily weight saturation (main color characteristic)
    # Weight brightness (needs to pop on dark bg)
    # Weight frequency (should be a main color, not accent)
    score="$(perlcalc "($local_sat * 2) + $local_lum + ($local_pct * 5)")"
    if [[ $DARK_PROMINENT_IDX -lt 0 ]] \
       || better_score "$score" "$DARK_PROMINENT_SCORE" "$local_pct" "${PCT[$DARK_PROMINENT_IDX]}" "${HEXS[$i]}" "${HEXS[$DARK_PROMINENT_IDX]}"; then
      DARK_PROMINENT_SCORE="$score"; DARK_PROMINENT_IDX=$i
    fi
  fi
done
# Progressive fallback: if no color met 2% threshold, remove frequency requirement
# This helps pokemon with predominantly black/white colors
if [[ $DARK_PROMINENT_IDX -lt 0 ]]; then
  for i in {1..$#ALL_COLORS}; do
    IFS=',' read -r r g b <<< "${ALL_COLORS[$i]}"
    local_sat="${SAT[$i]}"
    local_lum="${LUM[$i]}"
    local_pct="${PCT[$i]}"
    # Same criteria but NO frequency requirement
    if perlcmp "$local_lum" "50" && perlcmp "$local_sat" "30"; then
      score="$(perlcalc "($local_sat * 2) + $local_lum")"
      if [[ $DARK_PROMINENT_IDX -lt 0 ]] \
         || better_score "$score" "$DARK_PROMINENT_SCORE" "$local_pct" "${PCT[$DARK_PROMINENT_IDX]}" "${HEXS[$i]}" "${HEXS[$DARK_PROMINENT_IDX]}"; then
        DARK_PROMINENT_SCORE="$score"; DARK_PROMINENT_IDX=$i
      fi
    fi
  done
fi

# Dark bright: Highest brightness, minimal color
# "most brightness, least color"
DARK_BRIGHT_IDX=-1; DARK_BRIGHT_SCORE="0"
for i in {1..$#ALL_COLORS}; do
  [[ ${IS_GRAY[$i]} -eq 1 ]] && continue
  local_sat="${SAT[$i]}"; local_lum="${LUM[$i]}"; local_pct="${PCT[$i]}"
  # Want bright but with some color (not pure white)
  # Low saturation, high luminance
  if (( $(perlcalc "$local_lum > 120 && $local_lum < 250 && $local_sat > 10 && $local_sat < 60") )); then
    # Score: brightness - saturation (NO frequency requirement - allows rare accent colors)
    score="$(perlcalc "$local_lum - ($local_sat * 0.5)")"
    if [[ $DARK_BRIGHT_IDX -lt 0 ]] \
       || better_score "$score" "$DARK_BRIGHT_SCORE" "$local_pct" "${PCT[$DARK_BRIGHT_IDX]}" "${HEXS[$i]}" "${HEXS[$DARK_BRIGHT_IDX]}"; then
      DARK_BRIGHT_SCORE="$score"; DARK_BRIGHT_IDX=$i
    fi
  fi
done
# lenient fallback
if [[ $DARK_BRIGHT_IDX -lt 0 ]]; then
  for i in {1..$#ALL_COLORS}; do
    [[ ${IS_GRAY[$i]} -eq 1 ]] && continue
    local_sat="${SAT[$i]}"; local_lum="${LUM[$i]}"; local_pct="${PCT[$i]}"
    if (( $(perlcalc "$local_lum > 100 && $local_sat > 5") )); then
      score="$(perlcalc "$local_lum")"
      if [[ $DARK_BRIGHT_IDX -lt 0 ]] \
         || better_score "$score" "$DARK_BRIGHT_SCORE" "$local_pct" "${PCT[$DARK_BRIGHT_IDX]}" "${HEXS[$i]}" "${HEXS[$DARK_BRIGHT_IDX]}"; then
        DARK_BRIGHT_SCORE="$score"; DARK_BRIGHT_IDX=$i
      fi
    fi
  done
fi
# Fallback for predominantly white/black pokemon: allow bright whites
if [[ $DARK_BRIGHT_IDX -lt 0 ]]; then
  for i in {1..$#ALL_COLORS}; do
    local_lum="${LUM[$i]}"
    local_pct="${PCT[$i]}"
    # Accept bright colors (lum > 200) regardless of saturation
    if (( $(perlcalc "$local_lum > 200") )); then
      score="$local_lum"
      if [[ $DARK_BRIGHT_IDX -lt 0 ]] \
         || better_score "$score" "$DARK_BRIGHT_SCORE" "$local_pct" "${PCT[$DARK_BRIGHT_IDX]}" "${HEXS[$i]}" "${HEXS[$DARK_BRIGHT_IDX]}"; then
        DARK_BRIGHT_SCORE="$score"; DARK_BRIGHT_IDX=$i
      fi
    fi
  done
fi
# Ultimate fallback: hardcoded light gray (for completely monochrome pokemon)
if [[ $DARK_BRIGHT_IDX -lt 0 ]]; then
  # Add a synthetic color entry for the fallback
  ALL_COLORS+=("224,224,224")  # #E0E0E0
  HEXS+=("#E0E0E0")
  SAT+=("0")
  LUM+=("224")
  PCT+=("0")
  IS_GRAY+=("1")
  DARK_BRIGHT_IDX=${#ALL_COLORS}
fi

# Dark dim: Grayscale, mid-range brightness, prefer frequent
DARK_DIM_IDX=-1; DARK_DIM_SCORE="0"
for i in {1..$#ALL_COLORS}; do
  [[ ${IS_GRAY[$i]} -eq 1 ]] || continue
  local_lum="${LUM[$i]}"; local_pct="${PCT[$i]}"
  # prefer mid-gray (80..150), peak at 115
  if (( $(perlcalc "$local_lum > 80 && $local_lum < 150") )); then
    score="$(perlcalc "150 - (($local_lum - 115)**2)/10 + ($local_pct * 2)")"
    if [[ $DARK_DIM_IDX -lt 0 ]] \
       || better_score "$score" "$DARK_DIM_SCORE" "$local_pct" "${PCT[$DARK_DIM_IDX]}" "${HEXS[$i]}" "${HEXS[$DARK_DIM_IDX]}"; then
      DARK_DIM_SCORE="$score"; DARK_DIM_IDX=$i
    fi
  fi
done
# fallback: any grayscale
if [[ $DARK_DIM_IDX -lt 0 ]]; then
  for i in {1..$#ALL_COLORS}; do
    [[ ${IS_GRAY[$i]} -eq 1 ]] || continue
    local_lum="${LUM[$i]}"; local_pct="${PCT[$i]}"
    if (( $(perlcalc "$local_lum > 40 && $local_lum < 200") )); then
      score="$(perlcalc "100 - (($local_lum - 115)**2)/50 + ($local_pct * 2)")"
      if [[ $DARK_DIM_IDX -lt 0 ]] \
         || better_score "$score" "$DARK_DIM_SCORE" "$local_pct" "${PCT[$DARK_DIM_IDX]}" "${HEXS[$i]}" "${HEXS[$DARK_DIM_IDX]}"; then
        DARK_DIM_SCORE="$score"; DARK_DIM_IDX=$i
      fi
    fi
  done
fi
# fallback: desaturated color
if [[ $DARK_DIM_IDX -lt 0 ]]; then
  for i in {1..$#ALL_COLORS}; do
    local_sat="${SAT[$i]}"; local_lum="${LUM[$i]}"; local_pct="${PCT[$i]}"
    if (( $(perlcalc "$local_lum > 60 && $local_lum < 180 && $local_sat < 30") )); then
      score="$(perlcalc "(100 - $local_sat) + ($local_pct * 2)")"
      if [[ $DARK_DIM_IDX -lt 0 ]] \
         || better_score "$score" "$DARK_DIM_SCORE" "$local_pct" "${PCT[$DARK_DIM_IDX]}" "${HEXS[$i]}" "${HEXS[$DARK_DIM_IDX]}"; then
        DARK_DIM_SCORE="$score"; DARK_DIM_IDX=$i
      fi
    fi
  done
fi

# ------------------------- Pickers (light bg) ------------------
# Light prominent: Most saturated + dark enough to show + FREQUENT
# "most color, but not too bright such as not to show up properly on light background"
LIGHT_PROMINENT_IDX=-1; LIGHT_PROMINENT_SCORE="0"
for i in {1..$#ALL_COLORS}; do
  local_sat="${SAT[$i]}"; local_lum="${LUM[$i]}"; local_pct="${PCT[$i]}"
  # saturated + sufficiently dark + frequent
  if (( $(perlcalc "$local_lum < 200 && $local_sat > 30 && $local_pct > 2") )); then
    # Score: saturation + darkness + frequency
    score="$(perlcalc "($local_sat * 2) + (255 - $local_lum) + ($local_pct * 5)")"
    if [[ $LIGHT_PROMINENT_IDX -lt 0 ]] \
       || better_score "$score" "$LIGHT_PROMINENT_SCORE" "$local_pct" "${PCT[$LIGHT_PROMINENT_IDX]}" "${HEXS[$i]}" "${HEXS[$LIGHT_PROMINENT_IDX]}"; then
      LIGHT_PROMINENT_SCORE="$score"; LIGHT_PROMINENT_IDX=$i
    fi
  fi
done
# Progressive fallback: if no color met 2% threshold, remove frequency requirement
if [[ $LIGHT_PROMINENT_IDX -lt 0 ]]; then
  for i in {1..$#ALL_COLORS}; do
    local_sat="${SAT[$i]}"; local_lum="${LUM[$i]}"; local_pct="${PCT[$i]}"
    # Same criteria but NO frequency requirement
    if (( $(perlcalc "$local_lum < 200 && $local_sat > 30") )); then
      score="$(perlcalc "($local_sat * 2) + (255 - $local_lum)")"
      if [[ $LIGHT_PROMINENT_IDX -lt 0 ]] \
         || better_score "$score" "$LIGHT_PROMINENT_SCORE" "$local_pct" "${PCT[$LIGHT_PROMINENT_IDX]}" "${HEXS[$i]}" "${HEXS[$LIGHT_PROMINENT_IDX]}"; then
        LIGHT_PROMINENT_SCORE="$score"; LIGHT_PROMINENT_IDX=$i
      fi
    fi
  done
fi

# Light bright: Darkest color with minimal saturation
# "least color, most dark"
LIGHT_BRIGHT_IDX=-1; LIGHT_BRIGHT_SCORE="0"
for i in {1..$#ALL_COLORS}; do
  [[ ${IS_GRAY[$i]} -eq 1 ]] && continue
  local_sat="${SAT[$i]}"; local_lum="${LUM[$i]}"; local_pct="${PCT[$i]}"
  # moderate saturation, dark for contrast
  if (( $(perlcalc "$local_lum > 40 && $local_lum < 140 && $local_sat > 20 && $local_sat < 70") )); then
    # Score: darkness - saturation (NO frequency requirement - allows rare accent colors)
    score="$(perlcalc "(255 - $local_lum) - ($local_sat * 0.5)")"
    if [[ $LIGHT_BRIGHT_IDX -lt 0 ]] \
       || better_score "$score" "$LIGHT_BRIGHT_SCORE" "$local_pct" "${PCT[$LIGHT_BRIGHT_IDX]}" "${HEXS[$i]}" "${HEXS[$LIGHT_BRIGHT_IDX]}"; then
      LIGHT_BRIGHT_SCORE="$score"; LIGHT_BRIGHT_IDX=$i
    fi
  fi
done
# lenient fallback
if [[ $LIGHT_BRIGHT_IDX -lt 0 ]]; then
  for i in {1..$#ALL_COLORS}; do
    [[ ${IS_GRAY[$i]} -eq 1 ]] && continue
    local_sat="${SAT[$i]}"; local_lum="${LUM[$i]}"; local_pct="${PCT[$i]}"
    if (( $(perlcalc "$local_lum < 150 && $local_sat > 15") )); then
      score="$(perlcalc "(255 - $local_lum)")"
      if [[ $LIGHT_BRIGHT_IDX -lt 0 ]] \
         || better_score "$score" "$LIGHT_BRIGHT_SCORE" "$local_pct" "${PCT[$LIGHT_BRIGHT_IDX]}" "${HEXS[$i]}" "${HEXS[$LIGHT_BRIGHT_IDX]}"; then
        LIGHT_BRIGHT_SCORE="$score"; LIGHT_BRIGHT_IDX=$i
      fi
    fi
  done
fi
# Fallback for predominantly white/black pokemon: allow dark grays/blacks
if [[ $LIGHT_BRIGHT_IDX -lt 0 ]]; then
  for i in {1..$#ALL_COLORS}; do
    local_lum="${LUM[$i]}"
    local_pct="${PCT[$i]}"
    # Accept dark colors (lum < 50) regardless of saturation
    if (( $(perlcalc "$local_lum < 50") )); then
      score="$(perlcalc "255 - $local_lum")"
      if [[ $LIGHT_BRIGHT_IDX -lt 0 ]] \
         || better_score "$score" "$LIGHT_BRIGHT_SCORE" "$local_pct" "${PCT[$LIGHT_BRIGHT_IDX]}" "${HEXS[$i]}" "${HEXS[$LIGHT_BRIGHT_IDX]}"; then
        LIGHT_BRIGHT_SCORE="$score"; LIGHT_BRIGHT_IDX=$i
      fi
    fi
  done
fi
# Ultimate fallback: hardcoded dark gray (for completely monochrome pokemon)
if [[ $LIGHT_BRIGHT_IDX -lt 0 ]]; then
  # Add a synthetic color entry for the fallback
  ALL_COLORS+=("42,42,42")  # #2A2A2A
  HEXS+=("#2A2A2A")
  SAT+=("0")
  LUM+=("42")
  PCT+=("0")
  IS_GRAY+=("1")
  LIGHT_BRIGHT_IDX=${#ALL_COLORS}
fi

# Light dim: Grayscale, mid-to-light range, prefer frequent
LIGHT_DIM_IDX=-1; LIGHT_DIM_SCORE="0"
for i in {1..$#ALL_COLORS}; do
  [[ ${IS_GRAY[$i]} -eq 1 ]] || continue
  local_lum="${LUM[$i]}"; local_pct="${PCT[$i]}"
  # mid-gray for light bg (100..180), peak at 140
  if (( $(perlcalc "$local_lum > 100 && $local_lum < 180") )); then
    score="$(perlcalc "150 - (($local_lum - 140)**2)/10 + ($local_pct * 2)")"
    if [[ $LIGHT_DIM_IDX -lt 0 ]] \
       || better_score "$score" "$LIGHT_DIM_SCORE" "$local_pct" "${PCT[$LIGHT_DIM_IDX]}" "${HEXS[$i]}" "${HEXS[$LIGHT_DIM_IDX]}"; then
      LIGHT_DIM_SCORE="$score"; LIGHT_DIM_IDX=$i
    fi
  fi
done
# fallback: any grayscale
if [[ $LIGHT_DIM_IDX -lt 0 ]]; then
  for i in {1..$#ALL_COLORS}; do
    [[ ${IS_GRAY[$i]} -eq 1 ]] || continue
    local_lum="${LUM[$i]}"; local_pct="${PCT[$i]}"
    if (( $(perlcalc "$local_lum > 60 && $local_lum < 220") )); then
      score="$(perlcalc "100 - (($local_lum - 140)**2)/50 + ($local_pct * 2)")"
      if [[ $LIGHT_DIM_IDX -lt 0 ]] \
         || better_score "$score" "$LIGHT_DIM_SCORE" "$local_pct" "${PCT[$LIGHT_DIM_IDX]}" "${HEXS[$i]}" "${HEXS[$LIGHT_DIM_IDX]}"; then
        LIGHT_DIM_SCORE="$score"; LIGHT_DIM_IDX=$i
      fi
    fi
  done
fi
# fallback: desaturated color
if [[ $LIGHT_DIM_IDX -lt 0 ]]; then
  for i in {1..$#ALL_COLORS}; do
    local_sat="${SAT[$i]}"; local_lum="${LUM[$i]}"; local_pct="${PCT[$i]}"
    if (( $(perlcalc "$local_lum > 80 && $local_lum < 200 && $local_sat < 30") )); then
      score="$(perlcalc "(100 - $local_sat) + ($local_pct * 2)")"
      if [[ $LIGHT_DIM_IDX -lt 0 ]] \
         || better_score "$score" "$LIGHT_DIM_SCORE" "$local_pct" "${PCT[$LIGHT_DIM_IDX]}" "${HEXS[$i]}" "${HEXS[$LIGHT_DIM_IDX]}"; then
        LIGHT_DIM_SCORE="$score"; LIGHT_DIM_IDX=$i
      fi
    fi
  done
fi

# ------------------------- Color Differentiation --------------------
# Ensure prominent and bright colors are visually distinct (min 60° hue distance)
# This prevents similar-looking colors from being used for both roles

# Helper: Check and adjust color pair for sufficient differentiation
adjust_color_pair() {
  local prom_idx_var=$1  # Name of variable holding prominent index
  local bright_idx_var=$2  # Name of variable holding bright index
  local mode=$3  # "dark" or "light"

  eval "local prom_idx=\$$prom_idx_var"
  eval "local bright_idx=\$$bright_idx_var"

  # Skip if either color not selected
  [[ $prom_idx -lt 0 || $bright_idx -lt 0 ]] && return

  # Get RGB values
  IFS=',' read -r prom_r prom_g prom_b <<< "${ALL_COLORS[$prom_idx]}"
  IFS=',' read -r bright_r bright_g bright_b <<< "${ALL_COLORS[$bright_idx]}"

  # Calculate hues
  local prom_hue=$(calc_hue "$prom_r" "$prom_g" "$prom_b")
  local bright_hue=$(calc_hue "$bright_r" "$bright_g" "$bright_b")

  # Calculate hue distance
  local hue_dist=$(calc_hue_distance "$prom_hue" "$bright_hue")

  # If hue distance is sufficient, no adjustment needed
  (( $(perlcalc "$hue_dist >= 60") )) && return

  # Colors are too similar - adjust based on saturation levels
  local prom_sat="${SAT[$prom_idx]}"
  local bright_sat="${SAT[$bright_idx]}"

  # Case 1: Both have low saturation (< 30) - switch prominent to high-saturation color
  if (( $(perlcalc "$prom_sat < 30 && $bright_sat < 30") )); then
    # Find most frequent high-saturation color for prominent
    local new_prom_idx=-1
    local max_pct="0"
    for i in {1..$#ALL_COLORS}; do
      local i_sat="${SAT[$i]}"
      local i_pct="${PCT[$i]}"
      # Must be high saturation and different from current bright
      if (( $(perlcalc "$i_sat >= 30") )) && [[ $i -ne $bright_idx ]]; then
        if perlcmp "$i_pct" "$max_pct"; then
          max_pct="$i_pct"
          new_prom_idx=$i
        fi
      fi
    done
    # Update prominent if we found a better option
    if [[ $new_prom_idx -ge 0 ]]; then
      eval "$prom_idx_var=$new_prom_idx"
    fi

  # Case 2: Both have high saturation (≥ 30) - switch bright to low-saturation color
  elif (( $(perlcalc "$prom_sat >= 30 && $bright_sat >= 30") )); then
    # Find best low-saturation color for bright
    local new_bright_idx=-1
    local best_score="0"
    for i in {1..$#ALL_COLORS}; do
      [[ ${IS_GRAY[$i]} -eq 1 ]] && continue  # Skip grayscale
      local i_sat="${SAT[$i]}"
      local i_lum="${LUM[$i]}"
      local i_pct="${PCT[$i]}"
      # Must be low saturation and different from current prominent
      if (( $(perlcalc "$i_sat < 30") )) && [[ $i -ne $prom_idx ]]; then
        # Score based on mode (similar to bright selection logic)
        local score
        if [[ $mode == "dark" ]]; then
          score="$(perlcalc "$i_lum - ($i_sat * 0.5)")"  # Favor brightness
        else
          score="$(perlcalc "(255 - $i_lum) - ($i_sat * 0.5)")"  # Favor darkness
        fi
        if [[ $new_bright_idx -lt 0 ]] || perlcmp "$score" "$best_score"; then
          best_score="$score"
          new_bright_idx=$i
        fi
      fi
    done
    # Update bright if we found a better option
    if [[ $new_bright_idx -ge 0 ]]; then
      eval "$bright_idx_var=$new_bright_idx"
    fi
  fi
}

# Apply differentiation to both dark and light modes
adjust_color_pair "DARK_PROMINENT_IDX" "DARK_BRIGHT_IDX" "dark"
adjust_color_pair "LIGHT_PROMINENT_IDX" "LIGHT_BRIGHT_IDX" "light"

# ------------------------- Guard selection --------------------------
require_idx "$DARK_PROMINENT_IDX"   "dark.prominent"
require_idx "$DARK_BRIGHT_IDX"      "dark.bright"
require_idx "$DARK_DIM_IDX"         "dark.dim"
require_idx "$LIGHT_PROMINENT_IDX"  "light.prominent"
require_idx "$LIGHT_BRIGHT_IDX"     "light.bright"
require_idx "$LIGHT_DIM_IDX"        "light.dim"

# ------------------------- Build key --------------------------------
KEY="$POKEMON_NAME"
(( SHINY )) && KEY="${KEY}-shiny"
if [[ -n "$FORM_VALUE" ]]; then
  # normalize: lower-kebab
  KEY="${KEY}-$(print -r -- "$FORM_VALUE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
fi

# ------------------------- Emit Lua --------------------------------
# Selected color hexes
IFS=',' read -r r g b <<< "${ALL_COLORS[$DARK_PROMINENT_IDX]}"; DARK_PROMINENT=$(rgb_to_hex "$r" "$g" "$b")
IFS=',' read -r r g b <<< "${ALL_COLORS[$DARK_BRIGHT_IDX]}";    DARK_BRIGHT=$(rgb_to_hex "$r" "$g" "$b")
IFS=',' read -r r g b <<< "${ALL_COLORS[$DARK_DIM_IDX]}";       DARK_DIM=$(rgb_to_hex "$r" "$g" "$b")
IFS=',' read -r r g b <<< "${ALL_COLORS[$LIGHT_PROMINENT_IDX]}"; LIGHT_PROMINENT=$(rgb_to_hex "$r" "$g" "$b")
IFS=',' read -r r g b <<< "${ALL_COLORS[$LIGHT_BRIGHT_IDX]}";    LIGHT_BRIGHT=$(rgb_to_hex "$r" "$g" "$b")
IFS=',' read -r r g b <<< "${ALL_COLORS[$LIGHT_DIM_IDX]}";       LIGHT_DIM=$(rgb_to_hex "$r" "$g" "$b")

# Build lua entry with metadata for reliable parsing
# The _meta table stores the original components so parsers don't need to guess
# how to split keys containing natural dashes (e.g., "ho-oh", "porygon-z")
LUA_ENTRY=$(cat <<LUA_EOF
  ["$KEY"] = {
    _meta = {
      name = "$POKEMON_NAME",
      is_shiny = $( (( SHINY )) && print -r -- "true" || print -r -- "false" ),
      form = $( [[ -n "$FORM_VALUE" ]] && print -r -- "\"$FORM_VALUE\"" || print -r -- "nil" ),
    },
    colors = {
$(for hex in "${HEXS[@]}"; do print -r -- "      \"$hex\","; done)
    },
    dark = {
      prominent = "$DARK_PROMINENT",
      bright = "$DARK_BRIGHT",
      dim = "$DARK_DIM",
    },
    light = {
      prominent = "$LIGHT_PROMINENT",
      bright = "$LIGHT_BRIGHT",
      dim = "$LIGHT_DIM",
    },
  },
LUA_EOF
)

# If --update-db flag is set, update the lua file
if (( UPDATE_DB )); then
  # Find the database file (in the same directory as this script)
  SCRIPT_DIR="${0:A:h}"  # Get absolute directory of this script
  DB_FILE="${SCRIPT_DIR}/pokemon-colors.lua"

  if [[ ! -f "$DB_FILE" ]]; then
    fail "Database file not found: $DB_FILE"
  fi

  # Create a temporary file for the updated content
  TEMP_FILE=$(mktemp)
  ENTRY_FILE=$(mktemp)

  # Write the entry to a temp file
  print -r -- "$LUA_ENTRY" > "$ENTRY_FILE"

  # Check if the key already exists in the file
  if grep -q "\\[\"$KEY\"\\]" "$DB_FILE"; then
    # Key exists - replace it
    # Strategy: Skip the old entry block and insert the new one
    awk -v key="$KEY" -v entry_file="$ENTRY_FILE" '
      BEGIN { in_block=0; found=0 }
      /\["/ && $0 ~ "\\[\"" key "\"\\]" {
        in_block=1
        found=1
        # Insert new entry from file
        while ((getline line < entry_file) > 0) {
          print line
        }
        close(entry_file)
        next
      }
      in_block && /^  },/ {
        in_block=0
        next
      }
      !in_block { print }
    ' "$DB_FILE" > "$TEMP_FILE"

    mv "$TEMP_FILE" "$DB_FILE"
    rm "$ENTRY_FILE"
    print -r -- "Updated existing entry for '$KEY' in $DB_FILE"
  else
    # Key doesn't exist - append before closing brace
    # Find the last line with just "}" and insert before it
    awk -v entry_file="$ENTRY_FILE" '
      /^}$/ && !inserted {
        while ((getline line < entry_file) > 0) {
          print line
        }
        close(entry_file)
        inserted=1
      }
      { print }
    ' "$DB_FILE" > "$TEMP_FILE"

    mv "$TEMP_FILE" "$DB_FILE"
    rm "$ENTRY_FILE"
    print -r -- "Added new entry for '$KEY' to $DB_FILE"
  fi
else
  # Just print to stdout
  print -r -- "$LUA_ENTRY"
fi
