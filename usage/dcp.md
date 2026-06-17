# Dynamic Context Pruning (DCP) Usage Guide

> **Plugin**: `@tarquinen/opencode-dcp` ([github.com/Tarquinen/opencode-dynamic-context-pruning](https://github.com/Tarquinen/opencode-dynamic-context-pruning))
>

> **Purpose**: Automatically reduces token usage by compressing closed conversation content, deduplicating tool calls, and purging errored tool inputs.

## Features

### 1. Smart Compress

Replaces closed, stale conversation with high-fidelity technical summaries. Smarter than OpenCode's built-in compaction:

- **Range mode** (default) — compresses contiguous conversation spans
- **Message mode** (experimental) — compresses individual messages surgically

- Nested compression — old summaries preserved inside new ones
- Protected tool outputs preserved (task, skill, todowrite, todoread)

### 2. Deduplication

Removes repeated tool calls (same tool, same args) — keeps only the most recent output. Recalculated when compress runs.

### 3. Purge Errors

Prunes inputs from errored tool calls after 4 turns. Error messages preserved; only large input content removed.

## Slash Commands

| Command | Effect |
|---|---|
| `/dcp` | Show available commands |
| `/dcp context` | Show current session token usage breakdown |
| `/dcp stats` | Cumulative pruning stats across all sessions |
| `/dcp sweep` | Prune all tools since last user message |
| `/dcp sweep 10` | Prune last 10 tools |
| `/dcp manual on` | Disable autonomous context management |
| `/dcp manual off` | Re-enable autonomous management |
| `/dcp compress` | Trigger a single compress execution |
| `/dcp decompress 2` | Restore compression by ID |
| `/dcp recompress 2` | Re-apply a decompressed compression |

## Config File

Lookup order: `~/.config/opencode/dcp.jsonc` > `.opencode/dcp.jsonc` (project overrides global).

### Key Settings

| Option | Default | Effect |
|---|---|---|
| `enabled` | `true` | Master switch |
| `compress.mode` | `"range"` | `"range"` or `"message"` |
| `compress.maxContextLimit` | `100000` | Soft upper threshold |
| `compress.minContextLimit` | `50000` | Soft lower threshold |
| `compress.permission` | `"allow"` | `"allow"`, `"ask"`, or `"deny"` |
| `strategies.deduplication.enabled` | `true` | Remove duplicate tool calls |
| `strategies.purgeErrors.enabled` | `true` | Prune errored tool inputs |
| `pruneNotification` | `"detailed"` | `"off"`, `"minimal"`, or `"detailed"` |

### Protected Tools (never pruned by default)

`task`, `skill`, `todowrite`, `todoread`, `compress`, `batch`, `plan_enter`, `plan_exit`, `write`, `edit`

