#!/usr/bin/env bash
set -euo pipefail

GH_CMD="${PREFLIGHT_GH_CMD:-gh}"
CLAUDE_CMD="${PREFLIGHT_CLAUDE_CMD:-claude}"
CURL_CMD="${PREFLIGHT_CURL_CMD:-curl}"
CACHE_DIR="${PREFLIGHT_CACHE_DIR:-$HOME/.claude/dev-workflow}"
CACHE_TTL_SECONDS=900

results=()

check_gh_auth() {
  if ! command -v "$GH_CMD" >/dev/null 2>&1; then
    results+=("✗ GitHub CLI (gh) not found — install before relying on gh-authenticated workflows")
    return
  fi
  if "$GH_CMD" auth status >/dev/null 2>&1; then
    results+=("✓ GitHub CLI authenticated")
  else
    results+=("✗ GitHub CLI not authenticated — run \`gh auth login\`")
  fi
}

check_token() {
  local label="$1" var_name="$2" url="$3" header_fmt="$4"
  local token="${!var_name:-}"
  if [ -z "$token" ]; then
    echo "○ ${var_name} not set — skip if you don't use ${label}"
    return
  fi
  if ! command -v "$CURL_CMD" >/dev/null 2>&1; then
    echo "✗ curl not found — cannot verify ${var_name}"
    return
  fi
  local cache_path="$CACHE_DIR/preflight-cache-token_${var_name}.txt"
  local now; now=$(date +%s)
  if [ -f "$cache_path" ]; then
    local ts cached_line
    IFS=$'\t' read -r ts cached_line < "$cache_path"
    if [ -n "$ts" ] && [ $(( now - ts )) -le "$CACHE_TTL_SECONDS" ]; then
      echo "$cached_line"
      return
    fi
  fi
  local header
  header=$(printf "$header_fmt" "$token")
  local code
  code=$("$CURL_CMD" -s -o /dev/null --max-time 3 -w '%{http_code}' -H "$header" "$url" 2>/dev/null || echo "000")
  local line
  case "$code" in
    200) line="✓ ${var_name} valid (${label} responded 200)" ;;
    000) line="○ ${var_name} set but ${label} unreachable (offline or timed out) — could not verify" ;;
    *) line="✗ ${var_name} rejected by ${label} (HTTP ${code}) — token missing, expired, or revoked" ;;
  esac
  mkdir -p "$CACHE_DIR"
  printf '%s\t%s\n' "$now" "$line" > "$cache_path"
  echo "$line"
}

check_mcp_servers() {
  if ! command -v "$CLAUDE_CMD" >/dev/null 2>&1; then
    results+=("✗ claude CLI not found — cannot enumerate MCP servers")
    return
  fi
  # `claude mcp list` health-checks every configured server over the network
  # (~6s observed) — cache the result like check_token does for tokens.
  local cache_path="$CACHE_DIR/preflight-cache-mcplist.txt"
  local now; now=$(date +%s)
  local list=""
  local cache_hit=0
  if [ -f "$cache_path" ]; then
    local ts; ts=$(head -n 1 "$cache_path")
    if [[ "$ts" =~ ^[0-9]+$ ]] && [ $(( now - ts )) -le "$CACHE_TTL_SECONDS" ]; then
      list=$(tail -n +2 "$cache_path")
      cache_hit=1
    fi
  fi
  if [ "$cache_hit" -eq 0 ]; then
    list=$("$CLAUDE_CMD" mcp list 2>/dev/null || true)
    mkdir -p "$CACHE_DIR"
    { printf '%s\n' "$now"; printf '%s\n' "$list"; } > "$cache_path"
  fi
  if [ -z "$list" ]; then
    results+=("○ No MCP servers configured")
    return
  fi
  while IFS= read -r line; do
    if [ -n "$line" ]; then
      local server_name="${line%%: *}"
      results+=("✓ MCP server configured: ${server_name} (live connectivity checked by /preflight skill)")
    fi
  done <<< "$list"
}

check_gh_auth
results+=("$(check_token "GitHub" GITHUB_PERSONAL_ACCESS_TOKEN "https://api.github.com/user" "Authorization: token %s")")
results+=("$(check_token "GitLab" GITLAB_TOKEN "https://gitlab.com/api/v4/user" "PRIVATE-TOKEN: %s")")
check_mcp_servers

message=$(printf '%s\n' "${results[@]}")

if ! command -v jq >/dev/null 2>&1; then
  echo "preflight-check: jq is required to format this hook's output; install jq to see credential/MCP status." >&2
  exit 0
fi

jq -n --arg msg "$message" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $msg}}'
exit 0
