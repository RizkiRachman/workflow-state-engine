## Summary

Closes **15 reinforcement gaps** across the workflow-state-engine framework (P0-P3). This release hardens the state machine correctness, adds session integrity verification, implements rollback protocols, enhances the ponytail gate with dependency scanning, and introduces multi-service contract validation.

## Changes

### Critical (P0)
- **State machine sync** — Added PONYTAIL_CHECK to `rules.json` states array; removed duplicate transition entries
- **Blast radius gate** — `critical_thresholds.blast_radius_unacknowledged` now mechanically BLOCKED on HIGH/CRITICAL (not just warning)
- **Session integrity** — SHA-256 hashing for all contract snapshots; hash tracked in `state.md` and `index.md`

### High (P1)
- **Semantic merge** — `detect-parallel-conflicts.sh --json-merge` for jq-based AST conflict detection
- **Rollback protocol** — `scripts/rollback-state.sh` with SHA-256 integrity verification and state recovery
- **Dependency scan** — `pre-commit-ponytail.sh` now scans 8 package manager formats for new dependencies
- **state-guard.sh** — `--contract-dir` and `--blast-radius` flags for agent delegation integration

### Medium (P2)
- **Post-merge hook** — `.githooks/post-merge` syncs session index and re-indexes gitnexus
- **Scoring formula** — Formalized `(tier1 + tier2) / 2` formula in `rules.json`
- **Tarball archival** — `snapshot-contract.sh --archive` creates compressed session archives

### Low (P3)
- **Branch naming** — Pre-commit validates `feature/YYYYMMDD-` / `bugfix/YYYYMMDD-` pattern
- **Meta-contract validation** — `scripts/validate-meta-contract.sh` for multi-service deployments
- **Service-type schema** — `contract.schema.json` now requires `service_type` (Core/UI/Support/Infrastructure) with threshold rules

## Files Changed

**Modified (9):**
- `rules/rules.json` — state machine sync, scoring formula
- `contract/contract.schema.json` — service_type with thresholds
- `scripts/pre-commit-ponytail.sh` — dependency scan function
- `scripts/state-guard.sh` — contract-dir, blast-radius flags
- `scripts/snapshot-contract.sh` — SHA-256 hashing, --archive flag
- `scripts/detect-parallel-conflicts.sh` — --json-merge mode
- `.githooks/pre-commit` — branch naming validation
- `opencode.json.template` — minor updates
- `tasks/README.md` — sprint board

**Created (5):**
- `scripts/rollback-state.sh` — rollback protocol
- `scripts/validate-meta-contract.sh` — multi-service contract validation
- `.githooks/post-merge` — post-merge session sync
- `scripts/apply-profile.sh` — profile helper
- `tasks/backlogs/mcp-integration-planning-20260620.md` — backlog

## Verification

- [x] All scripts pass `bash -n` syntax check
- [x] All JSON files validate via `json.load`
- [x] New scripts made executable (`chmod +x`)
- [x] `gitnexus_detect_changes` — LOW risk, 0 affected processes
- [x] Session snapshot taken and knowledge persisted

## Breaking Changes

None. All changes are backward-compatible additions:
- `contract.schema.json` requires `service_type` for **new** contracts only
- `rules.json` scoring formula is additive documentation
- All new flags are opt-in (`--json-merge`, `--archive`, `--contract-dir`, `--blast-radius`)

## How to Test

```bash
# Validate all scripts
bash -n scripts/rollback-state.sh scripts/validate-meta-contract.sh

# Verify JSON schema
python3 -c "import json; json.load(open('contract/contract.schema.json'))"
python3 -c "import json; json.load(open('rules/rules.json'))"

# Test rollback (dry-run)
bash scripts/rollback-state.sh --list

# Test meta-contract validation
bash scripts/validate-meta-contract.sh --services Core,UI
```

## Migration Guide

Existing `contract.json` files without `service_type` will continue to work. New contracts should include:

```json
"service_type": "Core",
"service_type_rules": {
  "ponytail_intensity": "high",
  "score_threshold": 75,
  "max_debt_items": 3,
  "sdd_gate_required": true
}
```
