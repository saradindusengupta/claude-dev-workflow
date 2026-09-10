# dev-workflow (Claude Code plugin)

A Claude Code plugin bundling three skills and two `SessionStart` hooks:

- **`dev-workflow` skill** — a repeatable refresh/explore -> propose -> track -> implement -> verify -> archive cycle, chaining three tools:
  - **OpenSpec** — spec-driven change proposals
  - **beads** (`bd`) — dependency-aware issue tracking
  - **graphify** — optional codebase knowledge graph
- **`setup` skill** — diagnoses and (with your confirmation) installs or initializes missing prerequisite tooling: the `openspec`, `bd`, and `graphify` CLIs and their repo-level init state.
- **`preflight` skill** — diagnoses and (with your confirmation) repairs credential and MCP server issues: expired tokens, missing `gh` auth, unreachable MCP servers.

## What it does

On session start, the bundled hooks check (1) whether `openspec`, `bd`, and `graphify` are installed and initialized in the current repo, and (2) whether `gh` is authenticated, `GITHUB_PERSONAL_ACCESS_TOKEN`/`GITLAB_TOKEN` are set and valid, and which MCP servers are configured — reporting what's missing or broken in both cases. Invoke `/dev-workflow:dev-workflow` (or let it auto-trigger) to run the full cycle for a scoped change; invoke `/dev-workflow:setup` any time a phase0 check is red or uninitialized; invoke `/dev-workflow:preflight` any time a session hits an auth or MCP connectivity error. Skills in this plugin are invoked with the `dev-workflow:` prefix, since Claude Code namespaces skills by plugin name. `preflight-check.sh` makes outbound network requests on every session start — to configured MCP servers (via `claude mcp list`) and to `api.github.com`/`gitlab.com` (to validate tokens) — and caches their results locally under `~/.claude/dev-workflow/` to keep subsequent session starts fast.

## Usage

### Run the full dev cycle

In a repo with `openspec`/`bd` set up (or after letting `openspec init`/`bd init` run — Phase 0 checks for this), describe the change you want and either let the skill auto-trigger or invoke it explicitly:

```
/dev-workflow:dev-workflow
```

It walks a fixed six-phase cycle, one cohesive change per run:

1. **Refresh & Explore** — refresh the graphify graph (if installed), then use OpenSpec's `/opsx:explore` as a no-stakes thinking partner before proposing anything.
2. **Propose** — `openspec new change <name>`, write `proposal.md`/`specs/`/`tasks.md`, validate.
3. **Track** — turn the proposal's `tasks.md` groups into a beads epic + child tasks with dependencies.
4. **Implement** — `bd prime` → `bd ready` → claim, code, test, close each task in dependency order.
5. **Verify** — re-validate the spec, confirm every task closed, run the full suite.
6. **Archive & Sync** — `openspec archive` folds the change into the living specs; close the epic.

**Smaller change, don't need the full ceremony?** The skill has a lighter variant: skip straight to Phase 1's graph refresh for context, then track the work as a single beads task — no OpenSpec proposal, no multi-phase gate. Just say so when you invoke it, or the skill will offer this path itself for a scoped-enough ask.

### Install or fix missing tooling

If `openspec`, `bd`, or `graphify` is missing, or the repo hasn't been initialized for one of them yet:

```
/dev-workflow:setup
```

It reads the `phase0-check.sh` report from session start (or re-derives it if you're invoking mid-session), and — for anything missing or uninitialized — proposes exactly one fix at a time, showing you the exact command before it runs anything. Nothing is installed or initialized without your explicit confirmation, and it never guesses at an install command it isn't confident about.

### Fix a broken credential or MCP server

If a session hits an auth error, an MCP tool won't connect, or you just want a health check:

```
/dev-workflow:preflight
```

It reads the `preflight-check.sh` report from session start (or re-derives it if you're invoking mid-session), live-tests each configured MCP server with one read-only call, and — for anything red — proposes exactly one fix at a time, showing you the exact command before it writes anything. Nothing is applied without your explicit confirmation, and no raw token or secret value is ever printed, only status (valid/expired/missing).

Skills in this plugin are invoked with the `dev-workflow:` prefix — Claude Code namespaces skills by plugin name, so it's `/dev-workflow:dev-workflow`, `/dev-workflow:setup`, and `/dev-workflow:preflight`, not the bare names.

## Prerequisites

- `jq` — required by both SessionStart hooks to format their output; install via your OS package manager if missing
- OpenSpec CLI — `openspec init` in a repo that doesn't have it yet
- [beads](https://github.com/gastownhall/beads) — `bd init`
- graphify — optional, `graphify install && graphify claude install --project --strict && graphify hook install && graphify update .` (or run `/dev-workflow:setup` to do this with per-step confirmation)
- `gh` CLI, authenticated (`gh auth login`) — optional, but `preflight` uses it to diagnose and derive GitHub tokens without asking you to paste one
- `GITHUB_PERSONAL_ACCESS_TOKEN` / `GITLAB_TOKEN` — optional, only checked if set

This plugin never installs software, initializes your repo, or writes to your shell profile without your explicit confirmation for that exact step (the hooks' own local status cache under `~/.claude/dev-workflow/` aside). `/dev-workflow:setup` and `/dev-workflow:preflight` diagnose and propose; you decide what actually runs.

## Install

**From a local checkout (testing):**

```bash
/plugin marketplace add /path/to/claude-dev-workflow
/plugin install dev-workflow@dev-workflow-marketplace --scope user
```

**From GitHub (once published):**

```bash
/plugin marketplace add saradindusengupta/claude-dev-workflow
/plugin install dev-workflow@dev-workflow-marketplace --scope user
```

`--scope user` makes it active in every project on your machine. Use `--scope project` or `--scope local` to opt in per repo instead.

## License

MIT — see [LICENSE](LICENSE).
