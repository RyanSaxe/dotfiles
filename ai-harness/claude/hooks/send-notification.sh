#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
harness_notify="$(cd "$script_dir/../.." && pwd)/notify.sh"

export AI_AGENT_SOURCE="${AI_AGENT_SOURCE:-claude}"
exec bash "$harness_notify" "$@"
