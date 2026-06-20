# Improvement Plan — Contract Validation & Test Framework

## What Was Done

### Test Framework
- **contract-lifecycle-test.sh**: 17 tests covering:
  - JSON validity (Test 1-2)
  - State field validation (Tests 3-4)
  - Nested field presence (Test 5)
  - Content quality at various states (Tests 6, 10-12)
  - State transition validation (Tests 6b, 7-9)
  - **Scope consistency** (Tests 13-16) — new

### Validator (validate-contract.sh)
- **Hard-block on missing/invalid state** (Step 1.5) — state is critical, missing it = BLOCKED immediately
- **Scope consistency checks** (Step 6b):
  - `parallel_eligible=true` → `max_parallel_agents >= 1`
  - `scope.included` / `scope.excluded` overlap detection
  - `shard_id` requires `parallel_eligible=true`
  - `parallel_instances` non-empty when `parallel_eligible=true`
  - `shard_id` must exist in `parallel_instances`
- **Field-name alignment**: Validator and template now share canonical field names (`current_guidance`, `previous_blockers`, `current_phase`, `W_threshold`, `cur_session_usage`)
- **jq multi-result fix**: `[select(...)][0]` to handle multiple matching transitions in rules.json

### Schema (contract.schema.json)
- Added `scope.shard_id` (string) and `scope.parallel_instances` (string array)

### Bug Fixes
- Lowercase `transition` → `[Tt]ransition` in test grep patterns (ANSI codes masked capital T)
- `set_field()` test helper: `true`/`false` parsed via `json.loads()` instead of raw Python eval
- `run_check()` in validator now uses proper `if/else` branch — no double execution

## Next Improvements (Roadmap)

### Short Term (Next Session)

| Priority | Item | Area | Effort |
|----------|------|------|--------|
| P0 | **Add `--score` mode output hardening** — ensure score mode outputs ONLY a number (no stray logs) | validate-contract.sh | S |
| P1 | **Bash `check_scope_consistency` cleanup** — replace inline Python with jq for simple checks | validate-contract.sh | S |
| P2 | **Add `--max-depth` to validator** — skip deep nested checks in quick CI mode | validate-contract.sh | M |
| P3 | **Schema coverage audit** — compare template vs schema; flag missing field definitions | contract/ | M |

### Medium Term

| Priority | Item | Area | Effort |
|----------|------|------|--------|
| P1 | **Parallel execution test** — add scope-related scenarios (parallel dispatch conflicts) | parallel-execution-test.sh | M |
| P2 | **Integration test harness** — full 9-state cycle end-to-end test (INIT → COMPLETE) | test/ | L |
| P3 | **Validator plugin system** — allow per-repo custom validation rules via `rules/` | validate-contract.sh | XL |
| P4 | **Score analytics** — track score history across contract transitions for drift detection | audit-observability skill | M |

### Long Term

| Priority | Item | Area | Effort |
|----------|------|------|--------|
| P2 | **Cross-service contract synchronization** — validate contracts stay consistent across all 8 services | orchestration | XL |
| P3 | **Contract diff tool** — `diff-contracts.sh` to compare two contract states | scripts/ | L |

## Validation Coverage Map

| Contract Section | Schema | Validator Check | Tests |
|-----------------|--------|----------------|-------|
| contract_version | ✅ | — | — |
| state_machine_version | ✅ | — | — |
| state | ✅ | Step 1.5 (hard-block) + Step 3 | Tests 3-4 |
| session | ✅ | Step 4 (nested fields) | Test 5 |
| requirements | ✅ | Step 4 (nested fields) | — |
| decisions | ✅ | Step 4 (nested fields) | — |
| governance | ✅ | Step 4 (nested fields) + Step 6 (field access) | — |
| score | ✅ | Step 5 (content quality) | Tests 10-12 |
| retry | ✅ | Step 5 (content quality, item 10) | — |
| outputs | ✅ | Step 5 (content quality) | Tests 10-11 |
| **scope** | ✅ | **Step 6b** (NEW) | **Tests 13-16 (NEW)** |
| ponytail | ✅ | Step 4 (nested fields) | — |
| metrics | ✅ | Step 4 (nested fields) | — |
| token_budget | ✅ | Step 4 (nested fields) | — |
| validation | ✅ | Step 4 (nested fields) + Step 5 | — |
| lessons_learned | ✅ | Step 4 (nested fields) | — |
| audit_log | ✅ | Step 5 (content quality, item 6/6a) | Test 12 |
| Transitions | ✅ | Step 7 (+ score gate via Step 3b) | Tests 6b, 7-9 |
