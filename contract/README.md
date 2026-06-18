# Contract — Workflow State Engine Definitions

This folder defines the orchestration contract for AI agent workflows.
**All files here are version-controlled definitions** — no runtime state.

| File | Purpose |
|------|---------|
| `README.md` | This file — overview of the contract/ folder |
| `contract.schema.json` | JSON Schema (Draft 2020-12) validating the orchestration envelope |
| `superpowers-contract.json` | Registry of all plugins, skills, and MCP tools available to agents |
| `state.md` | Template for session state tracking |
| `contract.template.json` | Seed envelope with default values — agents use this as the base for new sessions via `lean-ctx ctx_knowledge` |

## Runtime State

Per-session runtime state (contract.json, state.md copies) lives in `session/<branch-name>/`,
which is gitignored. The `scripts/snapshot-contract.sh` script manages checkpoint snapshots.

## Symlink

The `.opencode/orchestration` symlink points to `../contract`, so agents can read definitions
via `.opencode/orchestration/contract.schema.json`.