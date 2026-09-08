#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../plugins/dev-workflow/hooks/preflight-check.sh"

fail() { echo "FAIL: $1"; exit 1; }

fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures" "${cache_dir_broken:-}" "${cache_dir_healthy:-}" "${cache_dir:-}" "${mcp_cache_dir:-}" "${cache_dir_fingerprint:-}" "${cache_dir_corrupt:-}" "${cache_dir_403:-}"' EXIT

make_fixture() {
  local name="$1" body="$2"
  local path="$fixtures/$name"
  printf '#!/usr/bin/env bash\n%s\n' "$body" > "$path"
  chmod +x "$path"
  echo "$path"
}

gh_fail=$(make_fixture "gh-fail" 'exit 1')
gh_ok=$(make_fixture "gh-ok" 'exit 0')
claude_empty=$(make_fixture "claude-empty" 'echo ""')
claude_servers=$(make_fixture "claude-servers" 'printf "github\nlinear\n"')
curl_401=$(make_fixture "curl-401" 'echo "401"')
curl_403=$(make_fixture "curl-403" 'echo "403"')
curl_200=$(make_fixture "curl-200" 'echo "200"')

# Case 1: everything broken
cache_dir_broken=$(mktemp -d)
output_broken=$(PREFLIGHT_CACHE_DIR="$cache_dir_broken" PREFLIGHT_GH_CMD="$gh_fail" PREFLIGHT_CLAUDE_CMD="$claude_empty" PREFLIGHT_CURL_CMD="$curl_401" \
  GITHUB_PERSONAL_ACCESS_TOKEN="expired-token" GITLAB_TOKEN="" "$HOOK")
echo "$output_broken" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null || fail "broken case: hookEventName missing or wrong"
message_broken=$(echo "$output_broken" | jq -r '.hookSpecificOutput.additionalContext')
echo "$message_broken" | grep -q "GitHub CLI not authenticated" || fail "broken case: expected gh not-authenticated line"
echo "$message_broken" | grep -q "GITHUB_PERSONAL_ACCESS_TOKEN rejected" || fail "broken case: expected rejected GitHub token line"
echo "$message_broken" | grep -q "GITLAB_TOKEN not set" || fail "broken case: expected GITLAB_TOKEN not-set line"
echo "$message_broken" | grep -q "No MCP servers configured" || fail "broken case: expected no-MCP-servers line"

# Case 2: everything healthy
cache_dir_healthy=$(mktemp -d)
output_healthy=$(PREFLIGHT_CACHE_DIR="$cache_dir_healthy" PREFLIGHT_GH_CMD="$gh_ok" PREFLIGHT_CLAUDE_CMD="$claude_servers" PREFLIGHT_CURL_CMD="$curl_200" \
  GITHUB_PERSONAL_ACCESS_TOKEN="good-token" GITLAB_TOKEN="good-token" "$HOOK")
message_healthy=$(echo "$output_healthy" | jq -r '.hookSpecificOutput.additionalContext')
echo "$message_healthy" | grep -q "GitHub CLI authenticated" || fail "healthy case: expected gh authenticated line"
echo "$message_healthy" | grep -q "GITHUB_PERSONAL_ACCESS_TOKEN valid" || fail "healthy case: expected valid GitHub token line"
echo "$message_healthy" | grep -q "GITLAB_TOKEN valid" || fail "healthy case: expected valid GitLab token line"
echo "$message_healthy" | grep -q "MCP server configured: github" || fail "healthy case: expected github MCP server line"
echo "$message_healthy" | grep -q "MCP server configured: linear" || fail "healthy case: expected linear MCP server line"

# Case 3: a token check result is cached and not re-verified within the TTL
cache_dir=$(mktemp -d)
curl_second=$(make_fixture "curl-second" 'echo "401"')

PREFLIGHT_CACHE_DIR="$cache_dir" PREFLIGHT_GH_CMD="$gh_ok" PREFLIGHT_CLAUDE_CMD="$claude_empty" PREFLIGHT_CURL_CMD="$curl_200" \
  GITHUB_PERSONAL_ACCESS_TOKEN="good-token" GITLAB_TOKEN="" "$HOOK" > /dev/null

output_cached=$(PREFLIGHT_CACHE_DIR="$cache_dir" PREFLIGHT_GH_CMD="$gh_ok" PREFLIGHT_CLAUDE_CMD="$claude_empty" PREFLIGHT_CURL_CMD="$curl_second" \
  GITHUB_PERSONAL_ACCESS_TOKEN="good-token" GITLAB_TOKEN="" "$HOOK")
message_cached=$(echo "$output_cached" | jq -r '.hookSpecificOutput.additionalContext')
echo "$message_cached" | grep -q "GITHUB_PERSONAL_ACCESS_TOKEN valid" || fail "cache case: expected cached valid result to be reused instead of re-querying curl"

# Case 4: MCP server list is cached and not re-queried within the TTL
mcp_cache_dir=$(mktemp -d)
claude_servers_second=$(make_fixture "claude-servers-second" 'printf "notion\n"')

