# Release Plan — Workflow State Engine v0.9.0

> **Branch:** `feature/20260624-workflow-reinforcement-gaps`
> **Target:** `main`
> **Score:** 97/100
> **Date:** 2026-06-24

## Summary

This release closes **15 reinforcement gaps** across the workflow-state-engine framework, spanning P0 (critical) through P3 (low) priority items. The improvements target state machine correctness, session integrity, conflict resolution, rollback safety, ponytail enforcement, and multi-service contract validation.

## Changes

### Files Modified (9)

| File | Change |
|------|--------|
| `rules/rules.json` | Added PONYTAIL_CHECK state, removed duplicate transitions, added blast radius BLOCKED gate, added scoring formula |
| `contract/contract.schema.json` | Added service_type field (Core/UI/Support/Infra) with threshold rules |
| `scripts/pre-commit-ponytail.sh` | Added `check_new_dependencies()` for package.json/pom.xml/build.gradle dependency scanning |
| `scripts/state-guard.sh` | Added `--contract-dir` and `--blast-radius` flags for agent integration |
| `scripts/snapshot-contract.sh` | Added SHA-256 hashing, hash columns in state.md/index.md, `--archive` flag |
| `scripts/detect-parallel-conflicts.sh` | Added `--json-merge` mode with jq AST semantic diff |
| `.githooks/pre-commit` | Added branch naming validation (`feature/bugfix` pattern) |
| `opencode.json.template` | Minor updates |
| `tasks/README.md` | Sprint board updates |

### Files Created (5)

| File | Purpose |
|------|---------|
| `scripts/rollback-state.sh` | Rollback protocol — restore contract from git with SHA-256 verification |
| `scripts/validate-meta-contract.sh` | Multi-service contract validation with service-type threshold enforcement |
| `.githooks/post-merge` | Post-merge hook for session index sync + gitnexus re-index |
| `scripts/apply-profile.sh` | Profile application helper |
| `tasks/backlogs/mcp-integration-planning-20260620.md` | MCP integration backlog |

## Detailed Component Breakdown

### P0 — Critical (4 items)

| ID | Item | Impact | Verification |
|----|------|--------|-------------|
| P0-1 | rules.json state sync — add PONYTAIL_CHECK to states array | State machine now has 10 states matching docs | `jq '.state_machine.states' rules.json` shows PONYTAIL_CHECK |
| P0-2 | Remove duplicate transition entries | Clean single chain: PLAN_SCORED→PONYTAIL_CHECK→EXECUTE | `jq '.state_machine.transitions' rules.json` no duplicates |
| P0-3 | Mechanical BLOCKED gate for blast radius HIGH | Blast radius HIGH/CRITICAL now forces BLOCKED, not just warning | `jq '.critical_thresholds.blast_radius_unacknowledged' rules.json` |
| P0-4 | SHA-256 hash for session snapshots | Audit integrity — hash sidecar per contract, hash columns in logs | `sha256sum session/*/contract.json.sha256` valid |

### P1 — High (4 items)

| ID | Item | Impact | Verification |
|----|------|--------|-------------|
| P1-5 | jq AST semantic merge | `detect-parallel-conflicts.sh --json-merge` walks top-level keys, catches conflicts | `bash -n scripts/detect-parallel-conflicts.sh` |
| P1-6 | Rollback protocol | `rollback-state.sh --list` + `--restore N` with SHA-256 integrity check | `bash -n scripts/rollback-state.sh` |
| P1-7 | Dependency scan in ponytail | Scans 8 package manager files for new deps; recommends ponytail: comments | `bash -n scripts/pre-commit-ponytail.sh` |
| P1-8 | state-guard.sh integration | `--contract-dir` auto-detects contract; `--blast-radius` checks governance ack | `bash -n scripts/state-guard.sh` |

### P2 — Medium (4 items)

| ID | Item | Impact | Verification |
|----|------|--------|-------------|
| P2-9 | GitNexus Process annotation | `state-machine.ts` already annotated — verified in source | Grep for GitNexus comment |
| P2-10 | Post-merge hook | Syncs session index + re-indexes gitnexus after merge | `bash -n .githooks/post-merge` |
| P2-11 | Scoring formula in rules.json | Formal (tier1 + tier2) / 2 formula documented | `jq '.scoring.formula' rules.json` |
| P2-12 | Tarball archival | `snapshot-contract.sh --archive` creates compressed tar.gz | `bash -n scripts/snapshot-contract.sh` |

### P3 — Low (3 items)

| ID | Item | Impact | Verification |
|----|------|--------|-------------|
| P3-13 | Branch naming validation | Pre-commit warns on non-conformant branch names | `bash -n .githooks/pre-commit` |
| P3-14 | validate-meta-contract.sh | Multi-service contract validation with type thresholds | `bash -n scripts/validate-meta-contract.sh` |
| P3-15 | Service-type schema enforcement | contract.schema.json enforces service_type + threshold rules | `python3 -c "import json; json.load(open('contract/contract.schema.json'))"` |

## Pre-Release Checklist

- [x] All 15 items pass `bash -n` syntax validation
- [x] All JSON files validate via `json.load`
- [x] New scripts are executable (`chmod +x`)
- [x] Session state updated with snapshot
- [x] Knowledge persisted via ctx_knowledge
- [x] `gitnexus_detect_changes` shows LOW risk, 0 affected processes
- [x] Branch created from main with uncommitted changes

## Release Steps

1. **Review** — verify PR against checklist above
2. **Merge** — `git checkout main && git merge feature/20260624-workflow-reinforcement-gaps`
3. **Verify** — run `scripts/validate-toolkit.sh` on main post-merge
4. **Tag** — `git tag v0.9.0 && git push origin v0.9.0`
5. **Communicate** — post release notes to team channel

## Rollback Plan

If issues are found post-merge:

```bash
git revert HEAD --no-edit
git push origin main
```

For session data integrity loss, restore from SHA-256 verified snapshots:

```bash
bash scripts/rollback-state.sh --list
bash scripts/rollback-state.sh --restore <index>
```

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| New scripts not executable on clone | Low | Low | `chmod +x` already applied; installer scripts handle this |
| Service-type schema breaks existing contracts | Low | Medium | Only affects new contracts; existing contracts without service_type continue to work |
| Post-merge hook conflicts with existing hooks | Low | Low | Hook is additive; no existing hook at `.githooks/post-merge` |
| SHA-256 hash mismatch edge case | Low | Medium | `rollback-state.sh` warns on mismatch, doesn't force restore |

## Version Bump

- **Current:** v0.8.0
- **Target:** v0.9.0
- **Bump type:** Minor (backward-compatible feature additions + hardening)
