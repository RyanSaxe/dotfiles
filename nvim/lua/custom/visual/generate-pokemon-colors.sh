#!/usr/bin/env zsh
# Generate color palette database for pokemon-colorscripts
# NEW ALGORITHM:
# - Prominent: Most frequent COLORFUL color that pops on the background
# - Bright:    Color most perceptually different from prominent (using Delta E)
# - Dim:       Dullest/most desaturated color that's still readable
#
# All selections use perceptual color science (CIELAB, Delta E 2000) for accuracy.
# Outputs 'fallback' for bright/dim if no suitable color found.

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

# Get colors sorted by frequency (most frequent first) for prominent selection
COLORS_BY_FREQUENCY=$(print -r -- "$COLORS_WITH_COUNTS" | awk '{print $2}')

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

# ------------------------- LAB Color Space & Delta E ----------------
# Convert RGB (0-255) to CIELAB color space
# Returns space-separated "L a b" values
rgb_to_lab() {
  local r=$1 g=$2 b=$3
  perl -e '
    use strict;
    use POSIX qw(pow);

    my ($r, $g, $b) = @ARGV;

    # Convert RGB to linear RGB (gamma correction)
    sub to_linear {
      my $c = shift() / 255.0;
      return $c <= 0.04045 ? $c / 12.92 : pow(($c + 0.055) / 1.055, 2.4);
    }

    my $rl = to_linear($r);
    my $gl = to_linear($g);
    my $bl = to_linear($b);

    # Convert to XYZ (using sRGB D65 illuminant)
    my $x = $rl * 0.4124564 + $gl * 0.3575761 + $bl * 0.1804375;
    my $y = $rl * 0.2126729 + $gl * 0.7151522 + $bl * 0.0721750;
    my $z = $rl * 0.0193339 + $gl * 0.1191920 + $bl * 0.9503041;

    # Normalize by D65 white point
    $x /= 0.95047;
    $y /= 1.00000;
    $z /= 1.08883;

    # Convert to LAB
    sub f {
      my $t = shift;
      return $t > 0.008856 ? pow($t, 1.0/3.0) : (7.787 * $t) + (16.0/116.0);
    }

    my $fx = f($x);
    my $fy = f($y);
    my $fz = f($z);

    my $L = (116.0 * $fy) - 16.0;
    my $a = 500.0 * ($fx - $fy);
    my $b_val = 200.0 * ($fy - $fz);

    printf "%.4f %.4f %.4f", $L, $a, $b_val;
  ' "$r" "$g" "$b"
}

# Calculate Delta E 2000 (perceptual color difference)
# Takes two LAB color strings: "L1 a1 b1" "L2 a2 b2"
# Returns a perceptual distance value (0 = identical, 100 = very different)
calc_delta_e() {
  local lab1=$1 lab2=$2
  perl -e '
    use strict;
    use POSIX qw(pow sqrt atan2 sin cos);

    my @lab1 = split(/\s+/, $ARGV[0]);
    my @lab2 = split(/\s+/, $ARGV[1]);

    my ($L1, $a1, $b1) = @lab1;
    my ($L2, $a2, $b2) = @lab2;

    # Simplified Delta E 2000 calculation
    # (Full implementation is complex; this is a practical approximation)

    my $dL = $L2 - $L1;
    my $da = $a2 - $a1;
    my $db = $b2 - $b1;

    # Chroma
    my $C1 = sqrt($a1*$a1 + $b1*$b1);
    my $C2 = sqrt($a2*$a2 + $b2*$b2);
    my $dC = $C2 - $C1;

    # Hue (approximate)
    my $dH_sq = $da*$da + $db*$db - $dC*$dC;
    $dH_sq = 0 if $dH_sq < 0;  # Avoid sqrt of negative
    my $dH = sqrt($dH_sq);

    # Simplified Delta E (not full CIEDE2000 but good enough)
    my $kL = 1.0;
    my $kC = 1.0;
    my $kH = 1.0;

    my $dE = sqrt(
      pow($dL / $kL, 2) +
      pow($dC / $kC, 2) +
      pow($dH / $kH, 2)
    );

    printf "%.4f", $dE;
  ' "$lab1" "$lab2"
}

