---
name: dev-workflow
description: This skill should be used when planning and shipping a scoped change in a repo with OpenSpec for proposals and beads for tracking. Walks the 6-phase dev-workflow cycle (refresh/explore → propose → track → implement → verify → archive); lighter single-task variants and optional graphify integration are also supported.
---

# Dev Workflow: OpenSpec + Beads + Graphify

A repeatable cycle for planning and shipping a scoped change, chaining three tools: **OpenSpec** (spec-driven change proposals), **beads** (`bd`, dependency-aware issue tracking), and **graphify** (codebase knowledge graph, optional).

## Phase 0: Prerequisites

This plugin's `SessionStart` hook already printed a prerequisite report. Before continuing, confirm:

- `openspec` CLI is installed and `openspec/` exists in this repo (run `openspec init` if not).
- `bd` CLI is installed and `.beads/` exists in this repo (run `bd init` if not).
- (Optional) `graphify` CLI is installed and `graphify-out/graph.json` exists, for codebase-graph-backed context (run `graphify install && graphify claude install --project --strict && graphify hook install` if not, then build the initial graph with `/graphify .` — safe to skip if the repo is small).
- (Optional, separate decision) if `claude-mem` is also installed in this repo, treat it as passive background capture only — this workflow's curated-memory channel is `bd remember`/`bd prime` (see Phase 3), not claude-mem. Don't let both compete for the same job.

If a required tool is missing, stop and tell the user what to install before proceeding. Do not fake the workflow without it.

If the preflight hook reports show anything red (✗) — a missing MCP server credential, an expired token, `gh` not authenticated — run `/dev-workflow:preflight` to diagnose and (with your confirmation) repair it before continuing. Don't work around a red preflight item manually; let it fix the root cause once.

Add churny, cache-busting artefacts to `.claudeignore` if not already present — `graph.json`, `graphify-out/`, `.beads/embeddeddolt/` — since every write to them invalidates Claude Code's prompt cache. (Note: `graphify-out/` should still be committed to git as a shared baseline for teammates and across sessions, despite being in `.claudeignore`.)

## Phase 1: Refresh & Explore (graphify + OpenSpec)

1. Refresh the graph: `graphify update .` (or `/graphify . --update`) — cheap, AST-only, and everything downstream is more useful when it's current.
2. Explore before proposing anything: run `/opsx:explore` as a no-stakes thinking partner. This is the highest-value step in the cycle — don't skip it under time pressure.
3. Query the graph mid-exploration (`graphify query "..."`, `graphify explain "<Entity>"`) so options are weighed against real structure, not guesses.
4. If a curated-memory tool is in use for this repo (`bd remember`/`bd prime`), check it for prior art on this exact ground before proposing — "have we tried this and abandoned it?"

## Phase 2: Propose (OpenSpec)

1. `openspec new change <change-name>` — kebab-case, one change per cohesive unit of work.
2. Author `proposal.md` (what/why), `specs/<capability>/spec.md` (delta spec: `## Purpose` + `## ADDED Requirements`), `design.md` if there are non-obvious technical decisions, and `tasks.md` grouped as `## N. <Group Name>` headings — this grouping becomes the beads task breakdown in Phase 3.
3. `openspec validate --changes <change-name> --strict` — must pass before moving on.

## Phase 3: Track (beads)

OpenSpec owns the spec and the definition of done; beads owns live execution state. Do not use `/opsx:apply` as the loop driver — it competes with this phase for the same job, and this workflow standardizes on beads instead.

1. Create the epic: `bd create --title="<change-name>" --description="<why, from proposal.md>" --type=feature`
2. Create one child task per `## N. Group` heading in `tasks.md`: `bd create -f tasks.md --parent <epic-id>`. **`--parent` is silently ignored when combined with `-f`** — follow up per generated task with `bd update <task-id> --parent <epic-id>`. Beads' hierarchical IDs (`bd-a3f8` → `bd-a3f8.1`) keep the OpenSpec change and its beads visibly linked.
3. Chain dependencies in the order the groups must land: `bd dep add <later-task-id> <earlier-task-id>` (reads as "later depends on earlier").
4. `bd remember` the epic-ID ↔ change-slug mapping (e.g. `bd remember "<change-name> tracked under <epic-id>"`) so a future session can reconnect them via `bd prime`.

## Phase 4: Implement

Per session, before touching any task:

1. `bd prime` — reload curated memory and workflow state; beads compacts old closed tasks so this never bloats context.
2. `bd ready` — see what's unblocked.

For each task, in dependency order:

1. `bd update <task-id> --claim`
2. Write the code and tests for that task's group.
3. Run this repo's own test/build/lint commands — check its README or package manifest, don't assume a stack.
4. Query the graph for the code each task touches (`graphify explain "<Entity>"` / `graphify path "A" "B"`) — it already reflects what earlier tasks in this cycle wrote, since the graphify hook rebuilds it on every commit.
5. `bd close <task-id> --reason="<one line: what changed and why>"`
6. Commit with a message describing the *why*, not just the *what*.

## Phase 5: Verify

1. `openspec validate --changes <change-name> --strict` again — the delta spec must still validate after implementation.
2. Confirm every beads task under the epic is closed: `bd show <epic-id>`.
3. Run the full test suite once more at the change boundary, not just per-task.

If any of these fail, stop and return to Phase 4 — do not proceed to Phase 6 with an unresolved failure.

## Phase 6: Archive & Sync

1. Archive and sync the delta spec: `openspec archive <change-name> --yes` — this merges `## ADDED Requirements` into the main spec tree and archives the change atomically.
2. Close the epic: `bd close <epic-id> --reason="<summary>"`.
3. If graphify is set up: `graphify update .` (AST-only, no API cost) to keep the knowledge graph current.

## Notes

- Never skip Phase 0. A missing `bd doctor` clean bill or a stale `openspec validate` is cheaper to fix before Phase 2 than after Phase 4.
- If told a beads issue "is fixed" but the underlying file/code hasn't been verified in *this* session, re-check before closing it — issue-tracker state and code state can drift.
- This skill assumes one cohesive change per cycle. If a request spans multiple independent subsystems, split into multiple OpenSpec changes and multiple beads epics up front rather than one giant one.
- **Lighter variant:** for changes that don't warrant full spec ceremony, skip Phases 2, 3, 5, and 6 entirely — use Phase 1's graph refresh for comprehension and a single beads task for the work. Reserve the full flow for changes substantial enough to need an agreed spec.
- **Multi-agent variant (not covered by this skill):** partitioning beads tasks across parallel agents by graph community, and syncing a shared backlog via `bd dolt push`/`bd dolt pull`, is deliberately out of scope for this version — see the plan's Future Work section.
- **Insights loop:** if `/dev-workflow:preflight` reports the same failure three runs running, it already suggests filing a beads issue (see its Step 5). If `/insights` (a separate tool, if installed — not part of this plugin) surfaces a recurring friction pattern on its own — not just credential/MCP issues — treat that the same way: file it as `bd create --type=chore --label=infra` rather than letting it repeat. Infra friction is backlog work like anything else.
