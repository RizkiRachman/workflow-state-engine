# Part F — Consumer Integration Model (Relative Architecture)
> See [doc/workflow/README.md](../workflow/README.md) for index.

This part describes how any project consumes the workflow-state-engine toolkit as a git submodule. The entire integration model is **relative** — paths are defined relative to the consumer project root, making the pattern reusable across any service, any language, any stack.

---

## F1. Directory Topology

A consumer project has three cooperating layers:

```
consumer-project/
├── .workflow-engine/          ← Git submodule (read-only, synced from this repo)
├── opencode.json              ← Project-local config (consumer-owned, committed)
├── .opencode/                 ← Symlink farm → resolves to submodule
│   ├── agents/       → ../.workflow-engine/agents/
│   ├── skills/       → ../.workflow-engine/skills/
│   ├── rules/        → ../.workflow-engine/rules/
│   ├── orchestration → ../.workflow-engine/contract/
│   ├── config/       → ../.workflow-engine/config/
│   ├── usage/        → ../.workflow-engine/usage/
│   └── plugins/      → ../.workflow-engine/.opencode/plugins/
├── session/                    ← Session state (consumer-owned, gitignored, local-only)
│   ├── state.md                ← Append-only state log
│   ├── index.md                ← Branch index
│   ├── main/                   ← Per-branch snapshot archive
│   │   ├── contract.json
│   │   ├── contract.schema.json
│   │   └── state.md
│   └── feature/<name>/
└── .gitignore                  ← Must include session/ and .opencode/
```

### Path Convention

Every path is relative. The `opencode.json` references `.workflow-engine/agent.md` (not an absolute path). The `.opencode/` symlinks use `../.workflow-engine/` (not a hardcoded absolute). This means:

- **All 7 services** use the same symlink pattern — only `opencode.json` model/provider values differ
- **No absolute paths** in any committed file — the integration works from any clone path
- **Session data is local** — `session/` is gitignored, never shared across clones

---

## F2. Submodule Lifecycle

### Add Submodule
```bash
git submodule add https://github.com/RizkiRachman/workflow-state-engine.git .workflow-engine
```

### Update Submodule
```bash
cd .workflow-engine && git checkout main && git pull origin main
```
This pulls the latest toolkit features (agents, skills, rules, scripts, contracts).
After updating, re-run `scripts/validate-toolkit.sh` to confirm integrity.

### Pin to a Specific Commit
```bash
cd .workflow-engine && git checkout <commit-hash>
```
Use for production stability — update deliberately, not automatically.

### Remove Submodule
```bash
git submodule deinit .workflow-engine
git rm .workflow-engine
git reset HEAD .gitmodules
```

---

## F3. Symlink Topology

The `.opencode/` directory is a **symlink farm** — it contains only symlinks that resolve into the submodule. No committed files in `.opencode/` exist within the submodule — the symlinks just reach into it.

```
Consumer Root                → .workflow-engine/
─────────────────────────────────────────────────────
.opencode/agents/            → .workflow-engine/agents/
.opencode/skills/            → .workflow-engine/skills/
.opencode/rules/             → .workflow-engine/rules/
.opencode/orchestration/     → .workflow-engine/contract/
.opencode/config/            → .workflow-engine/config/
.opencode/usage/             → .workflow-engine/usage/
.opencode/plugins/           → .workflow-engine/.opencode/plugins/
```

### Why Symlinks Instead of Copies?
- **Single source of truth** — agent instructions, skills, rules live in one repo
- **Atomic updates** — `git submodule update` refreshes all 7+ consumer projects at once
- **Zero drift** — no manual sync between consumer projects
- **Git-honoring** — symlinked `.opencode/` is gitignored at the consumer level (nothing to commit)

### .gitignore Pattern
```
# workflow-state-engine consumer integration
.opencode/
session/
.workflow-engine/
```

---

## F4. Consumer opencode.json

The consumer project's `opencode.json` is the **only committed config file**. It references the submodule relative paths:

```json
{
  "instructions": [".workflow-engine/agent.md"],
  "agents": {
    "tech-lead":       { "file": ".workflow-engine/agents/tech-lead.md" },
    "system-analyst":  { "file": ".workflow-engine/agents/system-analyst.md" },
    "developer":       { "file": ".workflow-engine/agents/developer.md" },
    "quality-analyst": { "file": ".workflow-engine/agents/quality-analyst.md" }
  },
  "mcp": {
    "lean-ctx": { "command": "/path/to/lean-ctx" }
  }
}
```

### Per-Service Configuration Matrix

| Field | Value (All Services) | Source |
|-------|---------------------|--------|
| `model` | `sumopod/deepseek-v4-flash` | Consumer chooses |
| `mcp.lean-ctx.command` | `/opt/homebrew/bin/lean-ctx` | Environment path |
| `LEAN_CTX_DATA_DIR` | `$HOME/.lean-ctx` | User home |
| `FIRECRAWL_API_KEY` | `YOUR_FIRECRAWL_API_KEY` | Per-environment env var |
| Provider block | Sumopod AI (apiKey from env) | Existing project config |

Only these 3-5 values differ per consumer project. Everything else (agents, skills, rules, contract schema) is inherited from the submodule.

