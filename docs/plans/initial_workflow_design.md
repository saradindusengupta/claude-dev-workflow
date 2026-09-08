# Claude Code Development Workflow

Revised to incorporate claude-mem as a conditional fourth layer. The core structure is unchanged; what changes is the bootstrap ordering, the context budget discipline, and one new decision you must make explicitly.

## 1. Design principle

Each tool is a context offload for a different category of state. The workflow is optimised when Claude Code's window holds only what the current step needs.

| Layer | Tool | State held | Status |
|---|---|---|---|
| Codebase comprehension | **graphify** | What exists, how it connects | Core |
| Intent / requirements | **OpenSpec** | What we agreed to build, and why | Core |
| Task / execution state | **beads** | Done, claimed, blocked | Core |
| Episodic history | **claude-mem** | What was tried, what failed | **Trial only** |

Two decisions must be settled before you start, because each involves two tools wanting the same job:

**Decision A — who drives execution?** OpenSpec's `/opsx:apply` and beads both want to be the task list. Resolution: **OpenSpec owns the spec and the definition of done; beads owns live execution state.** Generate beads issues *from* `tasks.md` once, at approval time, and drive implementation through the beads `ready → claim → close` loop. Do not use `/opsx:apply` as the loop driver. This suits long-horizon and parallel-agent work.

**Decision B — who owns curated memory?** beads has `bd remember` → `bd prime` (deliberate, curated). claude-mem captures everything automatically. These are competing philosophies, not complementary features. Pick one and stay with it. Recommended: **keep `bd remember` as the curated channel; treat claude-mem as passive background capture only.** Running both means two memory streams injecting at session start, which is how they start contradicting each other.

## 2. Phase 0 — One-time bootstrap

**Install order matters.** claude-mem auto-generates `CLAUDE.md` files in project folders and installs five lifecycle hooks; graphify hand-installs a `CLAUDE.md` section and a `PreToolUse` hook; beads writes `AGENTS.md`. Install the three core tools first, claude-mem last, then audit.

```bash
# 1. graphify — package is graphifyy (double-y); command is graphify
uv tool install graphifyy
graphify install
graphify claude install --project --strict   # CLAUDE.md guidance + PreToolUse hook
graphify hook install                        # rebuild graph on every commit (AST-only, free)

# 2. OpenSpec
npm i -g @fission-ai/openspec
openspec init
openspec config profile                      # expanded profile → adds /opsx:verify

# 3. beads
bd init                                      # writes AGENTS.md, installs Claude integration
bd setup claude

# 4. claude-mem — LAST, and only if you're running the trial
npx claude-mem install
```

**Then audit the instruction files immediately.** Open `CLAUDE.md` and `AGENTS.md` and confirm graphify's query-first guidance and beads' workflow section both survived. Re-run `graphify claude install --project --strict` if claude-mem overwrote anything. Repeat this check after every claude-mem update.

**Tune claude-mem's context injection down hard.** The default injects context from the last ten sessions at every session start. That is far too much for this stack and pushes directly against the context hygiene the rest of the workflow depends on. Reduce it via the context-configuration settings, and measure session-start token cost before and after.

**Set context hygiene.** All four tools write churny artefacts into the workspace; every write invalidates Claude Code's prompt cache and forces a re-upload on the next turn.

```gitignore
# .claudeignore
graph.json
graphify-out/
.beads/embeddeddolt/     # binary Dolt DB — churns on every claim/close
.claude-mem/             # observation DB — writes constantly
```

**Commit the baseline** so every session and teammate starts from the same map:

```
/graphify .
# commit graphify-out/, the openspec/ scaffold, and the beads DB
```

## 3. Phase 1 — Per-feature loop

**Step 1 — Refresh understanding (graphify).**
`/graphify . --update` re-extracts only changed files. Cheap, and everything downstream depends on it being current.

**Step 2 — Explore, graph-informed (OpenSpec + claude-mem).**
Run `/opsx:explore` as a no-stakes thinking partner. Two augmentations here, and this is the highest-value step in the whole loop:
- Query the graph mid-exploration (`graphify query "what connects auth to billing?"`) so options are weighed against real structure rather than guesses.
- **Ask claude-mem whether this ground has been covered before** — "have we tried this approach and abandoned it?" Recall of past dead ends is the one thing the three core tools cannot do, and it is the primary justification for the trial.

**Step 3 — Propose (OpenSpec).**
`/opsx:propose <feature>` produces the change folder: `proposal.md`, `specs/`, `design.md`, `tasks.md`. Review and agree the spec here, before any code is written.

**Step 4 — Seam 1: port `tasks.md` into beads.**
No native bridge exists, so instruct Claude Code explicitly:

> "Read `openspec/changes/<slug>/tasks.md`. Create a beads epic for this change, then create one bead per task as a child (hierarchical IDs), adding `bd dep add` edges so a task blocks the ones depending on it. Put the change slug `<slug>` in each bead's description, and run `bd remember` to record the epic-ID ↔ change-slug mapping."

Hierarchical IDs (`bd-a3f8` → `bd-a3f8.1`) keep the OpenSpec change and its beads visibly linked; the `bd remember` line lets a future session reconnect them via `bd prime`.

**Step 5 — Execute (beads-driven).** Per session:

