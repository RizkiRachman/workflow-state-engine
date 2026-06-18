# Daily Health Check Protocol

> A self-contained protocol for AI agents to evaluate workflow architecture health.
> Run daily to ensure the codebase stays consistent, healthy, and improves over time.

## How to Use

Copy the **Daily Prompt** (section 4) and paste it to your AI agent. The agent will:
1. Run all 10 health lenses against the live codebase
2. Produce a scored report
3. Flag any regressions or improvements since last check
4. Update session/health-record.md with the result

---

## 1. The 10 Health Lenses

Each lens checks one dimension of system health. Results are weighted into a 0-100 score.

| # | Lens | Weight | What It Checks |
|---|------|--------|---------------|
| 1 | **Contract Integrity** | 15% | `scripts/validate-contract.sh --score` passes on template + active contract |
| 2 | **Knowledge vs File Drift** | 10% | `scripts/drift-detect.sh` — knowledge ↔ session file consistency |
| 3 | **Git Health** | 10% | Stale branches (>7d idle), uncommitted changes, active branch not main |
| 4 | **Script Syntax** | 10% | `bash -n` on all `scripts/*.sh` — no syntax errors |
| 5 | **Agent Doc References** | 10% | Do `agents/*.md` reference scripts that exist? Any dead references? |
| 6 | **Knowledge Persistence** | 10% | `scripts/verify-knowledge.sh` — coverage of decisions, lessons, gotchas |
| 7 | **Git Hooks Active** | 5% | Is `core.hooksPath` set to `.githooks/`? Are hooks executable? |
| 8 | **Session Index vs Reality** | 5% | Do `session/index.md` entries match actual git branches? |
| 9 | **PR Health** | 10% | Open PRs with no activity in >3 days? |
| 10 | **Score Trend** | 15% | Compare today's score against `session/health-record.md` baseline |

---

## 2. Scoring Rules

```
Total = weighted sum of all 10 lens scores

≥ 90  → ✅ HEALTHY — system is sound
70-89 → ⚠️ WARNING — issues to review
< 70  → 🔴 CRITICAL — immediate attention needed
```

### Trend Detection

Compare today's score against the last 3 entries in `session/health-record.md`:

| Pattern | Trend |
|---------|-------|
| Score >= last 3 entries | improving ↗ |
| Score <= last 3 entries | declining ↘ |
| Mixed / flat | stable → |
| First check ever | baseline set |

---

## 3. Implementation — Each Lens in Detail

### Lens 1: Contract Integrity [15pts]

```bash
# Check template
scripts/validate-contract.sh --file contract/contract.template.json --score
exit_code=$?
# 0=PASS (full points), 1=retry (half), 2=BLOCKED (0pts)

# Check active session contract (if branch detected)
BRANCH=$(git branch --show-current)
if [[ -f "session/$BRANCH/contract.json" ]]; then
    scripts/validate-contract.sh --file "session/$BRANCH/contract.json" --score
fi
```

**Scoring**: Template PASS (15pts), template+session both PASS (15pts), template RETRY (7pts), BLOCKED (0pts)

### Lens 2: Knowledge vs File Drift [10pts]

```bash
scripts/drift-detect.sh --branch "$(git branch --show-current)" --verbose
# exit 0 = no drift (10pts), exit 1 = drift detected (0pts)
```

**Scoring**: No drift (10pts), drift (0pts)

### Lens 3: Git Health [10pts]

```bash
# Check uncommitted changes
UNCOMMITTED=$(git status --porcelain | wc -l)

# Check stale local branches (>7 days since last commit)
STALE_COUNT=0
for branch in $(git branch --format="%(refname:short)" | grep -v main); do
    days_since=$(git log -1 --format="%ct" "$branch" 2>/dev/null | xargs -I{} sh -c 'echo $(( ($(date +%s) - {}) / 86400 ))')
    if [[ "$days_since" -gt 7 ]]; then
        STALE_COUNT=$((STALE_COUNT + 1))
    fi
done

# Check current branch
BRANCH=$(git branch --show-current)
[[ "$BRANCH" == "main" ]] && ON_MAIN=true || ON_MAIN=false
```

