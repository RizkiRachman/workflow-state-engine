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

State machine: `INIT → PLAN → PLAN_SCORED → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE`

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
- **Every decision is tracked** in the shared JSON envelope (`template/contract.json`)
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

1. Clone the repo

   ```sh
   git clone https://github.com/RizkiRachman/workflow-state-engine.git
   cd workflow-state-engine
   ```

2. Bootstrap symlinks

   ```sh
   bash setup.sh
   ```

3. Verify the orchestration envelope loads

   ```sh
   lean-ctx ctx_knowledge recall --key "orchestration-contract" --mode exact
   ```

   If the envelope exists, you're resuming a session. If not, a fresh one will be created on first delegation.

4. (Optional) Configure your branch

   ```sh
   git checkout -b feature/your-task-description
   ```

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
│   ├── system-analyst.md
│   ├── developer.md
│   ├── quality-analyst.md
│   └── ...
├── skills/            ← 35 skill directories
│   ├── java-developer/
│   ├── spec-driven-development/
│   ├── gitnexus/
│   └── ...
├── template/          ← Shared JSON envelope, state.md, superpowers contract
├── rules/             ← State machine transitions, scoring thresholds
├── usage/             ← 15 tool usage guides
├── doc/               ← Workflow docs, project docs, gap analyses
└── config/            ← Plugin configurations
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
INIT → PLAN → PLAN_SCORED → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE
                              ↘                ↘                ↘
                          BLOCKED (score < 50 or retry ≥ 3)
                                ↘
                          User intervention → retry with guidance
```

| Transition | Gate | Condition |
|-----------|------|-----------|
| INIT → PLAN | Session created | Always |
| PLAN → PLAN_SCORED | Plan produced | Always |
| PLAN_SCORED → EXECUTE | Spec gate | Score ≥ 70 |
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
- [ ] Skill registry publishing (skills.sh)
- [ ] Intensity modes for ponytail (off/lite/full/ultra)
- [ ] Debt ledger harvesting (`/ponytail-debt` command)
- [ ] Multi-model council consensus for high-stakes decisions
- [ ] Parallel shard execution with conflict reconciliation

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
- [Ponytail](https://github.com/DietrichGebert/ponytail) — frugality ladder inspiration
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