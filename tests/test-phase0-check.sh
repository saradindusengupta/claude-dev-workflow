#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../plugins/dev-workflow/hooks/phase0-check.sh"

fail() { echo "FAIL: $1"; exit 1; }

trap 'rm -rf "${tmp_empty:-}" "${tmp_full:-}" "${tmp_repo:-}" "${tmp_no_graph:-}" "${tmp_partial:-}" "${tmp_wrong_type:-}"' EXIT

# Case 1: nothing initialized
tmp_empty=$(mktemp -d)
output_empty=$(cd "$tmp_empty" && "$HOOK")
echo "$output_empty" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null || fail "empty case: no additionalContext field in hook output"
echo "$output_empty" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null || fail "empty case: hookEventName missing or wrong"
message_empty=$(echo "$output_empty" | jq -r '.hookSpecificOutput.additionalContext')
echo "$message_empty" | grep -q "OpenSpec CLI" || fail "empty case: expected OpenSpec CLI line"
echo "$message_empty" | grep -q "Beads CLI" || fail "empty case: expected Beads CLI line"
echo "$message_empty" | grep -q "Graphify CLI" || fail "empty case: expected Graphify CLI line"
echo "$message_empty" | grep -q "OpenSpec not initialized" || fail "empty case: expected OpenSpec not-initialized line"
echo "$message_empty" | grep -q "Beads not initialized" || fail "empty case: expected Beads not-initialized line"
echo "$message_empty" | grep -q "Graphify not initialized" || fail "empty case: expected Graphify not-initialized line"

# Case 2: everything initialized
tmp_full=$(mktemp -d)
mkdir -p "$tmp_full/openspec" "$tmp_full/.beads" "$tmp_full/graphify-out"
touch "$tmp_full/graphify-out/graph.json"
output_full=$(cd "$tmp_full" && "$HOOK")
message_full=$(echo "$output_full" | jq -r '.hookSpecificOutput.additionalContext')
echo "$message_full" | grep -q "OpenSpec initialized" || fail "full case: expected OpenSpec initialized line"
echo "$message_full" | grep -q "Beads initialized" || fail "full case: expected Beads initialized line"
echo "$message_full" | grep -q "Graphify initialized" || fail "full case: expected Graphify initialized line"

# Case 3: everything initialized at repo root, hook run from a subdirectory
tmp_repo=$(mktemp -d)
(cd "$tmp_repo" && git init -q)
mkdir -p "$tmp_repo/openspec" "$tmp_repo/.beads" "$tmp_repo/graphify-out" "$tmp_repo/src/deep"
touch "$tmp_repo/graphify-out/graph.json"
output_subdir=$(cd "$tmp_repo/src/deep" && "$HOOK")
message_subdir=$(echo "$output_subdir" | jq -r '.hookSpecificOutput.additionalContext')
echo "$message_subdir" | grep -q "OpenSpec initialized" || fail "subdir case: expected OpenSpec initialized line"
echo "$message_subdir" | grep -q "Beads initialized" || fail "subdir case: expected Beads initialized line"
echo "$message_subdir" | grep -q "Graphify initialized" || fail "subdir case: expected Graphify initialized line"
echo "$message_subdir" | grep -q "OpenSpec not initialized" && fail "subdir case: OpenSpec wrongly reported not initialized"
echo "$message_subdir" | grep -q "Beads not initialized" && fail "subdir case: Beads wrongly reported not initialized"
echo "$message_subdir" | grep -q "Graphify not initialized" && fail "subdir case: Graphify wrongly reported not initialized"

# Case 4: graphify-out/ directory exists but graph.json hasn't been generated yet
tmp_no_graph=$(mktemp -d)
mkdir -p "$tmp_no_graph/openspec" "$tmp_no_graph/.beads" "$tmp_no_graph/graphify-out"
output_no_graph=$(cd "$tmp_no_graph" && "$HOOK")
message_no_graph=$(echo "$output_no_graph" | jq -r '.hookSpecificOutput.additionalContext')
echo "$message_no_graph" | grep -q "Graphify not initialized" || fail "no-graph case: expected Graphify not-initialized line when graphify-out/ exists but graph.json doesn't"

# Case 5: OpenSpec initialized, Beads and Graphify not
tmp_partial=$(mktemp -d)
mkdir -p "$tmp_partial/openspec"
output_partial=$(cd "$tmp_partial" && "$HOOK")
message_partial=$(echo "$output_partial" | jq -r '.hookSpecificOutput.additionalContext')
echo "$message_partial" | grep -q "OpenSpec initialized" || fail "partial case: expected OpenSpec initialized line"
echo "$message_partial" | grep -q "Beads not initialized" || fail "partial case: expected Beads not-initialized line"
echo "$message_partial" | grep -q "Graphify not initialized" || fail "partial case: expected Graphify not-initialized line"

# Case 6: OpenSpec/Beads paths exist as files, not directories
tmp_wrong_type=$(mktemp -d)
touch "$tmp_wrong_type/openspec" "$tmp_wrong_type/.beads"
mkdir -p "$tmp_wrong_type/graphify-out"
touch "$tmp_wrong_type/graphify-out/graph.json"
output_wrong_type=$(cd "$tmp_wrong_type" && "$HOOK")
message_wrong_type=$(echo "$output_wrong_type" | jq -r '.hookSpecificOutput.additionalContext')
echo "$message_wrong_type" | grep -q "OpenSpec not initialized" || fail "wrong-type case: expected OpenSpec not-initialized line for file path"
echo "$message_wrong_type" | grep -q "Beads not initialized" || fail "wrong-type case: expected Beads not-initialized line for file path"
echo "$message_wrong_type" | grep -q "Graphify initialized" || fail "wrong-type case: expected Graphify initialized line for graph.json file"

echo "All phase0-check tests passed"
