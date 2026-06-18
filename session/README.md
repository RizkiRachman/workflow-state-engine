# Session — Runtime State Archive

Per-branch contract snapshots and runtime state for orchestration sessions.
**All files are gitignored** — this directory is regenerated per session.

```
session/
├── state.md             # Append-only chronological state log
├── index.md             # Branch index (status per branch)
├── main/                # Main branch snapshots
│   ├── contract.json
│   ├── state.md
│   └── ...
└── feature/             # Per-feature-branch snapshots
    └── <name>/
        ├── contract.json
        └── state.md
```

## Lifecycle

| Event | Action |
|-------|--------|
| Session start | Load from `session/<branch>/` if resuming; init fresh from `contract/` templates otherwise |
| State transition | Snapshot `contract/` files to `session/<branch>/` via `scripts/snapshot-contract.sh` |
| Session end | Final snapshot → append summary to `session/state.md` → update `session/index.md` |
| Branch switch | Snapshot current branch → checkout → load new branch's session data |

## Why It Exists

Contract files (`contract.json`, `state.md`) mutate on every session. Committing them would
flood git history with noise. The `session/` archive preserves:
- **Audit trail** — every state transition, decision, and blocker recorded
- **Safe resume** — exact state from last session, no reconstruction
- **Discoverability** — `index.md` shows all branches at a glance

## Tooling

```bash
scripts/snapshot-contract.sh                    # Full snapshot
scripts/snapshot-contract.sh --snapshot-only     # Copy files only
scripts/snapshot-contract.sh --summary "..."     # Custom log entry
```