**Scoring**: 10 base, -3 if on main, -2 per stale branch, -2 if uncommitted changes (min 0)

### Lens 4: Script Syntax [10pts]

```bash
TOTAL=0; PASS=0
for script in scripts/*.sh; do
    TOTAL=$((TOTAL + 1))
    if bash -n "$script" 2>/dev/null; then
        PASS=$((PASS + 1))
    fi
done
```

**Scoring**: All pass (10pts), each fail deducts 2pts (min 0)

### Lens 5: Agent Doc References [10pts]

```bash
# Extract all script references from agent docs
REFERRED=$(grep -ohP 'scripts/[a-z_-]+' agents/*.md | sort -u | sed 's|scripts/||')

# Check each exists
MISSING=0
for ref in $REFERRED; do
    [[ -f "scripts/$ref" ]] || MISSING=$((MISSING + 1))
done

# Also check scripts not referenced by any agent
ALL_SCRIPTS=$(ls scripts/*.sh | xargs -n1 basename | sed 's/\.sh$//')
UNREFERENCED=0
for s in $ALL_SCRIPTS; do
    grep -q "scripts/$s" agents/*.md || UNREFERENCED=$((UNREFERENCED + 1))
done
```

**Scoring**: 10 base, -2 per missing reference, -1 per unreferenced script (min 0)

### Lens 6: Knowledge Persistence [10pts]

```bash
# Run verify-knowledge in dry-run mode
scripts/verify-knowledge.sh --dry-run --all 2>&1

# Extract coverage percentage from output
COVERAGE=$(scripts/verify-knowledge.sh --dry-run --all 2>&1 | grep -oP '[0-9]+%' | tail -1 | tr -d '%')
```

**Scoring**: Coverage ≥ 70% (10pts), 50-69% (5pts), <50% (0pts)

### Lens 7: Git Hooks Active [5pts]

```bash
HOOKS_PATH=$(git config core.hooksPath 2>/dev/null)
PRE_EXEC=$([ -x .githooks/pre-commit ] && echo 1 || echo 0)
POST_EXEC=$([ -x .githooks/post-commit ] && echo 1 || echo 0)
```

**Scoring**: All 3 conditions met (5pts), hooksPath set but missing files (2pts), nothing (0pts)

### Lens 8: Session Index vs Reality [5pts]