# Calculate colorfulness score (for prominent selection)
# High saturation + distance from neutral colors = more colorful
calc_colorfulness() {
  local r=$1 g=$2 b=$3
  local sat=$4  # Pre-calculated saturation

  perl -e '
    use strict;
    use POSIX qw(sqrt pow);

    my ($r, $g, $b, $sat) = @ARGV;

    # Calculate distance from neutral (white/black/gray)
    # Check distance to white (255,255,255), black (0,0,0), and mid-gray (128,128,128)
    sub euclidean_dist {
      my ($r1, $g1, $b1, $r2, $g2, $b2) = @_;
      return sqrt(pow($r1-$r2, 2) + pow($g1-$g2, 2) + pow($b1-$b2, 2));
    }

    my $dist_white = euclidean_dist($r, $g, $b, 255, 255, 255);
    my $dist_black = euclidean_dist($r, $g, $b, 0, 0, 0);
    my $dist_gray = euclidean_dist($r, $g, $b, 128, 128, 128);

    # Minimum distance from neutrals (normalized to 0-100 scale)
    my $min_dist = $dist_white;
    $min_dist = $dist_black if $dist_black < $min_dist;
    $min_dist = $dist_gray if $dist_gray < $min_dist;
    my $neutral_dist = ($min_dist / 441.67) * 100;  # 441.67 = sqrt(3*255^2) max distance

    # Colorfulness = saturation² (0-10000) + neutral distance (0-100)
    # Heavy weight on saturation to prefer truly colorful colors
    my $colorfulness = pow($sat, 2) + $neutral_dist;

    printf "%.2f", $colorfulness;
  ' "$r" "$g" "$b" "$sat"
}

# Calculate dullness score (for dim selection)
# Low saturation + mid-range readable luminance = duller
calc_dullness() {
  local r=$1 g=$2 b=$3
  local sat=$4 lum=$5

  perl -e '
    use strict;
    use POSIX qw(abs pow);

    my ($r, $g, $b, $sat, $lum) = @ARGV;

    # Dullness factors:
    # 1. Low saturation (desaturated colors are dull)
    # 2. Mid-range luminance (readable but not prominent)

    my $desat_score = (100 - $sat);  # Higher = less saturated = duller

    # Readability: prefer mid-range luminance (80-180)
    # Peak at 130 (readable in most contexts)
    my $readable_peak = 130;
    my $lum_penalty = pow(($lum - $readable_peak) / 100, 2) * 50;
    my $readable_score = 100 - $lum_penalty;
    $readable_score = 0 if $readable_score < 0;

    # Dullness = desaturation + readability
    my $dullness = $desat_score + $readable_score;

    printf "%.2f", $dullness;
  ' "$r" "$g" "$b" "$sat" "$lum"
}

# ------------------------- Build arrays -----------------------------
typeset -a ALL_COLORS  # "r,g,b"
typeset -a LUM         # numeric strings
typeset -a SAT         # numeric strings
typeset -a PCT         # percentage of sprite
typeset -a IS_GRAY     # "0"/"1"
typeset -a HEXS        # "#RRGGBB"
typeset -a LAB         # "L a b" - LAB color space values
typeset -a COLORFUL    # colorfulness scores
typeset -a DULLNESS    # dullness scores

# Read UNIQUE_COLORS lines: r,g,b
while IFS=',' read -r r g b; do
  # sanity clamp [0,255]
  (( r < 0 )) && r=0; (( r > 255 )) && r=255
  (( g < 0 )) && g=0; (( g > 255 )) && g=255
  (( b < 0 )) && b=0; (( b > 255 )) && b=255

  local_lum="$(calc_luminance "$r" "$g" "$b")"
  local_sat="$(calc_saturation "$r" "$g" "$b")"
  local_pct="$(get_color_percentage "$r,$g,$b")"
  local_lab="$(rgb_to_lab "$r" "$g" "$b")"
  local_colorful="$(calc_colorfulness "$r" "$g" "$b" "$local_sat")"
  local_dull="$(calc_dullness "$r" "$g" "$b" "$local_sat" "$local_lum")"

  ALL_COLORS+=("$r,$g,$b")
  LUM+=("$local_lum")
  SAT+=("$local_sat")
  PCT+=("$local_pct")
  LAB+=("$local_lab")
  COLORFUL+=("$local_colorful")
  DULLNESS+=("$local_dull")

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