```bash
bd prime                    # reload curated memory + workflow state
bd ready                    # only unblocked, claimable tasks
bd update <id> --claim      # atomic claim
# implement — query the graph for the code each task touches:
#   graphify explain "RateLimiter"  /  graphify path "A" "B"
bd close <id>               # releases downstream blockers → new bd ready items
```

Because `graphify hook install` rebuilds the graph on every commit, later tasks query a graph that already reflects the code earlier tasks wrote. That compounding freshness is the strongest synergy in the stack.

**Step 6 — Seam 2: verify, then archive (OpenSpec).**
Once the epic's beads are closed, check the implementation against the agreed spec — `/opsx:verify` if you enabled the expanded profile, otherwise a manual diff review against `specs/`. Then `/opsx:archive` folds the change into the living specs so the repo's description of current behaviour stays accurate.

## 4. Multi-agent variant

For parallel Claude Code sessions across git worktrees on one backlog:

- **Partition work by graph community.** `graphify prs --conflicts` surfaces PRs sharing graph communities as merge-order risk. Use the same signal *proactively*: assign beads tasks from *different* graph communities to different agents. This is a graphify → beads optimisation with no equivalent in either tool alone.
- **Conflict-free claiming.** beads' hash-based IDs and atomic `bd update --claim` mean parallel agents never collide on IDs or double-claim. Sync the shared backlog with `bd dolt push` / `bd dolt pull`.
- **Union-merged graph.** graphify's git merge driver union-merges `graph.json`, so parallel commits never leave conflict markers.
- **claude-mem does not help here.** Cross-machine shared memory requires CMEM Cloud, which is excluded — see §6.

## 5. Cross-cutting rules

- **Query-first, always.** Let the strict hook and `CLAUDE.md` guidance push the agent to `graphify query` before it greps or reads files. On a mixed repo, `--code-only` gives a fast AST-only pass with no LLM cost. Note the strict hook fires at most once per session, so it will not obstruct the file-heavy implementation phase.
- **Clear context before implementation.** OpenSpec's own guidance. Start execution with a clean window; use Opus 4.7 for both planning and implementation.
- **Watch the hook stack.** You are now running four sets of Claude Code hooks, including claude-mem's `PostToolUse` on *every* tool execution. Expect added per-call latency, and note that claude-mem will faithfully record your `bd ready` / `graphify query` command noise as observations unless filtered.
- **`bd prime` every session.** beads compacts old closed tasks so execution history never bloats context.

## 6. Constraints on claude-mem

These are conditions of the trial, not suggestions.

- **Local engine only.** No account, no cloud sync. The engine is Apache-2.0 and runs entirely on your machine; CMEM Cloud mirrors the observation database off-machine.
- **Never through CMEM Cloud for client work.** A `PostToolUse` hook recording every tool execution will capture query results, schema details, and potentially row-level data. For enterprise client engagements that database must not leave your machine without a security review. The $333/seat/month team tier is also hard to justify against that risk.
- **Use `<private>` tags rigorously** on anything client-data-adjacent, and confirm what the hook actually persists before running it against a production data layer.
- **Treat the vendor's quantitative claims as unverified.** The cmem.ai landing page carries contradictory and evidently unpopulated figures (both "92.1k" and "0" GitHub stars; both "11" and "0" bundled skills; "~0% lower agent cost"). The technical documentation is specific and plausible; the marketing is not. Verify the repo's actual activity yourself.
- **Kill criterion — two weeks.** Does semantic recall of a past decision or dead end save you real work at least a few times? If not, uninstall. The marginal value over `bd remember` plus graphify's `reflect`/`LESSONS.md` will not justify a fourth hook layer.

## 7. Session cheat-sheet

| Stage | Command(s) | Tool |
|---|---|---|
| Refresh graph | `/graphify . --update` | graphify |
| Explore | `/opsx:explore` + `graphify query …` + recall past dead ends | OpenSpec + graphify + claude-mem |
| Author spec + tasks | `/opsx:propose <feature>` | OpenSpec |
| **Seam 1:** tasks → beads | `bd create` epic + child beads, `bd dep add` | manual glue |
| Execute | `bd prime` → `bd ready` → `bd update --claim` → (`graphify explain/path`) → `bd close` | beads + graphify |
| **Seam 2:** verify + archive | `/opsx:verify` → `/opsx:archive` | OpenSpec |

## 8. Known limitations

**The two seams are manual by design.** There is no built-in integration between any of these tools. The `tasks.md` → beads port and the verify-before-archive step are conventions you enforce through instructions to Claude Code, not automation you can rely on.

**Instruction-file contention is ongoing, not one-off.** Four tools writing to `CLAUDE.md` / `AGENTS.md` and installing hooks means the audit in §2 must be repeated after any re-init or update.

**Overlapping memory features.** graphify has its own reflection loop (`save-result` → `reflect` → `LESSONS.md`, plus a work-memory overlay tagging nodes preferred/tentative/contested). That overlaps claude-mem, and is arguably better targeted because it anchors lessons to code entities rather than free-floating observations. If you drop claude-mem, invest in this instead.

**Lighter variant.** For changes that do not warrant full spec ceremony: skip OpenSpec entirely, use `/graphify` for comprehension and beads for the task loop. Reserve the full flow for features substantial enough to need an agreed spec.

Sources: [gastownhall/beads](https://github.com/gastownhall/beads), [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec), [Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify), [claude-mem docs](https://docs.claude-mem.ai/introduction), [cmem.ai](https://cmem.ai/).
