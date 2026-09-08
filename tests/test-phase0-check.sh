#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../plugins/dev-workflow/hooks/phase0-check.sh"

fail() { echo "FAIL: $1"; exit 1; }

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
rm -rf "$tmp_empty"

# Case 2: everything initialized
tmp_full=$(mktemp -d)
mkdir -p "$tmp_full/openspec" "$tmp_full/.beads" "$tmp_full/graphify-out"
touch "$tmp_full/graphify-out/graph.json"
output_full=$(cd "$tmp_full" && "$HOOK")
message_full=$(echo "$output_full" | jq -r '.hookSpecificOutput.additionalContext')
echo "$message_full" | grep -q "OpenSpec initialized" || fail "full case: expected OpenSpec initialized line"
echo "$message_full" | grep -q "Beads initialized" || fail "full case: expected Beads initialized line"
echo "$message_full" | grep -q "Graphify initialized" || fail "full case: expected Graphify initialized line"
rm -rf "$tmp_full"

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
rm -rf "$tmp_repo"

# Case 4: graphify-out/ directory exists but graph.json hasn't been generated yet
tmp_no_graph=$(mktemp -d)
mkdir -p "$tmp_no_graph/openspec" "$tmp_no_graph/.beads" "$tmp_no_graph/graphify-out"
output_no_graph=$(cd "$tmp_no_graph" && "$HOOK")
message_no_graph=$(echo "$output_no_graph" | jq -r '.hookSpecificOutput.additionalContext')
echo "$message_no_graph" | grep -q "Graphify not initialized" || fail "no-graph case: expected Graphify not-initialized line when graphify-out/ exists but graph.json doesn't"
rm -rf "$tmp_no_graph"

echo "All phase0-check tests passed"
