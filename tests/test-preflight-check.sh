#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../plugins/dev-workflow/hooks/preflight-check.sh"

fail() { echo "FAIL: $1"; exit 1; }

fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT

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
curl_200=$(make_fixture "curl-200" 'echo "200"')

# Case 1: everything broken
output_broken=$(PREFLIGHT_CACHE_DIR="$(mktemp -d)" PREFLIGHT_GH_CMD="$gh_fail" PREFLIGHT_CLAUDE_CMD="$claude_empty" PREFLIGHT_CURL_CMD="$curl_401" \
  GITHUB_PERSONAL_ACCESS_TOKEN="expired-token" GITLAB_TOKEN="" "$HOOK")
message_broken=$(echo "$output_broken" | jq -r '.hookSpecificOutput.additionalContext')
echo "$message_broken" | grep -q "GitHub CLI not authenticated" || fail "broken case: expected gh not-authenticated line"
echo "$message_broken" | grep -q "GITHUB_PERSONAL_ACCESS_TOKEN rejected" || fail "broken case: expected rejected GitHub token line"
echo "$message_broken" | grep -q "GITLAB_TOKEN not set" || fail "broken case: expected GITLAB_TOKEN not-set line"
echo "$message_broken" | grep -q "No MCP servers configured" || fail "broken case: expected no-MCP-servers line"

# Case 2: everything healthy
output_healthy=$(PREFLIGHT_CACHE_DIR="$(mktemp -d)" PREFLIGHT_GH_CMD="$gh_ok" PREFLIGHT_CLAUDE_CMD="$claude_servers" PREFLIGHT_CURL_CMD="$curl_200" \
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

echo "All preflight-check tests passed"