### F4.1: Firecrawl API Key
The workflow engine uses Firecrawl for web search, scraping, and agent-based research.
- Sign up at [firecrawl.dev](https://www.firecrawl.dev) (free tier: 500 credits)
- Get your API key from the dashboard
- Pass it to the install script: `--firecrawl-key <key>`
- Or set `FIRECRAWL_API_KEY` env var in your shell profile

---

## F5. Service-Type Integration Patterns

Consumer projects fall into four types with different thresholds:

| Service Type | Examples | Ponytail Intensity | Score Threshold | SDD Gate |
|---|---|---|---|---|
| **Core** | goods-price-comparison-{service,api} | high | 75 | always |
| **UI** | goods-price-comparison-dashboard | medium | 70 | >3 files |
| **Support** | goods-price-comparison-{automation,agent-helper,claude-service,properties} | low | 65 | never |
| **Infrastructure** | goods-price-comparison-deployer | high | 80 | always |

### Type-Specific Agent Overlays

Each service type has an agent overlay template at `agents/templates/`:

| Template | Loaded By | Customizes |
|---|---|---|
| `core-agent-template.md` | `agents/tech-lead.md` → loads at session start | Domain context, tech stack, event model |
| `ui-agent-template.md` | `agents/tech-lead.md` → loads at session start | API endpoints, visualization, no-persistence |
| `support-agent-template.md` | `agents/tech-lead.md` → loads at session start | Stateless scripts, minimal surface area |
| `infra-agent-template.md` | `agents/tech-lead.md` → loads at session start | CI/CD, Docker, Terraform, high-risk |

Overlays are injected via the orchestrator before delegating — they add domain-specific context to the generic agent instructions. See `doc/service-rules-thresholds.md` for the full threshold matrix.

---

## F6. Multi-Service Orchestration (Meta-Contract)

When orchestrating across multiple consumer services (e.g., changing the `service` API and the `dashboard` UI simultaneously), a **meta-contract** tracks all services:

`contract/meta-contract.template.json`:
```json
{
  "contract_version": "0.8.0",
  "workspace_root": "/Users/rizkirachman/IdeaProjects",
  "services": [
    { "name": "service",  "repo": "goods-price-comparison-service",  "state": "INIT", "validated": false },
    { "name": "api",      "repo": "goods-price-comparison-api",      "state": "INIT", "validated": false },
    { "name": "dashboard", "repo": "goods-price-comparison-dashboard", "state": "INIT", "validated": false }
  ],
  "integration_phases": {
    "A": { "label": "Fix Pilot",       "complete": false },
    "B": { "label": "Rollout 7",      "complete": false }
  }
}
```

Each service has its own per-service contract at `session/{branch}/contract.json`. The meta-contract is the **aggregate view** — it doesn't replace per-service contracts, it tracks their collective state.

### validate-all.sh

The multi-service validation runner at `scripts/validate-all.sh` iterates all registered consumer services:

```bash
bash scripts/validate-all.sh
```

It runs `validate-toolkit.sh` in each service's `.workflow-engine/` and reports pass/fail/skip. Exit code 0 means all services validated.

---

## F7. Git Hooks for Consumer Projects

The toolkit ships pre-commit and post-commit hooks in `.githooks/`. Consumer projects activate them via:

```bash
git config core.hooksPath .workflow-engine/.githooks/
```

| Hook | Trigger | Behavior |
|---|---|---|
| `pre-commit` | Before each commit | Validates contract.json isn't BLOCKED. Blocks commit if state=BLOCKED. |
| `post-commit` | After each commit | Auto re-indexes GitNexus (if available). Updates AGENTS.md. |

See `doc/git-hooks-installation.md` for full installation and troubleshooting.

---

## F8. Validation Flow

Every consumer project runs the same validation:

```bash
cd /path/to/consumer-project
bash .workflow-engine/scripts/validate-toolkit.sh
```

### What Gets Checked

1. **Required directories** (13 paths) — agents/, skills/, contract/, config/, scripts/, session/, doc/, rules/, usage/, .opencode/
2. **Symlink integrity** — all 6-8 `.opencode/` symlinks resolve correctly
3. **Contract schema** — valid JSON Schema compliance
4. **Agent file consistency** — all agent .md files have proper headings
5. **Cross-reference integrity** — internal links in agent.md resolve, `_governance.md` paths resolve

### Expected Results by Service Type

| Service Type | Expected Pass | Expected Skip | Notes |
|---|---|---|---|
| Core (service, api) | 23 | 1 | Full coverage |
| UI (dashboard) | 23 | 1 | Full coverage |
| Support (automation, agent-helper, claude-service, properties) | 23 | 1 | Full coverage |
| Infrastructure (deployer) | 22-23 | 1-2 | May need session/ scaffold if submodule reset |
| Engine itself (workflow-state-engine) | 9-23 | 1-14 | Validator is designed for consumers, not engine root |

---

## F9. Updating the Engine

Two strategies:

1. **Track latest**: `git submodule update --remote .workflow-engine` — gets latest main
   - Run `bash .workflow-engine/scripts/validate-toolkit.sh` after update
2. **Pin to release**: `cd .workflow-engine && git checkout tags/v0.8.0` — stable, intentional
   - Update deliberately per release notes
3. **Verify**: Always re-run validator after update

---

When the workflow-state-engine changes (new agent, new rule, new script), consumer projects pick up changes on next submodule update:

```bash
cd consumer-project/.workflow-engine
git pull origin main
cd ..
bash .workflow-engine/scripts/validate-toolkit.sh
```

Consumer projects should **not** modify files inside `.workflow-engine/` — those changes get overwritten on submodule update. Instead:
- `opencode.json` — configure models, providers, MCP paths
- `session/` — orchestration state (gitignored, local-only)
- Any consumer-specific agent overlays → copy overlay templates to a local `agents/templates/` dir

[workflow-shield]: https://img.shields.io/badge/Workflow-Orchestration-blue?style=for-the-badge
