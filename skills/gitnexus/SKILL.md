---
name: gitnexus
description: Code intelligence toolkit — impact analysis, code query, safe rename, execution flow tracing, and knowledge graph exploration. Use before editing any symbol, before committing, or when exploring unfamiliar code.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  domain: code-intelligence
---

# GitNexus Code Intelligence

GitNexus provides code intelligence for the goods-price-comparison-service. It indexes symbols, relationships, and execution flows for safe navigation and impact analysis.

## Sub-Skills

| Skill | Purpose |
|-------|---------|
| `gitnexus-exploring` | Understand architecture and execution flows |
| `gitnexus-impact-analysis` | Blast radius before edits |
| `gitnexus-debugging` | Trace bugs and errors |
| `gitnexus-refactoring` | Safe rename, extract, split |
| `gitnexus-guide` | Full tool and resource reference |
| `gitnexus-cli` | Index, status, clean, wiki CLI |

## Key Rules

- Always run `impact()` BEFORE editing any symbol
- Always run `detect_changes()` BEFORE committing
- Never rename with find-and-replace — use `gitnexus_rename`
