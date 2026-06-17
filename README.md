# Workflow State Engine

**Contract-driven state machine orchestration engine for AI agent workflows.**

## What It Is

A state machine orchestrator that:

- Drives agents through `INIT → PLAN → PLAN_SCORED → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE`
- Uses a **shared JSON envelope** (`contract.json`) as the single source of truth for state, decisions, and outputs
- Scores every agent output through a **three-tier scoring pipeline** (rule-based checks → LLM-as-judge → combined verdict)
- Handles retries, blockades, and escalation automatically
- Tracks metrics, lessons learned, and cross-session knowledge

This file is `authoritative` but the canonical agent instruction file is [`agent.md`](agent.md) which serves as `instructions[0]` for every agent.

## Architecture

```
agents/     → 11 agent instruction files (tech-lead, developer, quality-analyst, etc.)
skills/     → 35 skill directories (spec-driven-development, qa-expert, java-developer, etc.)
template/   → contract.json, superpowers-contract.json, state.md
rules/      → rules.json (state machine, scoring thresholds)
doc/        → workflow.md, project.md, gap analysis
usage/      → 15 tool usage guides (lean-ctx, gitnexus, firecrawl, postgres, etc.)
config/     → Plugin configuration (vibeguard, opencode-skillful)
```

## Quick Start

```bash
# Bootstrap a new project with the orchestration template
cp -r agents/ skills/ template/ rules/ usage/ your-project/.opencode/
cp agent.md your-project/AGENTS.md
```

## State Machine

```
INIT → PLAN → PLAN_SCORED → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE
                  ↓              ↓               ↓              ↓
              BLOCKED ← ← ← ← RETRY ← ← ← ← (score < 50 or attempts >= 3)
```

See [`template/contract.json`](template/contract.json) for the canonical contract schema and [`doc/workflow.md`](doc/workflow.md) for the full state machine, scoring pipeline, and validation rules.

## License

MIT
