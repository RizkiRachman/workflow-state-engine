# Git Hooks

The workflow-state-engine ships `pre-commit` and `post-commit` hooks in `.githooks/`. These hooks enforce structural validation, ponytail debt checks, and auto-index GitNexus after commits.

## Installation

```sh
# Root project
bash scripts/install-hooks.sh

# Consumer service (submodule)
bash .workflow-engine/scripts/install-hooks.sh
```

If `install-hooks.sh` is not available, configure core.hooksPath directly:

```sh
git config core.hooksPath .githooks/
```

## What the Hooks Do

### pre-commit (4-stage validation)

The pre-commit hook runs 4 stages. Any failure blocks the commit:

| Stage | Script | What It Checks | Blocking |
|-------|--------|----------------|----------|
| 1. State gate | Inline | Contract `state != BLOCKED` when `session/{branch}/contract.json` exists | Yes |
| 2. Kit integrity | `scripts/validate-toolkit.sh` | `.opencode/` symlinks resolve, agent files complete, contract schema valid | Yes |
| 3. Writing order | `scripts/check-writing-order.sh` | No merge conflict markers in staged files | Yes (conflict markers) |
| 4. Agent sync | `scripts/sync-agent-states.sh` | Agent state maps match `rules.json agent_states` | Warning only |

### post-commit

```sh
bash scripts/gitnexus-analyze.sh   # Updates AGENTS.md with current symbol/rel counts
```

Only runs if GitNexus is available.

## Check Installation

```sh
git config core.hooksPath
# Expected: .githooks/  (or .workflow-engine/.githooks/ for consumers)
```

## Uninstall

```sh
bash scripts/install-hooks.sh --uninstall
# Or: git config --unset core.hooksPath
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| pre-commit fails: "BLOCKED state" | Contract is BLOCKED | Resolve blocker or `git commit --no-verify` |
| pre-commit fails: "X violation(s)" | Broken symlinks or missing files | `bash scripts/validate-toolkit.sh` to see details |
| pre-commit fails: "Merge conflict" | Unresolved `<<<<<<<` markers | Resolve conflicts, re-stage, commit |
| Hooks not executable | Permissions lost on clone | `chmod +x .githooks/pre-commit .githooks/post-commit` |
| Post-commit hangs | GitNexus not installed | Install GitNexus or remove post-commit hook |

## Per-Service Customization

```sh
cp .githooks/pre-commit .git/hooks/pre-commit
# Edit .git/hooks/pre-commit as needed
git config core.hooksPath .git
```
