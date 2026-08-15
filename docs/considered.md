# Considered and not used

Tools evaluated for this setup, why they are not part of it, and what
would make them worth revisiting. If you are about to reach for macOS
automation, read this first.

## Leader Key

Launcher that turns a single tapped key into a command tree. Never made
it into daily use — the aerospace + tmux chord grammar (alt = terminal,
alt-cmd = window management) covers navigation, and popups cover
launching. Revisit if a genuinely global "run anything" tree becomes a
felt need; Raycast likely fills that role first (see the automations
design session on the roadmap).

## Karabiner-Elements

Low-level keyboard remapper. Existed only to give Leader Key a
shift-tap trigger; with Leader Key out, nothing uses it. Revisit only
for needs no app-level config can express — remapping a physical
modifier, per-device layouts, dual-role keys.

## Hammerspoon

Lua automation runtime for macOS. Nothing here needs it: the rail owns
the mascot and `theme` sets OS appearance itself. Revisit for
automation that must react to OS events with logic — though the known
lightweight recipe covers the likeliest case first: a ~20-line launchd
agent with WatchPaths on .GlobalPreferences.plist re-runs `theme apply`
when the OS flips appearance on a schedule, no runtime required.

## JankyBorders

Colored border around the focused window. Trialed and removed — the
setup reads better without it. Revisit only if focus ambiguity becomes
a real problem; HazeOver-style dimming is the stronger alternative (no
public macOS API sets another app's opacity).
