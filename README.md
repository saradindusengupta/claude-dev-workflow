# dev-workflow (Claude Code plugin)

A Claude Code plugin bundling two skills and two `SessionStart` hooks:

- **`dev-workflow` skill** — a repeatable refresh/explore -> propose -> track -> implement -> verify -> archive cycle, chaining three tools:
  - **OpenSpec** — spec-driven change proposals
  - **beads** (`bd`) — dependency-aware issue tracking
  - **graphify** — optional codebase knowledge graph
- **`preflight` skill** — diagnoses and (with your confirmation) repairs credential and MCP server issues: expired tokens, missing `gh` auth, unreachable MCP servers.

## What it does

On session start, the bundled hooks check (1) whether `openspec`, `bd`, and `graphify` are installed and initialized in the current repo, and (2) whether `gh` is authenticated, `GITHUB_PERSONAL_ACCESS_TOKEN`/`GITLAB_TOKEN` are set and valid, and which MCP servers are configured — reporting what's missing or broken in both cases. Invoke `/dev-workflow:dev-workflow` (or let it auto-trigger) to run the full cycle for a scoped change; invoke `/dev-workflow:preflight` any time a session hits an auth or MCP connectivity error. Skills in this plugin are invoked with the `dev-workflow:` prefix, since Claude Code namespaces skills by plugin name. `preflight-check.sh` makes outbound network requests on every session start — to configured MCP servers (via `claude mcp list`) and to `api.github.com`/`gitlab.com` (to validate tokens) — and caches their results locally under `~/.claude/dev-workflow/` to keep subsequent session starts fast.

## Prerequisites

- `jq` — required by both SessionStart hooks to format their output; install via your OS package manager if missing
- OpenSpec CLI — `openspec init` in a repo that doesn't have it yet
- [beads](https://github.com/gastownhall/beads) — `bd init`
- graphify — optional, `graphify install && graphify claude install --project --strict && graphify hook install`, then build the graph with `/graphify .`
- `gh` CLI, authenticated (`gh auth login`) — optional, but `preflight` uses it to diagnose and derive GitHub tokens without asking you to paste one
- `GITHUB_PERSONAL_ACCESS_TOKEN` / `GITLAB_TOKEN` — optional, only checked if set

This plugin does **not** install these tools, auto-initialize them in your repo, or write to your shell profile without asking first — it only checks, reports, and proposes. You decide whether to set each one up and confirm every repair `preflight` suggests.

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