PREFLIGHT_CACHE_DIR="$mcp_cache_dir" PREFLIGHT_GH_CMD="$gh_ok" PREFLIGHT_CLAUDE_CMD="$claude_servers" PREFLIGHT_CURL_CMD="$curl_200" \
  GITHUB_PERSONAL_ACCESS_TOKEN="" GITLAB_TOKEN="" "$HOOK" > /dev/null

output_mcp_cached=$(PREFLIGHT_CACHE_DIR="$mcp_cache_dir" PREFLIGHT_GH_CMD="$gh_ok" PREFLIGHT_CLAUDE_CMD="$claude_servers_second" PREFLIGHT_CURL_CMD="$curl_200" \
  GITHUB_PERSONAL_ACCESS_TOKEN="" GITLAB_TOKEN="" "$HOOK")
message_mcp_cached=$(echo "$output_mcp_cached" | jq -r '.hookSpecificOutput.additionalContext')
echo "$message_mcp_cached" | grep -q "MCP server configured: github" || fail "mcp cache case: expected cached github MCP server line to be reused instead of re-querying claude mcp list"
echo "$message_mcp_cached" | grep -q "MCP server configured: notion" && fail "mcp cache case: MCP list was re-queried instead of using the cache"

# Case 5: a token's cache entry is invalidated when the token value itself changes
# (cache is keyed by var name + TTL only — must not serve a stale verdict for a
# rotated token still inside the TTL window)
cache_dir_fingerprint=$(mktemp -d)
curl_after_rotation=$(make_fixture "curl-after-rotation" 'echo "401"')

PREFLIGHT_CACHE_DIR="$cache_dir_fingerprint" PREFLIGHT_GH_CMD="$gh_ok" PREFLIGHT_CLAUDE_CMD="$claude_empty" PREFLIGHT_CURL_CMD="$curl_200" \
  GITHUB_PERSONAL_ACCESS_TOKEN="old-token" GITLAB_TOKEN="" "$HOOK" > /dev/null

output_rotated=$(PREFLIGHT_CACHE_DIR="$cache_dir_fingerprint" PREFLIGHT_GH_CMD="$gh_ok" PREFLIGHT_CLAUDE_CMD="$claude_empty" PREFLIGHT_CURL_CMD="$curl_after_rotation" \
  GITHUB_PERSONAL_ACCESS_TOKEN="new-token" GITLAB_TOKEN="" "$HOOK")
message_rotated=$(echo "$output_rotated" | jq -r '.hookSpecificOutput.additionalContext')
echo "$message_rotated" | grep -q "GITHUB_PERSONAL_ACCESS_TOKEN rejected" || fail "rotated-token case: expected the new token to be freshly re-verified (rejected) instead of reusing the old token's cached valid result"

# Case 6: a corrupted cache file (non-numeric timestamp) must not crash the hook
cache_dir_corrupt=$(mktemp -d)
printf 'not-a-number\tsome-fingerprint\tsome cached line\n' > "$cache_dir_corrupt/preflight-cache-token_GITHUB_PERSONAL_ACCESS_TOKEN.txt"

output_corrupt=$(PREFLIGHT_CACHE_DIR="$cache_dir_corrupt" PREFLIGHT_GH_CMD="$gh_ok" PREFLIGHT_CLAUDE_CMD="$claude_empty" PREFLIGHT_CURL_CMD="$curl_200" \
  GITHUB_PERSONAL_ACCESS_TOKEN="good-token" GITLAB_TOKEN="" "$HOOK") || fail "corrupt-cache case: hook exited non-zero instead of degrading gracefully"
echo "$output_corrupt" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null || fail "corrupt-cache case: hook produced no valid JSON output"
message_corrupt=$(echo "$output_corrupt" | jq -r '.hookSpecificOutput.additionalContext')
echo "$message_corrupt" | grep -q "GITHUB_PERSONAL_ACCESS_TOKEN valid" || fail "corrupt-cache case: expected a fresh (non-crashed) verification result despite the corrupted cache file"

# Case 7: HTTP 403 (valid token, insufficient scope / access restricted) must be
# reported distinctly from 401 (invalid/expired) — a 403 should not tell the
# user their token is expired or needs regenerating.
cache_dir_403=$(mktemp -d)
output_403=$(PREFLIGHT_CACHE_DIR="$cache_dir_403" PREFLIGHT_GH_CMD="$gh_ok" PREFLIGHT_CLAUDE_CMD="$claude_empty" PREFLIGHT_CURL_CMD="$curl_403" \
  GITHUB_PERSONAL_ACCESS_TOKEN="scope-limited-token" GITLAB_TOKEN="" "$HOOK")
message_403=$(echo "$output_403" | jq -r '.hookSpecificOutput.additionalContext')
echo "$message_403" | grep -q "HTTP 403" || fail "403 case: expected the HTTP 403 status code in the report"
echo "$message_403" | grep -q "lack required scopes" || fail "403 case: expected a scopes/permissions explanation, not a blanket expired/invalid message"
echo "$message_403" | grep -q "missing, expired, or revoked" && fail "403 case: must not reuse the 401 (expired/invalid) wording for a 403 response"

echo "All preflight-check tests passed"
