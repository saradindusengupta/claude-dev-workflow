#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

results=()

add_cli_check() {
  local label="$1" cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    results+=("✓ ${label} CLI found")
  else
    results+=("✗ ${label} CLI not found — install before using this workflow")
  fi
}

add_dir_check() {
  local label="$1" path="$2" init_cmd="$3"
  if [ -d "$repo_root/$path" ]; then
    results+=("✓ ${label} initialized (${path})")
  else
    results+=("○ ${label} not initialized here — run \`${init_cmd}\` to set up")
  fi
}

add_file_check() {
  local label="$1" path="$2" init_cmd="$3"
  if [ -e "$repo_root/$path" ]; then
    results+=("✓ ${label} initialized (${path})")
  else
    results+=("○ ${label} not initialized here — run \`${init_cmd}\` to set up")
  fi
}

add_cli_check "OpenSpec" openspec
add_cli_check "Beads" bd
add_cli_check "Graphify" graphify
add_dir_check "OpenSpec" "openspec" "openspec init"
add_dir_check "Beads" ".beads" "bd init"
add_file_check "Graphify" "graphify-out/graph.json" "graphify install && graphify claude install --project --strict && graphify hook install && graphify update ."

message=$(printf '%s\n' "${results[@]}")

if ! command -v jq >/dev/null 2>&1; then
  echo "phase0-check: jq is required to format this hook's output; install jq to see prerequisite status." >&2
  exit 0
fi

jq -n --arg msg "$message" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $msg}}'
exit 0