# Find array index for a color "r,g,b"
find_color_index() {
  local target=$1
  for i in {1..$#ALL_COLORS}; do
    if [[ "${ALL_COLORS[$i]}" == "$target" ]]; then
      print -r -- "$i"
      return 0
    fi
  done
  print -r -- "-1"
  return 1
}

# ------------------------- Prominent Selection (NEW ALGORITHM) -----
# Iterate colors by frequency, select first one that is:
# 1. Sufficiently colorful (high saturation + not neutral)
# 2. Appropriate luminance for the background mode
# Track max colorfulness as fallback

select_prominent_color() {
  local mode=$1  # "dark" or "light"

  local colorful_threshold=2000  # Threshold for truly colorful colors
  local max_colorful_score=0
  local max_colorful_idx=-1
  local selected_idx=-1

  # Iterate colors by frequency (most frequent first)
  while IFS=',' read -r r g b; do
    local idx=$(find_color_index "$r,$g,$b")
    [[ $idx -lt 0 ]] && continue

    local lum="${LUM[$idx]}"
    local sat="${SAT[$idx]}"
    local colorful_score="${COLORFUL[$idx]}"

    # IMPORTANT: Reject colors too close to white/black (off-whites, pastels, dark grays)
    # These fail the "actually colorful" test even if they have decent saturation
    local too_close_to_neutral=0
    if [[ $mode == "dark" ]]; then
      # For dark mode, reject near-whites: any color where min distance to white < 100 in RGB space
      local dist_to_white=$(perlcalc "sqrt((255-$r)**2 + (255-$g)**2 + (255-$b)**2)")
      (( $(perlcalc "$dist_to_white < 100") )) && too_close_to_neutral=1
    else
      # For light mode, reject near-blacks: any color where min distance to black < 80 in RGB space
      local dist_to_black=$(perlcalc "sqrt($r**2 + $g**2 + $b**2)")
      (( $(perlcalc "$dist_to_black < 80") )) && too_close_to_neutral=1
    fi

    # Skip if too close to neutral
    (( too_close_to_neutral )) && continue

    # Track max colorfulness for fallback (among non-neutral colors only)
    if perlcmp "$colorful_score" "$max_colorful_score"; then
      max_colorful_score="$colorful_score"
      max_colorful_idx=$idx
    fi

    # Check luminance constraints based on mode
    local lum_ok=0
    if [[ $mode == "dark" ]]; then
      # Dark mode: need bright colors (lum > 80) to pop on dark background
      (( $(perlcalc "$lum > 80") )) && lum_ok=1
    else
      # Light mode: need dark colors (lum < 175) to show on light background
      (( $(perlcalc "$lum < 175") )) && lum_ok=1
    fi

    # If colorful enough AND appropriate luminance, select it
    if (( lum_ok )) && perlcmp "$colorful_score" "$colorful_threshold"; then
      selected_idx=$idx
      break
    fi
  done <<< "$COLORS_BY_FREQUENCY"

  # Fallback: if nothing met threshold, use most colorful color found
  if [[ $selected_idx -lt 0 ]]; then
    selected_idx=$max_colorful_idx
  fi

  print -r -- "$selected_idx"
}

# Dark mode prominent
DARK_PROMINENT_IDX=$(select_prominent_color "dark")

# Light mode prominent
LIGHT_PROMINENT_IDX=$(select_prominent_color "light")

# ------------------------- Bright Selection (NEW ALGORITHM) --------
# Select color with maximum Delta E distance from prominent
# Must have appropriate luminance (not too dark for dark mode, not too light for light mode)

select_bright_color() {
  local mode=$1
  local prominent_idx=$2

  [[ $prominent_idx -lt 0 ]] && { print -r -- "-1"; return; }

  local prominent_lab="${LAB[$prominent_idx]}"
  local max_delta_e=0
  local best_idx=-1
  local min_delta_e_threshold=30  # Minimum perceptual difference

  # Iterate all colors
  for i in {1..$#ALL_COLORS}; do
    # Skip if same as prominent
    [[ $i -eq $prominent_idx ]] && continue

    local lum="${LUM[$i]}"
    local current_lab="${LAB[$i]}"

    # Check luminance constraints
    local lum_ok=0
    if [[ $mode == "dark" ]]; then
      # Dark mode: avoid super dark colors (need lum > 100) and super light (lum < 240)
      (( $(perlcalc "$lum > 100 && $lum < 240") )) && lum_ok=1
    else
      # Light mode: avoid super light colors (need lum < 155) and super dark (lum > 20)
      (( $(perlcalc "$lum < 155 && $lum > 20") )) && lum_ok=1
    fi

    (( ! lum_ok )) && continue

    # Calculate perceptual distance
    local delta_e=$(calc_delta_e "$prominent_lab" "$current_lab")

    # Track maximum difference
    if perlcmp "$delta_e" "$max_delta_e"; then
      max_delta_e="$delta_e"
      best_idx=$i
    fi
  done

  # Only return if we found a sufficiently different color
  if [[ $best_idx -ge 0 ]] && perlcmp "$max_delta_e" "$min_delta_e_threshold"; then
    print -r -- "$best_idx"
  else
    print -r -- "-1"  # Will become 'fallback' in output
  fi
}

# Dark mode bright
DARK_BRIGHT_IDX=$(select_bright_color "dark" "$DARK_PROMINENT_IDX")

# Light mode bright
LIGHT_BRIGHT_IDX=$(select_bright_color "light" "$LIGHT_PROMINENT_IDX")

# ------------------------- Dim Selection (NEW ALGORITHM) -----------
# Select dullest color that's still readable
# Prefer desaturated colors with mid-range luminance

select_dim_color() {
  local mode=$1  # Not heavily used, but available for future refinement

  local max_dullness=0
  local best_idx=-1
  local min_dullness_threshold=80  # Minimum dullness to be considered "dim"

  # Iterate all colors
  for i in {1..$#ALL_COLORS}; do
    local dull="${DULLNESS[$i]}"

    # Track maximum dullness
    if perlcmp "$dull" "$max_dullness"; then
      max_dullness="$dull"
      best_idx=$i
    fi
  done

  # Only return if we found a sufficiently dull color
  if [[ $best_idx -ge 0 ]] && perlcmp "$max_dullness" "$min_dullness_threshold"; then
    print -r -- "$best_idx"
  else
    print -r -- "-1"  # Will become 'fallback' in output
  fi
}

# Dark mode dim
DARK_DIM_IDX=$(select_dim_color "dark")

# Light mode dim
LIGHT_DIM_IDX=$(select_dim_color "light")

# ------------------------- Validate prominent colors ----------------
# Prominent should NEVER fallback - these must be valid
[[ $DARK_PROMINENT_IDX -lt 0 ]] && fail "No suitable prominent color found for dark mode"
[[ $LIGHT_PROMINENT_IDX -lt 0 ]] && fail "No suitable prominent color found for light mode"

# ------------------------- Build key --------------------------------
KEY="$POKEMON_NAME"
(( SHINY )) && KEY="${KEY}-shiny"
if [[ -n "$FORM_VALUE" ]]; then
  # normalize: lower-kebab
  KEY="${KEY}-$(print -r -- "$FORM_VALUE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
fi

# ------------------------- Emit Lua --------------------------------
# Selected color hexes (or 'fallback' string)
IFS=',' read -r r g b <<< "${ALL_COLORS[$DARK_PROMINENT_IDX]}"; DARK_PROMINENT=$(rgb_to_hex "$r" "$g" "$b")
if [[ $DARK_BRIGHT_IDX -ge 0 ]]; then
  IFS=',' read -r r g b <<< "${ALL_COLORS[$DARK_BRIGHT_IDX]}"; DARK_BRIGHT=$(rgb_to_hex "$r" "$g" "$b")
else
  DARK_BRIGHT="fallback"
fi
if [[ $DARK_DIM_IDX -ge 0 ]]; then
  IFS=',' read -r r g b <<< "${ALL_COLORS[$DARK_DIM_IDX]}"; DARK_DIM=$(rgb_to_hex "$r" "$g" "$b")
else
  DARK_DIM="fallback"
fi

IFS=',' read -r r g b <<< "${ALL_COLORS[$LIGHT_PROMINENT_IDX]}"; LIGHT_PROMINENT=$(rgb_to_hex "$r" "$g" "$b")
if [[ $LIGHT_BRIGHT_IDX -ge 0 ]]; then
  IFS=',' read -r r g b <<< "${ALL_COLORS[$LIGHT_BRIGHT_IDX]}"; LIGHT_BRIGHT=$(rgb_to_hex "$r" "$g" "$b")
else
  LIGHT_BRIGHT="fallback"
fi
if [[ $LIGHT_DIM_IDX -ge 0 ]]; then
  IFS=',' read -r r g b <<< "${ALL_COLORS[$LIGHT_DIM_IDX]}"; LIGHT_DIM=$(rgb_to_hex "$r" "$g" "$b")
else
  LIGHT_DIM="fallback"
fi

# Build lua entry with metadata for reliable parsing
# The _meta table stores the original components so parsers don't need to guess
# how to split keys containing natural dashes (e.g., "ho-oh", "porygon-z")
# Note: 'fallback' strings are handled by utils.lua to resolve to colorscheme colors
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
