# Ponytail — Lazy Senior Dev Mode Analysis

**Source:** https://github.com/DietrichGebert/ponytail
**Analyzed:** 2026-06-17
**Stars:** 25.4k ★
**License:** MIT
**Status:** 🟡 BACKLOG

---

## What It Is

A plugin/ruleset that injects a frugality ladder into AI agent reasoning before writing code. Works across 13 agents (Claude Code, Codex, OpenCode, Gemini CLI, Cursor, Windsurf, Cline, Copilot, Aider, Kiro, Pi, Antigravity, OpenClaw). Benchmark: 80-94% less code, 3-6x faster, 47-77% cheaper.

## Core Delivery Mechanisms

- **AGENTS.md** — universal rule file loaded by any agent
- **Agent-specific plugins** — `.mjs` for OpenCode, plugin manifests for Claude Code/Codex
- **Rule files per agent** — `.cursor/rules/`, `.windsurf/rules/`, `.clinerules/`, `.github/copilot-instructions.md`
- **Commands** — `/ponytail [lite|full|ultra|off]`, `/ponytail-review`, `/ponytail-audit`, `/ponytail-debt`, `/ponytail-help`

## The 6-Rung Ladder (Key Innovation)

```
1. Does this need to exist?       → skip it (YAGNI)
2. Standard library does it?      → use it
3. Native platform feature?       → use it
4. Already-installed dependency?  → use it
5. Can this be one line?          → one line
6. Only then: minimum code that works
```

**Rules:** No unsolicited abstractions. No new deps if avoidable. Deletion over addition. Boring over clever. Fewest files possible.

## `ponytail:` Comment Convention

Every intentional shortcut must be marked with a `ponytail:` comment naming the ceiling and upgrade path:

```java
// ponytail: global lock, wont scale past 10 concurrent. Upgrade: ConcurrentHashMap + stripe locks
```

Creates a harvestable debt ledger via `/ponytail-debt`.

## What is NOT Sacrificed

- Input validation at trust boundaries
- Error handling that prevents data loss
- Security / accessibility
- Anything explicitly requested by the user
- Non-trivial logic must leave ONE runnable check (assert-based, no frameworks)

---

## Gap Analysis vs Our Stack

### What We Already Have

| Our Asset | Coverage |
|-----------|----------|
| `agent.md` Section 6 — YAGNI/git safety rules | Partial — written but no decision ladder |
| `simplify` skill | Yes — but no debt comment convention |
| `quality-analyst` code review | No over-engineering lens |
| Scoring Pipeline (Tier 2 LLM-as-Judge) | No simplicity check criteria |
| Spec Gate (GWT before EXECUTE) | No simplicity gate |

### What We are Missing

| Gap | Priority | Effort | Target |
|-----|----------|--------|--------|
| **6-Rung Decision Ladder** | 🔴 P1 | Low | `agent.md` Section 5 |
| **`ponytail:` Debt Comments** | 🟡 P2 | Low | `skills/simplify/` |
| **Over-Engineering Review** | 🟡 P2 | Low | `agents/quality-analyst.md` + Scoring Tier 2 |
| **Intensity Modes** | 🟢 P3 | Medium | contract envelope + `agent.md` |
| **Debt Ledger Harvesting** | 🟢 P3 | Low | `agents/quality-analyst-learner.md` |

---

## Recommended Actions

### ✅ Do Now — Install Ponytail plugin

Add to `opencode.json` plugin array. Zero-effort. Run 1 week, measure impact.

### ✅ Do Now — Copy the 6-rung ladder into `agent.md`

Costs ~5 lines. Proven across 13 agents.

### 🟡 Next — Add `ponytail:` convention to `simplify` skill

Makes tech debt visible and harvestable.

### 🟡 Next — Add over-engineering lens to quality-analyst

Our review covers security, perf, DevOps — but not YAGNI violations or bloat.

### 🟢 Later — Intensity modes

If the ladder proves valuable, add `lite/full/ultra` to envelope.

---

## Relationships

- `doc/reports/toolkit-architecture-gap-analysis-2026-06-17.md` — broader toolkit gaps
- `doc/gap/duplication-analysis.md` — overlapping instruction files
- `skills/simplify/` — would host `ponytail:` debt convention
- `agents/quality-analyst.md` — would host over-engineering review
- `agent.md` — target for 6-rung ladder

---

*Move to `tasks/planning/` when ready to begin implementation.*