```bash
# Extract branch names from session/index.md
INDEX_BRANCHES=$(grep -oP '`[a-z]+/[^`]+`' session/index.md | tr -d '`' | sort -u)

# Compare against actual git branches
GIT_BRANCHES=$(git branch --format="%(refname:short)" | sort -u)

# Flag index entries without live branches
STALE_INDEX=$(comm -23 <(echo "$INDEX_BRANCHES") <(echo "$GIT_BRANCHES") | wc -l)
```

**Scoring**: No stale entries (5pts), each stale entry deducts 1pt

### Lens 9: PR Health [10pts]

```bash
if command -v gh &>/dev/null; then
    STALE_PRS=$(gh pr list --state open --json updatedAt --jq '.[] | select((now - (.updatedAt | fromdate)) > 259200) | .number' 2>/dev/null | wc -l)
fi
```

**Scoring**: No stale PRs (10pts), stale PRs exist (5pts), `gh` not available (5pts partial)

### Lens 10: Score Trend [15pts]

```bash
# Read last score from session/health-record.md
LAST_SCORE=$(grep -oP '\| \d+ \|' session/health-record.md 2>/dev/null | tail -1 | tr -d '| ')

# If no baseline: this run becomes baseline (15pts by default)
# If baseline exists: compare
if [[ -n "$LAST_SCORE" ]]; then
    DROP=$((LAST_SCORE - TODAY_SCORE))
    if [[ DROP -gt 10 ]]; then
        # Regression: 0pts
    elif [[ DROP -gt 5 ]]; then
        # Mild regression: 7pts
    else
        # Stable or improving: 15pts
    fi
fi
```

**Scoring**: No regression >5pts (15pts), 5-10pt drop (7pts), >10pt drop (0pts), first run (15pts)

---

## 4. The Daily Prompt

Copy and paste this entire block to your AI agent for a daily health check:

> ```markdown
> Run daily health check on the Workflow State Engine.
> 
> ## Protocol
> 
> 1. **Read context**: Load `doc/health-check.md` for the full protocol. Load `session/health-record.md` for trend history.
> 2. **Run all 10 lenses** against the live codebase (read-only — no --fix flags):
>    - Lens 1: `scripts/validate-contract.sh --file contract/contract.template.json --score`
>    - Lens 2: `scripts/drift-detect.sh --branch "$(git branch --show-current)" --verbose`
>    - Lens 3: Check stale branches, uncommitted changes, current branch
>    - Lens 4: `bash -n` on all `scripts/*.sh`
>    - Lens 5: Cross-reference agent docs vs scripts
>    - Lens 6: `scripts/verify-knowledge.sh --dry-run --all`
>    - Lens 7: Check `git config core.hooksPath` and hook executability
>    - Lens 8: Compare `session/index.md` branches vs `git branch`
>    - Lens 9: Check open PRs for staleness via `gh pr list`
>    - Lens 10: Compare score against `session/health-record.md` baseline
> 3. **Score**: Apply weights, compute total (0-100), determine verdict (HEALTHY/WARNING/CRITICAL)
> 4. **Trend**: Compare against last 3 entries in `session/health-record.md`
> 5. **Report**: Produce a concise report with:
>    - Score and verdict
>    - Any failures or warnings per lens
>    - Trend direction
>    - Top 1-3 recommendations if score < 90 or declining
> 6. **Persist**: Append result to `session/health-record.md` in this format:
>    
>    ```markdown
>    | 2026-06-18 | 94 | HEALTHY | ↗ improving | No issues |
>    ```
>    
>    Columns: Date | Score | Verdict | Trend | Issues / Notes
> 
> ## Key Constraints
> - Read-only unless persisting the result record — do NOT modify scripts or contracts
> - If `drift-detect.sh` fails, do NOT auto-fix — just flag it
> - If any script is missing, note it but continue with remaining checks
> - If score < 80 OR trend is declining: propose a fix plan (like the 15-gap campaign)
> - If score >= 90 with stable/improving trend: confirm health, suggest 1 optimization
> ```

---

## 5. Health Record Format

Stored in `session/health-record.md`. Append-only chronological table:

```markdown
# Health Check Record

> Daily health scores for the Workflow State Engine.
> Updated after each daily health check.

| Date | Score | Verdict | Trend | Issues / Notes |
|------|-------|---------|-------|---------------|
| 2026-06-18 | 94 | ✅ HEALTHY | — (baseline) | No issues |
| 2026-06-19 | 92 | ✅ HEALTHY | → stable | 1 stale branch, minor drift |
| 2026-06-20 | 88 | ⚠️ WARNING | ↘ declining | validate-contract BLOCKED on session contract — needs investigation |
```

---

## 6. Quick Reference Card

```text
Command: Copy §4 prompt → paste to AI agent
Duration: ~2-3 minutes for AI to run all 10 lenses
Frequency: Daily
Trigger: Any of:
  - "Run daily health check"
  - "/health"
  - "Check system health"

Scoring:  90-100 ✅ HEALTHY
          70-89  ⚠️ WARNING
          < 70   🔴 CRITICAL

Lenses:  Contract(15) + Drift(10) + Git(10) + Syntax(10) +
         AgentDocs(10) + Knowledge(10) + Hooks(5) + Sessions(5) +
         PRs(10) + Trend(15) = 100

Files created/modified: session/health-record.md (appended)
Files read (read-only): All scripts, agents/, session/*, contract/
```

---

*Last updated: 2026-06-18. Built on 15 automation scripts from the workflow-architecture-analysis campaign.*
