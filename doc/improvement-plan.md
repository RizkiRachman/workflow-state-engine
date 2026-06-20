# Improvement Plan — Contract Validation & Test Framework

## What Was Done

### Test Framework
- **contract-lifecycle-test.sh**: **20 tests** covering:
  - JSON validity (Test 1-2)
  - State field validation (Tests 3-4)
  - Nested field presence (Test 5)
  - Content quality at various states (Tests 6, 10-12)
  - State transition validation (Tests 6b, 7-9)
  - **Scope consistency** (Tests 13-16) — jq-based (replaced inline Python)
  - **`--score` mode hardening** (Tests 17-18) — numeric-only output, graceful failure on invalid JSON
  - **`--max-depth` flag** (Test 19) — skips deep checks for CI mode
- **parallel-exec-test.sh**: **8 tests (14 assertions)** covering:
  - Basic parallel conflict detection (Tests 1-5)
  - **Diff format input detection** (Test 6)
  - **Mixed file list + diff input** (Test 7)
  - **Leading `./` path normalization** (Test 8)
- **contract-integration-test.sh**: **5 scenarios (16 assertions)** — full 9-state lifecycle, score gates, blocked recovery, schema round-trip

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

### Short Term — Completed ✅

| Priority | Item | Area | Effort | Status |
|----------|------|------|--------|--------|
| P0 | `--score` mode output hardening | validate-contract.sh | S | ✅ Done (Tests 17-18) |
| P1 | Bash `check_scope_consistency` → jq | validate-contract.sh | S | ✅ Done (Tests 13-16) |
| P2 | `--max-depth` flag for CI mode | validate-contract.sh | M | ✅ Done (Test 19) |
| P3 | Schema coverage audit | contract/ | M | ✅ Done (82%→94%) |
| P1 | Parallel exec test scenarios | parallel-exec-test.sh | M | ✅ Done (Tests 6-8) |
| P2 | Integration test (INIT→COMPLETE) | test/ | L | ✅ Done (5 scenarios) |
| P3 | Template↔Schema reconciliation | contract/ | M | ✅ Done (coverage 94%) |

### Medium Term

| Priority | Item | Area | Effort |
|----------|------|------|--------|
| P3 | Validator plugin system | validate-contract.sh | XL |
| P4 | Score analytics | audit-observability skill | M |
| P2 | Cross-service contract synchronization | orchestration | XL |
| P3 | Contract diff tool `diff-contracts.sh` | scripts/ | L |

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
