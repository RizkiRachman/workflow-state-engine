<!-- omit from toc -->
# OpenCode — Usage Guide

> **Official docs**: [opencode.ai/docs](https://opencode.ai/docs/)

OpenCode is the AI coding agent platform this project runs on. This guide covers how it's configured, how agents work, and what to do when things go wrong.

[![OpenCode Plugin][opencode-shield]][opencode-url] [![Docs][docs-shield]][docs-url]

<a id="readme-top"></a>

---

## Table of Contents
1. [How This Project Uses OpenCode](#1-how-this-project-uses-opencode)
2. [Configuration Reference](#2-configuration-reference)
3. [Agents](#3-agents)
4. [Permissions](#4-permissions)
5. [Tools](#5-tools)
6. [Rules (AGENTS.md)](#6-rules-agentsmd)
7. [Skills](#7-skills)
8. [CLI Reference](#8-cli-reference)
9. [Project-Specific Configuration](#9-project-specific-configuration)
10. [Troubleshooting](#10-troubleshooting)
11. [References](#11-references)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 1. How This Project Uses OpenCode

OpenCode is configured at **`opencode.json`** in the project root. Key configuration:

| Setting | Value | Notes |
|---------|-------|-------|
| Default agent | `tech-lead` | Primary orchestrator |
| Model | `sumopod/deepseek-v4-flash` | Via Sumopod AI provider |
| Instructions | `toolkit/agent.md` + morph-tools.md | Loaded every session |
| MCP servers | `lean-ctx`, `gitnexus`, `graphify`, `firecrawl`, `postgres`, `context7` | 6 MCPs |
| Plugins | `morph`, `dcp`, `vibeguard`, `notify`, `websearch-cited`, `worktree`, `model-fallback` | 7 plugins |
| Agents | 11 custom agents (tech-lead + 10 subagents) | Defined in `opencode.json` |
| Format | JSON (not JSONC) | `opencode.json`, no comments |

### Architecture

```
opencode.json          ← Project config (agents, MCPs, plugins, permissions)
toolkit/agent.md       ← instructions[0] — loaded every session
.opencode/ → toolkit/  ← Symlinks: agents/, skills/, rules/, usage/, template/
AGENTS.md → toolkit/agent.md  ← Symlink (same file)
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 2. Configuration Reference

### 2.1 Config File Locations

Config files are **merged**, not replaced. Later sources override earlier ones for conflicting keys only.

| Precedence | Location | Purpose |
|-----------|----------|---------|
| 1 (first) | Remote `.well-known/opencode` | Organization defaults |
| 2 | `~/.config/opencode/opencode.json` | User global preferences |
| 3 | `OPENCODE_CONFIG` env var | Custom override path |
| **4** | **`opencode.json`** (project root) | **Project-specific** |
| 5 | `.opencode/` directories | Agents, commands, plugins |
| 6 | `OPENCODE_CONFIG_CONTENT` env var | Runtime overrides |
| 7 (last) | Managed config (`/Library/...`) | Admin-enforced, highest priority |

This project uses **level 4** — `opencode.json` in the project root. Global config at `~/.config/opencode/` is optional for user preferences.

### 2.2 Schema Reference

The config schema is at [`opencode.ai/config.json`](https://opencode.ai/config.json).

Key sections in our `opencode.json`:

| Section | What It Controls |
|---------|-----------------|
| `agent` | 11 agent definitions (permissions, model, temperature, steps) |
| `mcp` | 6 MCP servers (lean-ctx, gitnexus, graphify, firecrawl, postgres, context7) |
| `plugin` | 7 installed plugins |
| `permission` | Global tool permissions (all `deny` except `lean-ctx_*` and `skill`) |
| `provider` | Sumopod AI provider config with model options |
| `compaction` | Auto context compaction with token budget |
| `instructions` | Instruction files loaded every session |

### 2.3 TUI Config

TUI-specific settings go in `tui.json` (project or `~/.config/opencode/tui.json`). Not currently configured in this project. Schema: [`opencode.ai/tui.json`](https://opencode.ai/tui.json).

Options include:
- `theme` — UI theme
- `keybinds` — keyboard shortcuts
- `scroll_speed` — scroll rate
- `mouse` — mouse support
- `attention` — desktop notifications and sounds

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 3. Agents

### 3.1 Agent Types

OpenCode has two types:

- **Primary agents** — switched via Tab key. Ours: `tech-lead` (the default).
- **Subagents** — invoked by primary agents or via `@mention`. Ours: 10 subagents.

### 3.2 Built-in Agents (not in use)

| Agent | Mode | Purpose |
|-------|------|---------|
| `build` | primary | All tools enabled (default in vanilla OpenCode) |
| `plan` | primary | Read-only for planning |
| `general` | subagent | Multi-step tasks |
| `explore` | subagent | Read-only code exploration |
| `scout` | subagent | External dependency research |

This project replaces `build` as the default with `tech-lead` and defines 10 custom subagents.

### 3.3 Our Custom Agents

Defined in `opencode.json` agent definitions + `.opencode/agents/*.md`:

| Agent | Mode | Steps | Temperature | Permission Pattern |
|-------|------|-------|-------------|-------------------|
| **tech-lead** | primary | 50 | 0 | skill=allow, everything else denied |
| **system-analyst** | subagent | 80 | 0 | skill=allow, read-only |
| **developer** | subagent | 100 | 0 | skill=allow |
| **developer-fixer** | subagent | 40 | 0 | MCP-restricted |
| **developer-explorer** | subagent | 30 | 0 | grep+gitnexus restricted |
| **developer-librarian** | subagent | 30 | 0 | gitnexus restricted |
| **developer-observer** | subagent | 30 | 0 | gitnexus+graphify restricted |
| **developer-council** | subagent | 30 | 0.2 | MCP-restricted |
| **quality-analyst** | subagent | 80 | 0 | skill=allow |
| **quality-analyst-learner** | subagent | 40 | 0 | MCP-restricted |
| **software-architect** | subagent | 60 | 0 | skill=allow |

Key pattern: All agents are read-only at the native tool level (`read`, `edit`, `bash`, `grep` are `deny` globally). They work through MCP tools like `lean-ctx_*` which are globally `allow`.

### 3.4 Agent Configuration Options

| Option | Example | Purpose |
|--------|---------|---------|
| `mode` | `"primary"` / `"subagent"` | How the agent is invoked |
| `model` | `"sumopod/deepseek-v4-flash"` | Override model for this agent |
| `temperature` | `0` — `1.0` | Response determinism |
| `steps` | `50` | Max agentic iterations before forced text response |
| `permission` | `{ "edit": "deny" }` | Tool access control |
| `description` | `"Reviews code..."` | Shown in tool list |
| `color` | `"#ff6b6b"` | TUI accent color |
| `hidden` | `true` | Hide from @mention menu |
| `fallback_models` | `["sumopod/..."]` | Models to try on failure |

### 3.5 Creating a New Agent

```bash
opencode agent create
```

Interactive prompts: path, description, mode, permissions, model. Or define in `opencode.json`:

```json
{
  "agent": {
    "my-agent": {
      "mode": "subagent",
      "description": "Does something specific",
      "permission": {
        "skill": "allow"
      }
    }
  }
}
```

Or as a markdown file at `.opencode/agents/my-agent.md`:

```markdown
---
description: Does something specific
mode: subagent
permission:
  skill: allow
---
Instructions for the agent...
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 4. Permissions

### 4.1 Actions

| Action | Meaning |
|--------|---------|
| `"allow"` | Runs automatically |
| `"ask"` | Prompts user for approval |
| `"deny"` | Blocked |

### 4.2 Global Permission Model (this project)

Our `opencode.json` uses a **deny-by-default** pattern:

```json
{
  "permission": {
    "*": "allow",
    "bash": "deny",
    "read": "deny",
    "edit": "deny",
    "grep": "deny",
    "lean-ctx_*": "allow"
  }
}
```

This means:
- All native tools (`read`, `edit`, `bash`, `grep`) are `deny` globally
- MCP tools (`lean-ctx_*`) are `allow`
- Each agent can override via its `permission` block
- Agents work through MCP tools (lean-ctx, gitnexus, etc.) and the `skill` tool

### 4.3 Permission Keys

| Key | Gates | Granular? |
|-----|-------|-----------|
| `read` | `read` tool | Path-based |
| `edit` | `edit`, `write`, `apply_patch` | Path-based |
| `bash` | `bash` command | Command pattern |
| `grep` | `grep` tool | Pattern-based |
| `glob` | `glob` tool | Pattern-based |
| `task` | subagent invocation | Subagent name pattern |
| `skill` | skill loading | Skill name pattern |
| `skill` | skill loading | Skill name pattern |
| `webfetch` | URL fetching | URL pattern |
| `external_directory` | Paths outside worktree | Path pattern |
| `doom_loop` | Repeated tool calls (3x same input) | Auto-triggered |

### 4.4 Granular (Object) Syntax

```json
{
  "permission": {
    "edit": {
      "src/main/**": "allow",
      "*.json": "deny"
    },
    "bash": {
      "*": "ask",
      "git *": "allow",
      "rm *": "deny",
      "grep *": "allow"
    }
  }
}
```

Rules are evaluated by matching — the **last matching rule wins**. Common pattern: put catch-all `"*"` first, specific rules after.

### 4.5 Permission Precedence

Agent permissions override global permissions. If global says `edit: deny` but an agent says `edit: ask`, the agent wins.

### 4.6 Home Directory Expansion

Use `~` or `$HOME` in permission patterns for external directories:

```json
{
  "permission": {
    "external_directory": {
      "~/projects/personal/**": "allow",
      "/tmp/**": "deny"
    },
    "edit": {
      "~/projects/personal/**": "deny"
    }
  }
}
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 5. Tools

OpenCode's native tools (all `deny` in this project — we use MCP alternatives):

| Tool | What It Does | Our Replacement |
|------|-------------|-----------------|
| `read` | Read file contents | `lean-ctx ctx_read` |
| `edit` | Exact string replace in files | `lean-ctx ctx_edit` / `morph_edit` |
| `write` | Create/overwrite files | `lean-ctx ctx_edit --create` / `write` |
| `bash` | Shell commands | `lean-ctx ctx_shell` |
| `grep` | Regex content search | `lean-ctx ctx_search` |
| `glob` | File pattern matching | — |
| `webfetch` | Fetch URLs | `firecrawl_firecrawl_scrape` |
| `websearch` | Web search | `firecrawl_firecrawl_search` / `websearch_cited` |
| `skill` | Load skill files | Used directly |
| `todowrite` | Manage task lists | Used directly |
| `question` | Ask the user | Used directly |
| `lsp` | LSP code intelligence | — |
| `apply_patch` | Apply unified diffs | — |

### 5.1 Custom Tools

Define in `opencode.json`:

```json
{
  "tool": {
    "my-tool": {
      "command": ["node", "scripts/my-tool.js", "$ARGS"]
    }
  }
}
```

### 5.2 MCP Servers (Our Setup)

| Server | Tool Pattern | Purpose |
|--------|-------------|---------|
| **lean-ctx** | `lean-ctx_*` | File ops, shell, search, knowledge, sessions |
| **gitnexus** | `gitnexus_*` | Impact analysis, code query, safe rename |
| **graphify** | `graphify_*` | Knowledge graph traversal |
| **firecrawl** | `firecrawl_*` | Web scraping, search, monitoring |
| **postgres** | `postgres_*` | Database queries, schema inspection |
| **context7** | `context7_*` | Library docs lookup |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 6. Rules (AGENTS.md)

The rules system in OpenCode uses `AGENTS.md` files. In this project:

- **`AGENTS.md`** → symlink to `toolkit/agent.md` — the canonical instructions file
- **Loaded via `instructions`** in `opencode.json`:
  - `toolkit/agent.md` (instructions[0])
  - `node_modules/@morphllm/opencode-morph-plugin/instructions/morph-tools.md`

### 6.1 File Precedence

1. **Project**: `AGENTS.md` (or `CLAUDE.md` fallback) in project root
2. **Global**: `~/.config/opencode/AGENTS.md` (or `~/.claude/CLAUDE.md` fallback)
3. **Custom**: `instructions` array in `opencode.json` supports glob patterns and remote URLs

### 6.2 Referencing External Files

In `opencode.json`:

```json
{
  "instructions": ["docs/standards.md", ".cursor/rules/*.md"]
}
```

Remote URLs are also supported with 5-second timeout:

```json
{
  "instructions": ["https://raw.githubusercontent.com/org/shared-rules/main/style.md"]
}
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 7. Skills

Skills are reusable instruction files loaded on-demand via the `skill` tool.

### 7.1 Location

| Scope | Path |
|-------|------|
| Project | `.opencode/skills/<name>/SKILL.md` |
| Global | `~/.config/opencode/skills/<name>/SKILL.md` |
| Claude compat | `.claude/skills/<name>/SKILL.md` or `~/.claude/skills/<name>/SKILL.md` |

This project has **29 skills** at `toolkit/skills/` (symlinked from `.opencode/skills/`).

### 7.2 SKILL.md Format

```markdown
---
name: my-skill
description: What this skill does (1-1024 chars)
license: MIT
compatibility: opencode
metadata:
  audience: developers
---
Detailed instructions for the agent...
```

Rules:
- `name` — lowercase alphanumeric with single hyphens, 1-64 chars, must match directory name
- `description` — 1-1024 characters, must be specific enough for agent to choose correctly
- Unknown frontmatter fields are ignored

### 7.3 Skill Permissions

```json
{
  "permission": {
    "skill": {
      "*": "allow",
      "internal-*": "deny"
    }
  }
}
```

Per-agent overrides:

```json
{
  "agent": {
    "plan": {
      "permission": {
        "skill": {
          "internal-*": "allow"
        }
      }
    }
  }
}
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 8. CLI Reference

### 8.1 Common Commands

| Command | Usage |
|---------|-------|
| `opencode` | Start TUI in current directory |
| `opencode -c` | Continue last session |
| `opencode -s <id>` | Resume specific session |
| `opencode run "prompt"` | Non-interactive mode |
| `opencode serve` | Headless server for API access |
| `opencode web` | Server with web UI |
| `opencode agent list` | List all agents |
| `opencode agent create` | Create new agent (interactive) |
| `opencode mcp list` | List configured MCP servers |
| `opencode mcp add` | Add new MCP server |
| `opencode models` | List available models |
| `opencode stats` | Show token usage and cost |
| `opencode session list` | List all sessions |
| `opencode export <id>` | Export session as JSON |
| `opencode import <file>` | Import session from JSON |
| `opencode upgrade` | Update to latest version |
| `opencode debug config` | Show resolved configuration |

### 8.2 Key Flags for `opencode run`

| Flag | Description |
|------|-------------|
| `-m <model>` | Override model (`provider/model`) |
| `--agent <name>` | Use specific agent |
| `--continue` / `-c` | Continue last session |
| `--share` | Share the session |
| `-f <file>` | Attach file to message |
| `--thinking` | Show thinking blocks |
| `--dangerously-skip-permissions` | Auto-approve all |

### 8.3 Environment Variables

| Variable | Purpose |
|----------|---------|
| `OPENCODE_CONFIG` | Custom config file path |
| `OPENCODE_CONFIG_DIR` | Custom config directory |
| `OPENCODE_PERMISSION` | Inline JSON permissions override |
| `OPENCODE_SERVER_PASSWORD` | Basic auth for `serve`/`web` |
| `OPENCODE_DISABLE_CLAUDE_CODE` | Disable Claude Code compatibility |
| `OPENCODE_ENABLE_EXA` | Enable web search tool |
| `OPENCODE_DISABLE_AUTOCOMPACT` | Disable auto context compaction |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 9. Project-Specific Configuration

### 9.1 MCP Servers

This project has 6 MCP servers configured in `opencode.json`:

| Server | Type | Command | Notes |
|--------|------|---------|-------|
| **lean-ctx** | local | `/opt/homebrew/bin/lean-ctx` | `LEAN_CTX_DATA_DIR` set |
| **gitnexus** | local | `npx gitnexus mcp` | — |
| **graphify** | local | `python3 -m graphify.serve` | Loads `graphify-out/graph.json` |
| **firecrawl** | local | `npx firecrawl-mcp` | Requires `FIRECRAWL_API_KEY` env |
| **postgres** | local | `npx @yawlabs/postgres-mcp` | Uses `${PG_MCP_URL}` env |
| **context7** | local | `npx @upstash/context7-mcp` | — |

### 9.2 Plugins

7 plugins installed:

| Plugin | npm Package | Purpose |
|--------|------------|---------|
| Morph | `@morphllm/opencode-morph-plugin` | Large/scattered file edits + warpgrep |
| DCP | `@tarquinen/opencode-dcp` | Context pruning and token budget |
| VibeGuard | `opencode-vibeguard` | Secret/PII redaction |
| Notify | `opencode-notify` | In-app notifications |
| WebSearch Cited | `opencode-websearch-cited` | Grounded web search |
| Worktree | `opencode-worktree` | Git worktree management |
| Model Fallback | `@razroo/opencode-model-fallback` | Auto failover on API error |

### 9.3 Compaction

```json
{
  "compaction": {
    "auto": true,
    "prune": true,
    "reserved": 8000
  }
}
```

- `auto`: Compact sessions automatically when context fills
- `prune`: Remove old tool outputs to save tokens
- `reserved`: 8000 token buffer for compaction safety

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 10. Troubleshooting

### 10.1 Config Validation

```bash
# Show resolved config (merged from all sources)
opencode debug config
```

This shows the effective config after merging global + project + env overrides.

### 10.2 Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Agent can't read files | `read` tool is `deny` | Use `lean-ctx ctx_read` instead |
| "bash is not available" | `bash` is `deny` globally | Use `lean-ctx ctx_shell` |
| `skill` tool doesn't find a skill | Skill not in search paths | Check `.opencode/skills/<name>/SKILL.md` exists and has valid frontmatter |
| MCP server not responding | Server crashed or not installed | Run `opencode mcp list` to check status |
| Model errors | API key expired or rate-limited | Run `opencode auth login` to refresh |
| Session lost after restart | Not saved | Use `ctx_session save` before closing |

### 10.3 Skill Not Loading

1. Check SKILL.md exists at correct path
2. Verify frontmatter has `name` and `description`
3. Ensure name matches directory name (regex: `^[a-z0-9]+(-[a-z0-9]+)*$`)
4. Check permissions — skills with `deny` are hidden
5. Skill names must be unique across all locations

### 10.4 Provider Issues

```bash
# List available models
opencode models --refresh

# Check authentication status
opencode auth list

# Re-authenticate
opencode auth login
```

### 10.5 MCP Connection Issues

```bash
# List all configured MCPs and their status
opencode mcp list

# Add a new MCP server
opencode mcp add
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 11. References

| Resource | URL |
|----------|-----|
| OpenCode Docs | [opencode.ai/docs](https://opencode.ai/docs/) |
| Config Schema | [opencode.ai/config.json](https://opencode.ai/config.json) |
| TUI Schema | [opencode.ai/tui.json](https://opencode.ai/tui.json) |
| GitHub | [github.com/anomalyco/opencode](https://github.com/anomalyco/opencode) |
| Discord | [opencode.ai/discord](https://opencode.ai/discord) |
| OpenCode Zen | [docs/zen/](https://opencode.ai/docs/zen/) |
| Skills Guide | [docs/skills/](https://opencode.ai/docs/skills/) |
| Permissions Guide | [docs/permissions/](https://opencode.ai/docs/permissions/) |
| MCP Servers | [docs/mcp-servers/](https://opencode.ai/docs/mcp-servers/) |
| Plugins Guide | [docs/plugins/](https://opencode.ai/docs/plugins/) |

[opencode-shield]: https://img.shields.io/badge/OpenCode-配置-blue?style=for-the-badge
[opencode-url]: #
[docs-shield]: https://img.shields.io/badge/DOCS-文档-blue?style=for-the-badge
[docs-url]: #
