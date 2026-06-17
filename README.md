# Workflow State Engine

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

**Contract-driven state machine orchestration engine for AI agent workflows.**

State machine: `INIT -> PLAN -> PLAN_SCORED -> EXECUTE -> EXECUTE_SCORED -> REVIEW -> REVIEW_SCORED -> COMPLETE`

Single source of truth for all AI agents. The canonical agent instruction file is [`agent.md`](agent.md) which serves as `instructions[0]` for every agent.

## Overview

This is a reusable orchestration toolkit for AI agents. It codifies agent collaboration into a state machine, ensuring every output is scored, every decision is tracked, and every session learns from the last.

- **Shared JSON envelope** (`template/contract.json`) — single source of truth for state, decisions, outputs, scoring
- **State machine** — 8 states + BLOCKED: agents transition via the envelope with gates and escalation
- **Scoring pipeline** — three-tier: rule-based checks -> LLM-as-judge -> combined verdict
- **Agent delegation** — orchestrator delegates to system-analyst, developer, quality-analyst
- **Cross-session learning** — lessons and patterns persist via `lean-ctx ctx_knowledge`

## Quick Start

```bash
# Copy toolkit to your project
mkdir -p your-project/.opencode
cp -r agents/ skills/ template/ rules/ usage/ your-project/.opencode/
cp agent.md your-project/AGENTS.md

# Bootstrap symlinks
bash setup.sh

# Run orchestration
lean-ctx ctx_knowledge recall --key orchestration-contract --mode exact
```

## Architecture

```
agents/     -> 11 agent instruction files
skills/     -> 35 skill directories
template/   -> contract.json, state.md, superpowers-contract.json
rules/      -> rules.json (state machine, scoring)
usage/      -> 15 tool usage guides
doc/        -> workflow.md, project.md
config/     -> Plugin configs
```

## State Machine

```
INIT -> PLAN -> PLAN_SCORED -> EXECUTE -> EXECUTE_SCORED -> REVIEW -> REVIEW_SCORED -> COMPLETE

Any phase -> BLOCKED (score < 50 or retry >= 3)
```

Transitions require `score >= 70` for: PLAN_SCORED->EXECUTE, EXECUTE_SCORED->REVIEW, REVIEW_SCORED->COMPLETE.

## Scoring Pipeline

| Tier | Method | Verdict |
|------|--------|---------|
| 1 | Rule-based checks (start 100, deduct for violations) | If < 70 skip Tier 2 |
| 2 | LLM-as-judge (requirements, governance, completeness, edge cases) | 0-100 |
| 3 | Combined: < 50 = BLOCKED, 50-69 = RETRY (max 3), >= 70 = PASS | Final |

## License

MIT (c) 2026 Rizki Rachman