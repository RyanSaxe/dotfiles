#!/bin/sh
# Codex's managed SessionStart hook. It registers the session with pair, so
# `pair agents` lists it and other agents can message it. The hook's JSON on
# stdin carries the session's ID.
exec "$HOME/.nix-profile/bin/pair" register --hook
