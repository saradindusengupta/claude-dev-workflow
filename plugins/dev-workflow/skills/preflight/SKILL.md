---
name: preflight
description: This skill should be used when a session hits an auth error, an MCP tool fails to connect, or the user asks to check or fix credentials, tokens, or MCP server health. Diagnoses the preflight hook's report, tests live MCP connectivity, and proposes repairs — never writes to the shell profile or a secret store without explicit per-item confirmation.
---

# Preflight: Credential & MCP Health Check

Turns the read-only `preflight-check.sh` hook report into live diagnosis and confirmed repairs. The hook already ran at session start — this skill picks up where it left off.

## Step 1: Read the existing report

Look at this session's `SessionStart` hook output for `preflight-check.sh`. If it's not visible (e.g. the user invoked `/dev-workflow:preflight` mid-session), re-run the hook script directly to reproduce the exact report with token-validity checks (✗/○ distinction) that manual checks alone cannot provide. `${CLAUDE_PLUGIN_ROOT}` is only substituted inside `hooks.json` command strings — it is not set in your shell environment when you run commands yourself while following a skill. So: if `${CLAUDE_PLUGIN_ROOT}` happens to be set, use `${CLAUDE_PLUGIN_ROOT}/hooks/preflight-check.sh`; otherwise locate the installed script by searching the plugin cache, e.g. `find ~/.claude/plugins/cache -path '*/dev-workflow/*/hooks/preflight-check.sh' 2>/dev/null | sort -V | tail -1` (this picks the highest-versioned match if more than one is cached), and run whichever path that returns.

## Step 2: Test live MCP connectivity

The hook can only confirm a server is *configured* — it can't make an actual protocol call. For each server the report lists as configured, make one trivial, read-only tool call from that server (a list/get/read operation, never a write) and note whether it succeeds, times out, or errors with an auth failure. Report each as ✓/✗/○ alongside the hook's static list.

## Step 3: Diagnose and propose repairs — never apply silently

For each ✗ or ○ item, diagnose the likely cause and propose exactly one fix at a time. Wait for explicit confirmation before writing anything. Never invent or guess a secret value.

- **`gh` not installed:** tell the user the install command for their platform (e.g. `brew install gh` on macOS); cannot be auto-repaired.
- **`gh auth status` fails:** tell the user to run `gh auth login` themselves — this is an interactive device/browser flow that must not be scripted.
- **`GITHUB_PERSONAL_ACCESS_TOKEN` unset but `gh auth status` succeeds:** the token can be derived without asking the user to paste anything — propose running `gh auth token` and exporting its output. Show the exact command-substitution form (e.g. `export GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token)"`) before writing it, never a resolved plaintext token value.
- **`GITHUB_PERSONAL_ACCESS_TOKEN` rejected with HTTP 401 (expired/invalid) and `gh auth status` also fails:** cannot be derived — ask the user to generate a new token (github.com/settings/tokens) and paste it, then propose the export line.
- **`GITHUB_PERSONAL_ACCESS_TOKEN` rejected with HTTP 403:** do NOT propose regenerating the token — a 403 usually means the token is valid but lacks a required scope, or access is blocked for another reason (org SSO not authorized, IP allowlist). Ask the user to check the token's scopes/permissions and org SSO authorization at github.com/settings/tokens rather than assuming it's expired.
- **`GITLAB_TOKEN` rejected or unset and needed:** same pattern (401 vs 403 distinction included) — there's no CLI-derivable fallback for GitLab here, so ask the user directly.
- **Before asking the user to paste any secret, on macOS only:** capture the value via command substitution, e.g. run it as `token_value=$(security find-generic-password -s "<likely-service-name>" -w 2>/dev/null)` — never run `security find-generic-password ... -w` as a bare command, since its output would print directly to your tool output/transcript. Try well-known service names first; only ask the user if the lookup comes up empty. Use `$token_value` directly in the export line — never echo it, print it, or show it to the user. Skip this step entirely on non-macOS — don't assume Keychain exists.
- **Writing an export line:** detect the user's shell (`$SHELL`) to pick `~/.zshrc` vs `~/.bashrc`/`~/.bash_profile`. `grep` for an existing `export <VAR>=` line first — replace it in place (with confirmation) if found, append only if it's genuinely new. When showing a line being replaced, show only the variable name being replaced, never its old value. Never duplicate an export line for the same variable.
- **`curl` or `claude` CLI not found:** tell the user the install command for their platform (matching the pattern for `gh` above); these are prerequisites the hook can't verify, so if either is missing, the hook's checks are incomplete. Cannot be auto-repaired.
- **No MCP servers configured (○):** check with the user first — if they intentionally don't use MCP integrations, there's nothing to fix. Only suggest adding a server if the user indicates they need one.
- **Misconfigured or unreachable MCP server:** point to `claude mcp list` / `claude mcp add` / `claude mcp remove` — the exact fix depends on that server's own setup; don't guess at a generic repair.

## Step 4: Re-check and report

After any repairs, re-run the affected checks and print a single compact table, one row per check, ✓/✗/○ plus a one-line reason. If anything requires a session restart to take effect — a new shell-profile export doesn't reach the current shell or this plugin's hooks until restarted, since hooks only reload at `SessionStart` — say so explicitly as the last line.

## Step 5: Track recurring friction (insights loop)

After reporting, update `~/.claude/dev-workflow/preflight-state.json` — a flat map of check name to fail count, e.g. `{"gh_auth": {"failCount": 2}, "github_token": {"failCount": 0}}`. For every check that came back ✗ this run, increment its `failCount`; for every check that came back ✓, reset it to 0. If any check's `failCount` reaches 3 — three separate `/dev-workflow:preflight` runs where it didn't stay fixed — tell the user this is worth surfacing: suggest running `/insights` (a separate tool, if installed — not part of this plugin), and if it confirms a recurring pattern, file it with `bd create --type=chore --title="Recurring preflight failure: <check>" --label=infra` so it becomes a tracked backlog item instead of repeat friction.

## Notes

- Never print a raw secret value in this skill's output, in the hook's output, or in a `bd create`/commit message — status only (valid/expired/missing), never the token itself.
- This skill mutates the user's own machine (shell profile, possibly a keychain read). It never touches files inside the current git repo.
