# MCP Server Integration — Planning & Backlog

**Date:** 2026-06-20
**Source:** `awesome-mcp-servers` analysis
**Goal:** Integrate MCP servers into workflow-state-engine to enhance state machine, scoring pipeline, agent orchestration, and cross-session learning.

---

## Architecture Strategy

```
Orchestrator (tech-lead)
  → mcp-gateway / pluggedin-mcp-proxy  (state-gated tool routing)

State Machine Engine
  → neo4j-mcp  (graph-based transition validation)
  → pg-mnemosyne-mcp  (contract persistence + coordination)

Scoring Pipeline
  Tier 1 (Rules) → CodeMCP + depscope + sieve-mcp
  Tier 2 (LLM)   → selvage + langfuse (tracing)
  Tier 3 (Verdict) → mcpskills-server (auto-gate pattern)

Cross-Session Learning
  → waypath + Agent-Memory-Bridge  (gated memory promotion)

Agent Handoff
  → agent-mq + agent-comm-hub

Execution
  → mcp-shell-server + server-filesystem
```

---

## HIGH Priority Backlog Items

### H1 — Meta-Orchestration: Deploy mcp-gateway as routing hub
- **Server:** [ViperJuice/mcp-gateway](https://github.com/ViperJuice/mcp-gateway)
- **What:** Meta-server exposing state-gated tools per workflow phase. Only PLAN tools during PLAN state, EXECUTE tools during EXECUTE state.
- **Acceptance:**
  - [ ] Install and configure mcp-gateway in `.opencode/` config
  - [ ] Define tool manifests per state machine phase
  - [ ] Wire progressive disclosure to contract state transitions
  - [ ] Test: tool visibility restricted to current state only

### H2 — Scoring Pipeline: Integrate CodeMCP for Tier 1 rule checks
- **Server:** [SimplyLiz/CodeMCP](https://github.com/SimplyLiz/CodeMCP)
- **What:** 80+ tools for impact analysis, call graphs, ownership detection. Maps to `-40 blast radius HIGH` scoring rule.
- **Acceptance:**
  - [ ] Install CodeMCP in tool configuration
  - [ ] Wire blast radius detection into `scripts/score-output.sh`
  - [ ] Verify: rule-based scoring reads CodeMCP impact results
  - [ ] Test: direct caller count thresholds match scoring rules

### H3 — Scoring Pipeline: Integrate selvage for Tier 2 LLM-as-Judge
- **Server:** [selvage-lab/selvage](https://github.com/selvage-lab/selvage)
- **What:** AST-aware LLM code review scoring for REVIEW→REVIEW_SCORED transition.
- **Acceptance:**
  - [ ] Install selvage MCP server
  - [ ] Wire into `scripts/score-output.sh` as Tier 2 evaluation
  - [ ] Configure model selection (via OpenRouter multi-model)
  - [ ] Test: review score correlates with code quality metrics

### H4 — Contract Storage: Deploy pg-mnemosyne-mcp
- **Server:** [Janadasroor/pg-mnemosyne-mcp](https://github.com/Janadasroor/pg-mnemosyne-mcp)
- **What:** PostgreSQL-based persistent memory and multi-agent coordination hub. Stores contract JSON + tracks agent handoffs.
- **Acceptance:**
  - [ ] Configure PostgreSQL connection
  - [ ] Migrate contract storage from filesystem to PostgreSQL
  - [ ] Implement agent handoff tracking via pg-mnemosyne
  - [ ] Test: contract state survives agent restarts

### H5 — State Machine: Deploy neo4j-mcp for graph-based validation
- **Server:** [neo4j-contrib/mcp-neo4j](https://github.com/neo4j-contrib/mcp-neo4j)
- **What:** Store state machine as graph (states=nodes, transitions=edges). Validate legal transitions via Cypher.
- **Acceptance:**
  - [ ] Deploy Neo4j (local or cloud)
  - [ ] Define graph schema for state machine
  - [ ] Replace rules-based transition validation with Cypher queries
  - [ ] Test: invalid transitions rejected, valid ones pass

### H6 — Cross-Session Learning: Integrate waypath
- **Server:** [TheStack-ai/waypath](https://github.com/TheStack-ai/waypath)
- **What:** Local-first memory with promote/review gates — mirrors scoring pipeline gates.
- **Acceptance:**
  - [ ] Install waypath MCP server
  - [ ] Wire lesson extraction at REVIEW_SCORED state to waypath
  - [ ] Configure promote gate thresholds matching scoring pipeline
  - [ ] Test: lessons promoted across sessions

### H7 — Agent Handoff: Deploy agent-mq
- **Server:** [bababoi-bibilabu/agent-mq](https://github.com/bababoi-bibilabu/agent-mq)
- **What:** Message queue for inter-agent handoffs — tech-lead→developer→scorer.
- **Acceptance:**
  - [ ] Install agent-mq server
  - [ ] Define message schemas for state transition events
  - [ ] Wire publisher into tech-lead delegation
  - [ ] Wire consumer into agent startup for state resumption

### H8 — Execution: Integrate mcp-shell-server
- **Server:** [tumf/mcp-shell-server](https://github.com/tumf/mcp-shell-server)
- **What:** Secure shell execution for EXECUTE state — run build, test, validate scripts.
- **Acceptance:**
  - [ ] Install mcp-shell-server
  - [ ] Configure whitelist of allowed commands
  - [ ] Wire into EXECUTE state command runner
  - [ ] Test: command execution with security constraints

### H9 — Observability: Integrate langfuse-mcp
- **Server:** [avivsinai/langfuse-mcp](https://github.com/avivsinai/langfuse-mcp)
- **What:** Trace all LLM-as-Judge scoring calls, debug failures, track prompt versions.
- **Acceptance:**
  - [ ] Configure Langfuse project
  - [ ] Wire tracing into `scripts/score-output.sh`
  - [ ] Tag traces by state machine phase
  - [ ] Test: scoring trace visible in Langfuse dashboard

---

## MEDIUM Priority Backlog Items

### M1 — Scheduled ponytail reminders via Pingfyr
- **Server:** [Pingfyr/mcp](https://github.com/Pingfyr/mcp)
- **What:** Schedule recurring ponytail debt re-checks, webhook notifications on BLOCKED state.
- **Acceptance:**
  - [ ] Configure Pingfyr reminders per workflow interval
  - [ ] Webhook on BLOCKED state → notify orchestrator
  - [ ] Wire deferred scoring re-triggers

### M2 — Agent communication hub via agent-comm-hub
- **Server:** [liuboacean/agent-comm-hub](https://github.com/liuboacean/agent-comm-hub)
- **What:** 53 tools for real-time agent messaging, shared memory, 4-level RBAC.
- **Acceptance:**
  - [ ] Install agent-comm-hub
  - [ ] Configure RBAC matching governance rules
  - [ ] Wire shared memory for cross-agent contract state

### M3 — Dependency security checks via depscope
- **Server:** [cuttalo/depscope](https://github.com/cuttalo/depscope)
- **What:** Package intelligence across 17 ecosystems — health, vulnerabilities, typosquats.
- **Acceptance:**
  - [ ] Install depscope MCP server
  - [ ] Add dependency check rule to scoring pipeline Tier 1
  - [ ] Test: scoring penalizes vulnerable dependencies

### M4 — Secret scanning via sieve-mcp
- **Server:** [gautam-u/sieve-mcp](https://github.com/gautam-u/sieve-mcp)
- **What:** Scans agent chat histories for accidentally leaked secrets.
- **Acceptance:**
  - [ ] Install sieve-mcp
  - [ ] Add secret scan step after each agent session
  - [ ] Wire findings into governance scoring rule

### M5 — Event-sourced log via zaxy
- **Server:** [syndicalt/zaxy](https://github.com/syndicalt/zaxy)
- **What:** Append-only hash-chained log with temporal knowledge graph. Maps to `session/state.md`.
- **Acceptance:**
  - [ ] Install zaxy MCP server
  - [ ] Migrate state.md to append-only log
  - [ ] Configure salience-based forgetting for old states

---

## Execution Plan

### Phase 1 — Foundation (HIGH items, 2-week sprint)
| Week | Items |
|------|-------|
| Week 1 | H4 (contract storage), H5 (state machine graph), H9 (observability) |
| Week 2 | H1 (meta-orchestration), H8 (execution) |

### Phase 2 — Scoring (HIGH items, 1-week sprint)
| Week | Items |
|------|-------|
| Week 3 | H2 (CodeMCP Tier 1), H3 (selvage Tier 2) |

### Phase 3 — Intelligence (HIGH items, 1-week sprint)
| Week | Items |
|------|-------|
| Week 4 | H6 (cross-session learning), H7 (agent handoff) |

### Phase 4 — Polish (MEDIUM items, ongoing)
| Week | Items |
|------|-------|
| Week 5+ | M1–M5 as capacity allows |

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|-----------|
| MCP server API instability | Service disruption | Pin versions, wrap in adapter layer |
| Neo4j operational overhead | Complex infra | Use AuraDB managed, validate with server-sqlite first |
| Langfuse cost at scale | Budget overrun | Set trace sampling rate, cap per-session traces |
| Agent-mq message loss | State inconsistency | Implement retry + dead letter queue |
