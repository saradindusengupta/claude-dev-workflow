---
name: setup
description: This skill should be used when a session reports a missing openspec/bd/graphify CLI, an uninitialized openspec/.beads directory, or a missing graphify-out/graph.json, or the user asks to install, initialize, or fix dev-workflow's prerequisite tooling. Diagnoses the phase0-check hook's report and proposes installs/inits — never runs a command without explicit per-item confirmation, and never guesses an install command it isn't confident about.
---

# Setup: Prerequisite Install & Fix

Turns the read-only `phase0-check.sh` hook report into live diagnosis and confirmed installs/inits for `openspec`, `bd`, and `graphify`. The hook already ran at session start — this skill picks up where it left off, the same way `preflight` does for the credential/MCP report.

## Step 1: Read the existing report

Look at this session's `SessionStart` hook output for `phase0-check.sh`. If it's not visible (e.g. the user invoked `/dev-workflow:setup` mid-session), re-run the hook script directly to reproduce the exact report. `${CLAUDE_PLUGIN_ROOT}` is only substituted inside `hooks.json` command strings — it is not set in your shell environment when you run commands yourself while following a skill. So: if `${CLAUDE_PLUGIN_ROOT}` happens to be set, use `${CLAUDE_PLUGIN_ROOT}/hooks/phase0-check.sh`; otherwise locate the installed script by searching the plugin cache, e.g. `find ~/.claude/plugins/cache -path '*/dev-workflow/*/hooks/phase0-check.sh' 2>/dev/null | sort -V | tail -1` (this picks the highest-versioned match if more than one is cached), and run whichever path that returns.

## Step 2: Diagnose and propose repairs — one at a time, never guess

For each ✗ (CLI not found) or ○ (not initialized) item, propose exactly one fix and wait for explicit confirmation before running anything. Never invent an install command you aren't confident is correct.

- **CLI missing (`openspec`, `bd`, or `graphify`):**
  1. Detect the platform: `uname -s`. On macOS, check whether the tool has a known Homebrew formula (e.g. `brew info <formula>`) before proposing `brew install`. On Linux, check which package manager is present (`command -v apt`, `command -v dnf`, `command -v pacman`) — do not assume one.
  2. If you already know the tool's actual install method with confidence, propose that exact command. Package name does **not** reliably match the CLI name — e.g. the npm packages literally named `beads` and `graphify` are unrelated projects; do not assume `npm install -g <tool-name>` is correct just because the name matches.
  3. If you are not confident, `WebFetch` the tool's own docs/README before proposing anything: OpenSpec → https://openspec.dev, beads → https://github.com/gastownhall/beads, graphify → its project's own README (search for it if not already known this session). Quote the command you found and where you found it.
  4. If no safe, non-interactive install command exists (the only path is an interactive installer, or you still aren't confident after checking docs), say so and give the user the command to run themselves — do not attempt it. This mirrors how `preflight` already handles `gh`/`curl`/`claude` CLI itself.
  5. Show the exact command. Wait for explicit confirmation. Run it. Re-verify with `command -v <tool>` before moving to the next item.

- **Directory not initialized (`openspec/`, `.beads/`, `graphify-out/graph.json`):**
  - Only propose this once the corresponding CLI check is already ✓ — don't propose `openspec init` while `openspec` itself is still missing.
  - Run the hook-embedded init command verbatim: `openspec init`, `bd init`, or for graphify, ask before each sub-step separately rather than the full chain at once (see below). Always run from the repo root (`git rev-parse --show-toplevel`), never the current subdirectory, matching how `phase0-check.sh` itself resolves the repo root.
  - **Graphify's repo-init chain is four sub-steps, each its own confirmation — never bundle them:**
    1. `graphify install`
    2. `graphify claude install --project --strict`
    3. `graphify hook install` — call out explicitly that this installs a git hook into the repo before asking for confirmation; this has a different blast radius than the other three steps.
    4. `graphify update .`

- **Graphify is optional — check before proposing anything for it.** If the user indicates they don't want the codebase graph (small repo, explicit decline, or it just isn't relevant to what they're doing), that's a valid terminal answer — don't keep re-proposing graphify's CLI install or repo-init chain, and don't count a declined item as a fail-count increment (see Step 4).

- After running any command, re-verify that specific check (re-run `phase0-check.sh`, or the equivalent `command -v` / path check) before proposing the next fix. If the re-check still fails, stop — show the exact stdout/stderr from the command you ran, and let the user decide whether to retry, skip, or investigate manually. Do not retry silently and do not move on to the next item as if it succeeded.

## Step 3: Re-check and report

After all items are processed (or the user stops partway through), re-run `phase0-check.sh` once more and print a single compact table, one row per check, ✓/✗/○ plus a one-line reason. If a just-installed CLI still doesn't resolve via `command -v` — some installers only take effect in a fresh shell (an updated `PATH`, a new shim, a re-sourced profile) — say so explicitly as a possible cause rather than reporting the install as failed outright, and suggest the user open a new shell and re-run `/dev-workflow:setup` to confirm.

## Step 4: Track recurring friction (insights loop)

After reporting, update `~/.claude/dev-workflow/setup-state.json` — a flat map of check name to fail count, e.g. `{"openspec_cli": {"failCount": 1}, "beads_init": {"failCount": 0}}`. For every check that came back ✗ or ○ this run — except an item the user explicitly declined (see Step 2's graphify note) or that Step 2 never reached because the user stopped partway through — increment its `failCount`; for every check that came back ✓, reset it to 0. If any check's `failCount` reaches 3 — three separate `/dev-workflow:setup` runs where it didn't stay fixed — tell the user this is worth surfacing: suggest running `/insights` (a separate tool, if installed — not part of this plugin), and if it confirms a recurring pattern, file it with `bd create --type=chore --title="Recurring setup failure: <check>" --label=infra` so it becomes a tracked backlog item instead of repeat friction.

## Notes

- Never run an install or init command without that specific item's explicit confirmation — no batching multiple confirmations into one yes.
- This skill mutates both the user's machine (CLI installs) and the current repo (`openspec/`, `.beads/`, `graphify-out/`, and — for `graphify hook install` specifically — the repo's git hooks). Say which of the two a proposed fix touches before asking for confirmation.
- If told a tool "is already installed" but the hook still reports it missing, trust the hook's `command -v` check over the claim — the shell that ran the hook may have a different `PATH` than the one being talked about (e.g. a tool installed only in a different shell profile).
