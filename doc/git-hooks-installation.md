# Git Hooks Installation

## Overview
The workflow-state-engine ships pre-commit and post-commit hooks in `.githooks/`. These hooks enforce ponytail debt checks and auto-index GitNexus after commits.

## Installation

### Per Service
```bash
cd /path/to/goods-price-comparison-<service>
bash .workflow-engine/scripts/install-hooks.sh
```

If `install-hooks.sh` does not exist in the submodule, configure directly:
```bash
cd /path/to/goods-price-comparison-<service>
git config core.hooksPath .workflow-engine/.githooks/
```

### What Gets Installed
- **pre-commit**: runs `pre-commit-ponytail.sh` — scans modified files for ponytail debt items exceeding the configured max. Blocks commit if debt exceeds threshold.
- **post-commit**: auto re-indexes GitNexus (if GitNexus is available in the repo). Updates AGENTS.md with current symbol/relationship counts.

## Verification
```bash
ls -la .git/hooks/pre-commit .git/hooks/post-commit
```

Or check the hooks path:
```bash
git config core.hooksPath
# Expected: .workflow-engine/.githooks/
```

## Removal
```bash
git config --unset core.hooksPath
rm -f .git/hooks/pre-commit .git/hooks/post-commit
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `pre-commit` fails during commit | Ponytail debt exceeds threshold | Fix debt items or `git commit --no-verify` |
| Hooks not executable | Permissions lost on clone | `chmod +x .git/hooks/pre-commit .git/hooks/post-commit` |
| `post-commit` hangs | GitNexus not installed | Install GitNexus or disable post-commit hook |

## Per-Service Customization

Hooks are shared via the submodule, so all services use the same hooks. If a service needs custom behavior, copy the hook file to `.git/hooks/` and modify locally:
```bash
cp .workflow-engine/.githooks/pre-commit .git/hooks/pre-commit
# Edit .git/hooks/pre-commit as needed
git config core.hooksPath .git
```
