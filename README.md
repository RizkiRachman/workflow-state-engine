<!-- omit from toc -->
# Workflow State Engine

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=for-the-badge)](http://makeapullrequest.com)

<!-- omit from toc -->
### Contract-driven state machine orchestration engine for AI agent workflows

State machine: `INIT → PLAN → PLAN_SCORED → PONYTAIL_CHECK → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE`

Single source of truth for all AI agents. The canonical agent instruction file is [`agent.md`](agent.md) which serves as `instructions[0]` for every agent.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Table of Contents

1. [About The Project](#about-the-project)
   - [Built With](#built-with)
2. [Getting Started](#getting-started)
   - [Prerequisites](#prerequisites)
   - [Installation](#installation)
3. [Usage](#usage)
4. [Architecture](#architecture)
5. [State Machine](#state-machine)
6. [Scoring Pipeline](#scoring-pipeline)
7. [Roadmap](#roadmap)
8. [Contributing](#contributing)
9. [License](#license)
10. [Contact](#contact)
11. [Acknowledgments](#acknowledgments)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## About The Project

This is a reusable orchestration toolkit for AI coding agents. It codifies agent collaboration into an 8-state state machine, ensuring:

- **Every output is scored** via a three-tier pipeline (rule checks → LLM-as-judge → combined verdict)
- **Every decision is tracked** in the shared JSON envelope (`session/{branch}/contract.json`)
- **Every session learns** from the last — lessons and patterns persist cross-session via `lean-ctx ctx_knowledge`
- **Every delegation is gated** — agents only transition if scoring thresholds are met

The project follows a **spec-driven development (SDD)** workflow: discuss → plan → spec gate → execute → review → verify → ship. Non-trivial decisions are cross-examined via **doubt-driven development (DDD)** before they stand, and every code shortcut is annotated with a **ponytail:** debt comment documenting its ceiling and upgrade path.

### Built With

This project is a documentation and configuration toolkit for AI agents. It leverages:

[![OpenCode](https://img.shields.io/badge/OpenCode-000000?style=for-the-badge&logo=openai&logoColor=white)](https://github.com/opencode-ai/opencode)
[![LeanCtx](https://img.shields.io/badge/lean--ctx-8B5CF6?style=for-the-badge&logo=github&logoColor=white)](https://github.com/opencode-ai/lean-ctx)
[![GitNexus](https://img.shields.io/badge/GitNexus-22C55E?style=for-the-badge&logo=git&logoColor=white)](https://github.com/RizkiRachman/gitnexus)
[![Graphify](https://img.shields.io/badge/Graphify-F59E0B?style=for-the-badge&logo=neo4j&logoColor=white)](https://github.com/safishamsi/graphify)
[![Firecrawl](https://img.shields.io/badge/Firecrawl-EF4444?style=for-the-badge&logo=firefox&logoColor=white)](https://firecrawl.dev)
[![Morph](https://img.shields.io/badge/Morph-3B82F6?style=for-the-badge&logo=vim&logoColor=white)](https://github.com/opencode-ai/morph)
[![Ponytail](https://img.shields.io/badge/Ponytail-F97316?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxNiIgaGVpZ2h0PSIxNiIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJub25lIiBzdHJva2U9IndoaXRlIiBzdHJva2Utd2lkdGg9IjIiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgc3Ryb2tlLWxpbmVqb2luPSJyb3VuZCI+PHBhdGggZD0iTTIgMTJsMTAgMTAiLz48cGF0aCBkPSJNMTIgMjJsMTAtMTAiLz48cGF0aCBkPSJNMTIgMTJsLTEwLTEwIi8+PHBhdGggZD0iTTEyIDEybDEwLTEwIi8+PC9zdmc+&logoColor=white)](https://github.com/DietrichGebert/ponytail)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Getting Started

Copy the orchestration toolkit into your AI agent project and bootstrap it.

### Prerequisites

Your project needs:

- **OpenCode** (or another lean-ctx-compatible AI agent platform)
- **lean-ctx** — compressed file reads, shell, knowledge persistence, session management
- **Git** — for branch management (never work on `main`)
- Optional but recommended: GitNexus (impact analysis), Graphify (knowledge graph), Firecrawl (web search)

Verify your setup:

```sh
lean-ctx --version
git --version
```

### Installation

#### Quick Install

```sh
git clone https://github.com/RizkiRachman/workflow-state-engine.git
cd workflow-state-engine
bash scripts/install.sh
```

The `install.sh` script handles dependency checks, `.opencode/` symlinks, session directory setup, and validation automatically.

#### Manual Setup

1. **Clone the repo**

   ```sh
   git clone https://github.com/RizkiRachman/workflow-state-engine.git
   cd workflow-state-engine
   ```

2. **Bootstrap symlinks** — `setup.sh` creates `.opencode/` symlinks pointing to root-level source directories:

   ```sh
   bash setup.sh
   ```

3. **Configure opencode.json** — copy and configure API keys:

   ```sh
   cp opencode.json.template opencode.json
   # Edit opencode.json — replace YOUR_SUMOPOD_API_KEY,
   # YOUR_FIRECRAWL_API_KEY, and other placeholders
   ```

#### Verify Installation

```sh
# Check toolkit integrity
bash scripts/validate-toolkit.sh

# Verify MCP servers
bash scripts/check-mcp.sh

# Load orchestration envelope
lean-ctx ctx_knowledge recall --key "orchestration-contract" --mode exact
```

#### Branch Setup

```sh
git checkout -b feature/your-task-description
```

⚠️ Never work on `main` — the orchestrator enforces this before any operation.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Usage

### Orchestration Flow

Every task follows this sequence:

| Phase | Agent | Gate |
|-------|-------|------|
| **Discuss** | Tech lead (5-lens check) | Requirements clarified |
| **Plan** | @system-analyst | Impact analysis + plan produced |
| **Spec** (gate) | @system-analyst | GWT-format specs, DDD review |
| **Execute** | @developer | Implementation + tests |
| **Review** | @quality-analyst | Code quality, security, DevOps |
| **Verify** | Quality gates | Validated JSON, conventions check |
| **Ship** | Tech lead | Post-flight protocol |

### Key Commands

```sh
# Load/save session state
lean-ctx ctx_session save
lean-ctx ctx_session load

# Persist decisions
lean-ctx ctx_knowledge remember key <key> value <value>

# Check blast radius before editing
gitnexus_impact({target: "symbolName", direction: "upstream"})

# Run the frugality ladder on any code decision
# (See agent.md §5 for the full 6-rung decision ladder)
```

### Ponytail Gate

Before writing **any** code, run the frugality ladder:

```
1. Does this need to exist?       → skip it (YAGNI)
2. Standard library does it?      → use it
3. Native platform feature?       → use it
4. Already-installed dependency?  → use it
5. Can this be one line?          → one line
6. Only then: minimum code that works
```

Mark intentional shortcuts with `// ponytail: <ceiling>. Upgrade: <path>` comments.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Architecture

```
.
├── agent.md           ← Orchestrator instructions (instructions[0])
├── agents/            ← 11 agent instruction files
├── skills/            ← 29 skill directories + package.json per skill
├── contract/          ← Contract templates & schema (contract.template.json, schema, superpowers)
├── session/           ← Per-branch live state & archives (append-only state log + branch snapshots + contract.json)
├── rules/             ← State machine transitions, scoring thresholds
├── usage/             ← 15 tool usage guides
├── doc/               ← Workflow docs, project docs, gap analyses, cross-agent conventions
├── config/            ← Plugin configurations
├── scripts/           ← 25+ automation & architecture enforcement scripts
│   ├── install.sh                — One-command project setup
│   ├── uninstall.sh              — Clean removal
│   ├── validate-toolkit.sh       — Full toolkit integrity check
│   ├── validate-contract.sh      — Contract JSON validation
│   ├── check-conventions.sh      — Architecture convention checking
│   ├── check-mcp.sh              — MCP server verification
│   ├── health-check.sh           — 6-dimension health verification
│   ├── pre-commit-ponytail.sh    — Ponytail debt gate (pre-commit)
│   ├── scan-ponytail-debt.sh     — Debt marker scanner
│   ├── contract-migrate.sh       — Contract version migration
│   ├── generate-config.sh        — Agent config + skills.json generation
│   ├── build-npm.sh              — npm package build
│   ├── publish-skills.sh         — Skills catalog publication
│   ├── self-healing-retry.sh     — Adaptive retry + backoff
│   ├── timeout-watchdog.sh       — Delegation watchdog with deadlock detection
│   ├── decision-journal.sh       — ADR + confidence score management
│   ├── session-lock.sh           — Concurrent session lock
│   ├── cleanup-branches.sh       — Stale branch cleanup
│   ├── prototype-mode.sh         — Prototype/low-ceremony mode toggle
│   ├── uncertainty-router.sh     — Confidence-based decision routing
│   ├── revert-threshold.sh       — Revert complexity scoring
│   ├── test-gitnexus-integration.sh — GitNexus integration test
│   ├── snapshot-contract.sh      — Envelope snapshot & archival
│   ├── sdd-gate.sh               — SDD spec gate enforcement
│   ├── state-guard.sh            — Agent state guard verification
│   ├── self-repair.sh            — Corrupt contract repair
│   ├── drift-detect.sh           — Knowledge vs file drift detection
│   ├── persist-contract.sh       — Atomic envelope persistence
│   ├── verify-knowledge.sh       — Knowledge persistence verification
│   ├── auto-persist.sh           — Automated contract persistence
│   ├── auto-score.sh             — Automated 3-tier scoring
│   ├── archive-sessions.sh       — Session archival & cleanup
│   ├── autonomous-runner.sh      — Autonomous contract bridge runner
│   └── gitnexus-analyze.sh       — GitNexus re-index
├── .githooks/         ← Git hooks for pre-commit validation and post-commit re-index (pre-commit, post-commit)
├── opencode.json      ← OpenCode configuration
├── opencode.json.template ← Redacted template with annotated MCP tiers
└── setup.sh           ← Bootstrap: pre-flight checks + MCP/plugin verification + symlinks
```

### Agent Delegation Model

```
Orchestrator (tech-lead)
  ├── @system-analyst   → Planning & impact analysis (read-only)
  ├── @developer        → Implementation & tests (read/write)
  ├── @quality-analyst  → Code review (read-only)
  └── @quality-analyst-learner → Post-execution learning
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## State Machine

```
INIT → PLAN → PLAN_SCORED → PONYTAIL_CHECK → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE
                              ↘                      ↘                ↘
                          BLOCKED (score < 50 or retry ≥ 3)
                                ↘
                          User intervention → retry with guidance
```

| Transition | Gate | Condition |
|-----------|------|-----------|
| INIT → PLAN | Session created | Always |
| PLAN → PLAN_SCORED | Plan produced | Always |
| PLAN_SCORED → PONYTAIL_CHECK | Ponytail gate | Score ≥ 70 |
| PONYTAIL_CHECK → EXECUTE | Ponytail scan | Debt items ≤ max_debt_items |
| EXECUTE → EXECUTE_SCORED | Implementation done | Always |
| EXECUTE_SCORED → REVIEW | Code review | Score ≥ 70 |
| REVIEW → REVIEW_SCORED | Review done | Always |
| REVIEW_SCORED → COMPLETE | All gates pass | Score ≥ 70 |
| Any → BLOCKED | Escalation | Score < 50 or retry ≥ 3 |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Scoring Pipeline

Three-tier scoring runs after every delegation:

| Tier | Method | Deduction / Range |
|------|--------|-------------------|
| 1 | Rule-based checks (start 100) | Schema -15, permissions -40, blast radius -40, writing order -15, over-engineering -15 |
| 2 | LLM-as-judge | Requirements 0-40, governance 0-30, completeness 0-20, edge cases 0-10 |
| 3 | **Combined verdict** | **≥ 70 PASS** · 50–69 RETRY (max 3) · < 50 BLOCKED |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Roadmap

- [x] Core state machine (8 states + BLOCKED)
- [x] Three-tier scoring pipeline
- [x] 11 specialized agent instructions
- [x] Ponytail frugality ladder integration
- [x] Vercel-style skill packaging (package.json per skill)
- [x] Cross-reference audit and broken-link detection
- [x] Template configuration (opencode.json.template with MCP/plugin tiers)
- [x] MCP and plugin verification scripts (scripts/check-mcp.sh, check-plugins.sh)
- [x] Architecture convention checking (scripts/check-conventions.sh — agent paths, JSON schema, forbidden patterns, state.md sync)
- [x] Toolkit integrity validation (scripts/validate-toolkit.sh — symlinks, contract integrity, agent consistency, cross-references)
- [x] Ponytail debt scanning (scripts/scan-ponytail-debt.sh — ponytail:, TODO, FIXME, HACK markers)
- [x] Session archival (scripts/archive-sessions.sh — days-based cleanup with dry-run/restore)
- [x] Shared governance document (agents/_governance.md — contract protocol, permissions, frugality, post-flight)
- [x] JSON Schema enforcement (contract/contract.schema.json — Draft 2020-12, $defs, numeric constraints, valid states)
- [x] CI/CD governance pipeline (.github/workflows/governance.yml — conventions, schema, toolkit validation)
- [x] Token budget enforcement (token_budget in contract.json + TOKEN_001-004 in rules.json)
- [x] Skillful configuration catalog (config/opencode-skillful.json — 56 skills across 7 categories)
- [x] Configuration template sync (opencode.json.template — 4 placeholders, synced from opencode.json)
- [x] Session archival protocol (session/ directory — per-branch snapshots, append-only state log, branch index)
- [ ] Skill registry publishing (skills.sh)
- [ ] Intensity modes for ponytail (off/lite/full/ultra)
- [ ] Debt ledger harvesting (`/ponytail-debt` command)
- [ ] Multi-model council consensus for high-stakes decisions
- [x] Parallel shard execution with conflict reconciliation
- [x] Automated contract persistence (scripts/auto-persist.sh)
- [x] Automated 3-tier scoring pipeline (scripts/auto-score.sh)
- [x] Agent state guard verification (scripts/state-guard.sh)
- [x] Self-repair for corrupt contracts (scripts/self-repair.sh)
- [x] Knowledge vs file drift detection (scripts/drift-detect.sh)
- [x] SDD spec gate enforcement (scripts/sdd-gate.sh)
- [x] Knowledge persistence verification (scripts/verify-knowledge.sh)
- [x] Git hook automation (scripts/install-hooks.sh + .githooks/)
- [x] Autonomous runner contract bridge (scripts/autonomous-runner.sh)
- [x] Cross-session learning feedback loop (agents/tech-lead.md, quality-analyst-learner.md)

See the [open issues](https://github.com/RizkiRachman/workflow-state-engine/issues) for a full list of proposed features and known issues.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement".

Don't forget to give the project a star! Thanks again!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## License

Distributed under the MIT License. See `LICENSE` for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Contact

Rizki Rachman - [@RizkiRachman](https://github.com/RizkiRachman)

Project Link: [https://github.com/RizkiRachman/workflow-state-engine](https://github.com/RizkiRachman/workflow-state-engine)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Acknowledgments

This README follows the [Best-README-Template](https://github.com/othneildrew/Best-README-Template) by [@othneildrew](https://github.com/othneildrew).

Additional thanks to:

- [OpenCode](https://github.com/opencode-ai/opencode) — AI agent platform
- [lean-ctx](https://github.com/opencode-ai/lean-ctx) — compressed context management
- [GitNexus](https://github.com/RizkiRachman/gitnexus) — code intelligence graph
- [Graphify](https://github.com/safishamsi/graphify) — knowledge graph builder
- [Firecrawl](https://firecrawl.dev) — web scraping for AI agents
- [Ponytail](https://github.com/DietrichGebert/ponytail) — frugality ladder inspiration and plugin
- [Vercel Skills](https://github.com/vercel-labs/skills) — cross-agent skill packaging
- [Img Shields](https://shields.io) — badge generation
- [Choose an Open Source License](https://choosealicense.com) — license guidance
- [GitHub Emoji Cheat Sheet](https://www.webpagefx.com/tools/emoji-cheat-sheet)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- MARKDOWN LINKS & IMAGES -->
[contributors-shield]: https://img.shields.io/github/contributors/RizkiRachman/workflow-state-engine.svg?style=for-the-badge
[contributors-url]: https://github.com/RizkiRachman/workflow-state-engine/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/RizkiRachman/workflow-state-engine.svg?style=for-the-badge
[forks-url]: https://github.com/RizkiRachman/workflow-state-engine/network/members
[stars-shield]: https://img.shields.io/github/stars/RizkiRachman/workflow-state-engine.svg?style=for-the-badge
[stars-url]: https://github.com/RizkiRachman/workflow-state-engine/stargazers
[issues-shield]: https://img.shields.io/github/issues/RizkiRachman/workflow-state-engine.svg?style=for-the-badge
[issues-url]: https://github.com/RizkiRachman/workflow-state-engine/issues
[license-shield]: https://img.shields.io/github/license/RizkiRachman/workflow-state-engine.svg?style=for-the-badge
[license-url]: https://github.com/RizkiRachman/workflow-state-engine/blob/main/LICENSE