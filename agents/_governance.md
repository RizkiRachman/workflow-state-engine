# Shared Governance — All Agents

This file is included by agent instruction files. It defines common governance rules,
permissions, and protocols that apply to every agent in the workflow-state-engine.

---
## 1. Contract Protocol

All agents **MUST** read the shared JSON envelope (`.opencode/orchestration/contract.json`) at session start:

```lean-ctx
lean-ctx ctx_knowledge recall --key "orchestration-contract" --mode "exact"
```

- If found → extract `decisions.*`, `governance.*`, `retry.issues[]`, `scope.*`, `requirements.*`
- If NOT found (standalone session) → create fresh from `.opencode/orchestration/contract.json`:
  1. Populate `session.task_id` (short slug like `"<agent-type>-standalone-<date>"`)
  2. Populate `session.created_at` (ISO timestamp)
  3. Persist: `lean-ctx ctx_knowledge remember key orchestration-contract value <JSON>`

The envelope is the single source of truth for session state, decisions, and outputs.
All agents read from it; write-capable agents update it with results.

---
## 2. Permissions

| Dimension | Rule |
|-----------|------|
| Shell commands | Use `lean-ctx ctx_shell` for **all** shell commands. `bash`/`snip` are denied in `opencode.json` — triggers permission prompts and blocks automation. |
| File reads | Prefer `lean-ctx ctx_read` (cached, compressed, ~13 tok re-reads). Use `lean-ctx ctx_search` for regex search. Native `read`/`grep` trigger permission prompts. |
| File edits | Use `lean-ctx ctx_edit` (search-and-replace) or `ctx_edit` with `create=true` for new files. Native `write`/`edit` tools are blocked. |
| **Read-only agents** | `system-analyst`, `quality-analyst`, `quality-analyst-learner`, `software-architect`, `developer-explorer`, `developer-librarian`, `developer-council`, `developer-observer` — **MUST NOT edit files**. |
| **Read-write agents** | `developer`, `developer-fixer`, `tech-lead` — may edit files within `scope.included`. |

---
## 3. Session Lifecycle (Contract Archival)

Every orchestration session MUST persist its contract state to the `session/` directory for cross-session traceability and resumption.

### Directory layout

```
contract/                    ← Active contract (mutable, current state)
  contract.json
  contract.schema.json
  state.md
  superpowers-contract.json

session/                     ← Historical archive (append-only state log + per-branch snapshots)
  state.md                   ← Append-only log of ALL state transitions (every session, every branch)
  index.md                   ← Master branch index (one row per branch, latest state per row)
  {branch-name}/             ← Per-branch snapshot for resumption
    contract.json
    contract.schema.json
    state.md
    superpowers-contract.json
```

### Lifecycle Protocol

| Event | Action |
|-------|--------|
| **Session start** | Read git branch → check `session/{branch}/` exists → if yes, resume from there (load contract.json); if no, init fresh from `contract/` template |
| **State transition** | Update `contract/contract.json` → snapshot to `session/{branch}/` via `scripts/snapshot-contract.sh` |
| **Session end** (COMPLETE/BLOCKED) | Run final snapshot → append summary to `session/state.md` → update `session/index.md` with result |
| **Branch switch** | Snapshot old branch (`--branch OLD`) → checkout new branch → load `session/NEW/` if exists |

### Snapshot command

```bash
# Full snapshot (copies contract files + updates state.md + index.md)
bash scripts/snapshot-contract.sh --summary "State: ${STATE} — brief description"

# Files-only (skip index updates for hot-reload scenarios)
bash scripts/snapshot-contract.sh --snapshot-only

# Preview without writing
bash scripts/snapshot-contract.sh --dry-run --verbose
```

### Why

Without per-branch archival, contract files get overwritten when switching branches or resuming sessions. The `session/` archive preserves:
- **Resumability**: Each branch's last state is independently restorable
- **Audit trail**: `session/state.md` grows monotonically — every state transition, ever
- **Discoverability**: `session/index.md` shows all branches with their status at a glance

## 4. Pre-Edit Safety (write-capable agents only)

Before editing **any existing symbol** (function, class, method):

1. **Impact analysis** — `gitnexus_impact({target: "symbolName", direction: "upstream"})`
   - Report blast radius (direct callers, affected processes, risk level)
2. **HIGH/CRITICAL warning** — if impact returns HIGH or CRITICAL risk, **warn the user** before proceeding
3. **Detect changes** — `gitnexus_detect_changes()` before committing to verify only expected files changed
4. **Never rename with find-and-replace** — use `gitnexus_rename` which understands the call graph

---
## 4. Frugality Ladder (Ponytail — before every code decision)

Run this ladder in order before writing ANY code:

1. Does this need to exist? → skip it (YAGNI)
2. Standard library does it? → use it
3. Already-installed dependency? → use it
4. Can this be one line? → one line
5. Only then: minimum code that works

**Rules:** No unsolicited abstractions. No new deps if avoidable. Deletion > addition.
Boring > clever. Fewest files possible. Mark intentional shortcuts with `ponytail:`
comments (ceiling + upgrade path).

**Not sacrificed:** Input validation at trust boundaries, data-loss error handling,
security, accessibility, anything explicitly requested. Non-trivial logic leaves
ONE runnable check (assert-based, no test framework).

---
## 5. Post-Flight Protocol (before commit)

After completing work, run these steps **in order**:

| # | Step | Tool |
|---|------|------|
| 1 | Impact verification | `gitnexus_impact({target, direction: "upstream"})` — confirm blast radius matches expectations. If HIGH/CRITICAL, note in output. |
| 2 | Change detection | `gitnexus_detect_changes()` (or `{scope: "all"}` for staged+unstaged) — verify only expected files changed, no unintended side effects. |
| 3 | Knowledge persistence | `lean-ctx ctx_knowledge remember` — persist gotchas, patterns, decisions (categories: `architecture`, `gotchas`, `conventions`). |
| 4 | STATE.md update | `lean-ctx ctx_edit` on `contract/state.md` — append completed work, update Current Focus, update Known Blockers. |
| 5 | Session save | `ctx_session save` — persist conversation state for resumption across opencode restarts. |

**Exceptions:** Documentation-only changes may skip steps 1, 2, and 4. Config-only changes skip 1, 2.

---
## 6. Communication

- Explain tradeoffs, not just decisions
- Admit unknowns — be clear about what you don't know
- Be **token-efficient**: concise, no filler, no full-file dumps
- Return only what was asked — don't expand scope
- Use fragments where clear, revert to full sentences for security warnings and destructive operations
