# Ponytail — Frugality Ladder Plugin

**Ponytail** is a laziness-optimized code frugality system. It injects a 6-rung decision ladder into every agent's reasoning, reducing unnecessary code by 80-94%. Think of it as a senior dev who asks "do we even need this?" before writing anything.

## Quick Start

### 1. Enable the plugin

The plugin is already registered in `opencode.json`:

```json
"plugin": [
  ".opencode/plugins/ponytail.mjs"
]
```

It activates automatically on next OpenCode restart.

### 2. Set your intensity

```
/ponytail full       ← default: full ladder + rules
/ponytail lite       ← brief YAGNI reminder only
/ponytail ultra      ← strict enforcement + pre-commit checklist
/ponytail off        ← disable entirely
```

Mode is persisted across sessions.

### 3. Use the ladder

The 6-rung frugality ladder runs **before every code decision**:

```
1. Does this need to exist?       → skip it (YAGNI)
2. Standard library does it?      → use it
3. Native platform feature?       → use it
4. Already-installed dependency?  → use it
5. Can this be one line?          → one line
6. Only then: minimum code that works
```

### 4. Mark debt with `ponytail:` comments

When you take an intentional shortcut, document the ceiling and upgrade path:

```java
// ponytail: global lock, wont scale past 10 concurrent. Upgrade: ConcurrentHashMap + stripe locks
```

Run `/ponytail-debt` to harvest all `ponytail:` comments into a structured report.

---

## Features

### `/ponytail` Command

| Mode | What it does | When to use |
|------|-------------|-------------|
| `off` | No injection | Debugging, production firefighting |
| `lite` | Brief YAGNI reminder | Simple, well-understood tasks |
| `full` | Full 6-rung ladder + rules | Default. General development |
| `ultra` | Ladder + strict rules + perfectionism check | High-risk production code, refactors |

### 6-Rung Frugality Ladder

The core of ponytail. Always ask:

| # | Question | Action |
|---|----------|--------|
| 1 | Does this need to exist? | Skip it (YAGNI) |
| 2 | Standard library does it? | Use it |
| 3 | Native platform feature? | Use it |
| 4 | Already-installed dep? | Use it |
| 5 | Can this be one line? | One line |
| 6 | Only then | Minimum code that works |

### Enforcement Rules

- **No unsolicited abstractions** — don't build for "what if" scenarios
- **No new dependencies unless unavoidable** — check stdlib, platform, existing deps first
- **Deletion > addition** — removing code is better than adding code
- **Boring > clever** — simple, obvious, and easy to remove later
- **Fewest files possible** — prefer inline over extraction
- **Mark shortcuts with `ponytail:`** — document the ceiling and upgrade path
- **ONE runnable check** — non-trivial logic needs exactly one assert-based verification; no test framework

### What is NOT Sacrificed

- Input validation at trust boundaries
- Error handling that prevents data loss
- Security vulnerabilities
- Accessibility
- Anything explicitly requested by the user

### `ponytail:` Debt Convention

Format for marking intentional shortcuts:

```java
// ponytail: <what the ceiling is>, Upgrade: <what to replace it with>
```

Examples:

```java
// ponytail: global lock, wont scale past 10 concurrent. Upgrade: ConcurrentHashMap + stripe locks
// ponytail: inline SQL, wont survive schema changes. Upgrade: query builder with migration plan
// ponytail: hardcoded timeout 30s, not configurable. Upgrade: env-var or config file
```

Debt can be harvested with `/ponytail-debt`:

```
/ponytail-debt
> Found 3 ponytail debt items:
> 1. workflow-state-engine/src/main/java/org/example/LockService.java:15 — global lock
> 2. workflow-state-engine/src/main/java/org/example/UserRepo.java:42 — inline SQL
> 3. workflow-state-engine/src/main/java/org/example/HttpClient.java:8 — hardcoded timeout
```

### Over-Engineering Check

The quality-analyst agent runs this checklist during review (see `agents/quality-analyst.md`):

- Is every abstraction justified? Any YAGNI violations?
- Could stdlib or existing deps replace any custom code?
- Any unnecessary indirection (factories, interfaces with one impl, over-abstracted patterns)?
- Are there `ponytail:` debt comments? If so, are the ceilings and upgrade paths documented?
- Could any file be eliminated entirely?
- Are any new dependencies avoidable?

### Scoring Integration

The scoring pipeline (`rules/rules.json`) includes:

- **SIMPLICITY_001 rule** (HIGH severity): Detects unnecessary abstractions, unused deps, over-engineering
- **over_engineering_deduction: 15**: Tier 1 scoring deduction for YAGNI violations

---

## Project Integration Points

| File | What it adds | Reference |
|------|-------------|-----------|
| `agent.md` §5 | 6-rung frugality ladder, rules, exceptions | Cross-references `skills/simplify/SKILL.md` for debt convention |
| `agents/quality-analyst.md` | Over-engineering check checklist | 6-question review checklist |
| `rules/rules.json` | SIMPLICITY_001 rule, over_engineering_deduction | Scoring pipeline Tier 1 |
| `skills/simplify/SKILL.md` | Ponytail Debt Convention section | `ponytail:` comment format, debt harvesting |
| `.opencode/plugins/ponytail.mjs` | Plugin (self-contained ESM) | Intensity modes, system prompt injection, mode persistence |

## Comparison: Upstream vs Our Stack

| Feature | Upstream (DietrichGebert/ponytail) | Ours |
|---------|-----------------------------------|------|
| 6-rung ladder | Full implementation | ✅ Integrated into `agent.md` |
| `/ponytail <mode>` | Built-in | ✅ Self-contained plugin |
| Mode persistence | Flag file | ✅ `~/.config/.ponytail-active` |
| Debt comments | `/ponytail-debt` command | ✅ Convention in `simplify/SKILL.md` |
| Over-engineering review | Full review checklist | ✅ In `quality-analyst.md` |
| Scoring integration | SIMPLICITY_001 | ✅ In `rules/rules.json` |
| Intensity modes | off, lite, full, ultra | ✅ All 4 modes |
| Perfectionism check | ultra mode | ✅ In plugin |
| Cross-agent portability | 13 agents | ✅ OpenCode-first, package.json standard |
| Pre-commit CI hooks | Yes | 🟡 Not yet implemented |

## Troubleshooting

**Plugin not activating?**
- Check `opencode.json` has `".opencode/plugins/ponytail.mjs"` in the plugins array
- Restart OpenCode after adding/changing plugins
- Check `node --check .opencode/plugins/ponytail.mjs` for JS syntax errors

**Mode not persisting?**
- Mode is stored in `~/.config/.ponytail-active`
- If the file is unwritable, falls back to default mode (`full`)

**Plugin conflicts?**
- Disable with `/ponytail off` or remove from `opencode.json`

## Related

- [`skills/simplify/SKILL.md`](../skills/simplify/SKILL.md) — simplify skill with debt convention
- [`agents/quality-analyst.md`](../agents/quality-analyst.md) — over-engineering review checklist
- [`rules/rules.json`](../rules/rules.json) — scoring rules with SIMPLICITY_001
- [`agent.md`](../agent.md) — 6-rung frugality ladder in §5
