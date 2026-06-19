# Model-Agnostic Fallback Guide (G7)

> **Goal**: Ensure the Workflow State Engine toolkit runs reliably across any LLM provider, with graceful fallback when the primary model is unavailable.

[![Model Agnostic][model-agnostic-shield]][model-agnostic-url]

<a id="readme-top"></a>

## Table of Contents

1. [Why Model Agnosticism Matters](#why-model-agnosticism-matters)
2. [How the Contract Envelope Makes It Model-Agnostic](#how-the-contract-envelope-makes-it-model-agnostic)
3. [Fallback Strategies](#fallback-strategies)
4. [Configuration](#configuration)
5. [Setup Examples](#setup-examples)
6. [Troubleshooting](#troubleshooting)
7. [Timeout Handling](#timeout-handling)
8. [See Also](#see-also)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Why Model Agnosticism Matters

| Reason | Impact |
|--------|--------|
| **Avoid vendor lock-in** | No single LLM provider owns your workflow. Switch models without rewriting orchestration logic. |
| **Cost optimization** | Use cheap models for routine tasks (search, summarization) and expensive models only for critical decisions (scoring, code generation). |
| **Reliability** | If Claude is down, GPT takes over. If OpenAI rate-limits you, a local model handles the request. |
| **Compliance** | Run sensitive workloads on self-hosted or on-premise models without changing your workflow. |
| **Future-proofing** | New models emerge quarterly — swap them in without touching agent instructions. |

The toolkit is designed so that **every aspect of orchestration — state transitions, scoring, delegation, knowledge persistence — works identically regardless of which model drives it.**

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## How the Contract Envelope Makes It Model-Agnostic

The shared JSON envelope (`contract/contract.template.json`) is the **single source of truth**. It contains:

- **State**: `contract.state` — current workflow state (INIT → PLAN → ... → COMPLETE)
- **Requirements**: `requirements.goal`, `requirements.constraints` — what to do
- **Outputs**: `outputs.agent_reports[]`, `outputs.code_changes[]` — what was produced
- **Score**: `score.*` — decision quality, independent of which model generated it

**No model-specific data lives in the envelope.** No API keys, no model names, no provider-specific formats. This means:

- Any model can read and write the envelope
- State transitions are purely data-driven, not model-driven
- Score thresholds (`≥70 PASS`, `<50 BLOCKED`) are model-independent
- Switching models mid-session is safe — the next agent picks up from the same envelope state

```json
{
  "contract": {
    "state": "EXECUTE_SCORED",
    "version": "1.0"
  },
  "session": {
    "task_id": "add-pagination-20260619",
    "branch": "feature/20260619-add-pagination"
  },
  "score": {
    "tier1_rules": 85,
    "tier2_llm_judge": 78,
    "tier3_combined": 80
  }
  // No model/provider fields — model-agnostic by design
}
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Fallback Strategies

The toolkit supports four fallback layers. They compose — a request can pass through all four before failing.

### 1. API Error Retry (Exponential Backoff)

The simplest layer: when a model API returns a transient error (429 rate limit, 503 service unavailable, connection timeout), retry with increasing delays.

**Where it applies**: All MCP tool calls that contact an LLM API.

**Strategy**:

```
Attempt 1 → wait 1s → Attempt 2 → wait 2s → Attempt 3 → wait 4s → Attempt 4 → fail
```

**Configuration** (in `opencode.json` or per-agent):

```jsonc
// opencode.json — agent-level retry
{
  "agent": {
    "tech-lead": {
      "model": "claude-sonnet-4-20250514",
      "retry": {
        "maxRetries": 3,
        "baseDelayMs": 1000,
        "maxDelayMs": 10000,
        "backoffMultiplier": 2
      }
    }
  }
}
```

### 2. Model Failover

When retries on the primary model are exhausted, switch to a different model entirely. This is handled by the **Model Fallback plugin** (`@razroo/opencode-model-fallback`).

**How it works**:

```
Primary: Claude Sonnet → fails after maxRetries → Fallback 1: GPT-4o → fails → Fallback 2: Local model → fails → Error propagated
```

The failover is **transparent** to the agent — it receives the response as if the primary model handled it.

**When it triggers**:

| Error | Triggers Fallback? |
|-------|-------------------|
| 4xx/5xx API errors | Yes |
| 429 Rate limit | Yes |
| Request timeout | Yes |
| Connection/DNS errors | Yes |
| Content moderation refusal | No — passed through |
| Tool-call errors | No — agent-level concern |

See [`usage/model-fallback.md`](../usage/model-fallback.md) for full plugin configuration.

### 3. Graceful Degradation

If all models are unavailable, the toolkit degrades gracefully rather than crashing:

| Capability | Full Mode | Degraded Mode |
|------------|-----------|---------------|
| **Scoring pipeline** | 3-tier (rules + LLM-judge + combined) | Rule-based scoring only (Tier 1) |
| **Agent delegation** | Full agent roster | Orchestrator self-executes with reduced steps |
| **Research** | Firecrawl + context7 + websearch | websearch_cited only |
| **Code generation** | Full implementation | Stub generation with ponytail comments |
| **Knowledge persistence** | Cross-session embeddings | Local file-only persistence |

**Contract flag** — set when degraded:

```jsonc
{
  "contract": {
    "state": "EXECUTE",
    "degraded": true,
    "degraded_reason": "No LLM fallback available — rule-based scoring only"
  }
}
```

### 4. Cached Decisions

Re-use previous analysis when confidence is high and context hasn't changed. This avoids burning API calls on repeat decisions.

**What gets cached**:

| Decision Type | Cache Key | TTL |
|---------------|-----------|-----|
| Impact analysis (gitnexus) | Symbol name + branch | Session lifetime |
| Scoring verdict | Contract state + agent report id | 1 hour |
| Library research | Library name + version queried | 24 hours |
| Architecture evaluation | Module name + requirements hash | Session lifetime |

Cached decisions are stored in `lean-ctx ctx_knowledge` with a `confidence` field:

```bash
# Example: caching a scoring decision
lean-ctx ctx_knowledge remember \
  --key "score/plan-scored/20260619" \
  --value '{"state": "EXECUTE", "score": 82, "confidence": 0.9}' \
  --confidence 0.9
```

**Cache hit policy**: Confidence ≥ 0.8 → use cached. Confidence 0.5–0.79 → use cached but flag for review. Confidence < 0.5 → re-evaluate.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Configuration

### Downstream User Config (opencode.json)

Users configure their model of choice in `opencode.json`. The toolkit does not hardcode any model.

```jsonc
// opencode.json — minimal setup
{
  "model": "claude-sonnet-4-20250514",
  "small_model": "gpt-4o-mini",
  "agent": {
    "tech-lead": {
      "model": "claude-sonnet-4-20250514",
      "fallback_models": [
        "gpt-4o",
        "gpt-4o-mini"
      ]
    },
    "developer": {
      "model": "gpt-4o",
      "fallback_models": [
        "claude-sonnet-4-20250514"
      ]
    }
  }
}
```

### Environment Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `ANTHROPIC_API_KEY` | For Claude models | Anthropic API authentication |
| `OPENAI_API_KEY` | For GPT models | OpenAI API authentication |
| `FIRECRAWL_API_KEY` | For Firecrawl MCP | Web search / scraping (optional) |
| `LEAN_CTX_DATA_DIR` | For lean-ctx | Knowledge persistence directory |

### Provider-Specific Config

**Anthropic (Claude)**:

```jsonc
{
  "model": "claude-sonnet-4-20250514",
  "provider": "anthropic",
  "apiKeyEnv": "ANTHROPIC_API_KEY"
}
```

**OpenAI (GPT)**:

```jsonc
{
  "model": "gpt-4o",
  "provider": "openai",
  "apiKeyEnv": "OPENAI_API_KEY"
}
```

**Local / Self-Hosted** (e.g., Ollama, vLLM):

```jsonc
{
  "model": "llama-3-70b",
  "provider": "openai",  // OpenAI-compatible API
  "baseUrl": "http://localhost:11434/v1",
  "apiKeyEnv": "LOCAL_API_KEY"
}
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Setup Examples

### Claude Code (Anthropic primary)

```jsonc
// opencode.json
{
  "model": "claude-sonnet-4-20250514",
  "small_model": "claude-haiku-3-5-20241022",
  "agent": {
    "tech-lead": {
      "model": "claude-sonnet-4-20250514",
      "fallback_models": ["gpt-4o"]
    }
  }
}
```

### Cline (OpenAI primary, local fallback)

```jsonc
// opencode.json
{
  "model": "gpt-4o",
  "small_model": "gpt-4o-mini",
  "agent": {
    "developer": {
      "model": "gpt-4o",
      "fallback_models": [
        "claude-sonnet-4-20250514",
        "ollama/llama3"
      ]
    }
  }
}
```

### Continue.dev (VS Code extension)

Configure via `~/.continue/config.json`:

```jsonc
{
  "models": [
    {
      "title": "Claude Sonnet",
      "provider": "anthropic",
      "model": "claude-sonnet-4-20250514",
      "apiKey": "${ANTHROPIC_API_KEY}"
    },
    {
      "title": "GPT-4o Fallback",
      "provider": "openai",
      "model": "gpt-4o",
      "apiKey": "${OPENAI_API_KEY}"
    }
  ],
  "tabAutocompleteModel": {
    "title": "Starcoder 2",
    "provider": "ollama",
    "model": "starcoder2:7b"
  }
}
```

### Custom MCP Server

Route model requests through a custom MCP server that implements your own failover logic:

```jsonc
// opencode.json — MCP section
{
  "mcp": {
    "llm-router": {
      "command": "node",
      "args": ["path/to/llm-router-mcp.js"],
      "env": {
        "PRIMARY_MODEL": "claude-sonnet-4-20250514",
        "FALLBACK_MODEL": "gpt-4o",
        "PRIMARY_API_KEY": "${ANTHROPIC_API_KEY}",
        "FALLBACK_API_KEY": "${OPENAI_API_KEY}"
      }
    }
  }
}
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| All models fail | All API keys are invalid or expired | Check `apiKeyEnv` values in config. Run `scripts/check-mcp.sh` to verify. |
| Fallback never triggers | `timeoutMs` too high or `maxRetries` too many | Reduce `timeoutMs` (≤30s) or `maxRetries` (≤2). |
| Slow failover | Primary model keeps timing out before falling back | Lower `timeoutMs`. Switch primary to a faster model. |
| Degraded scoring accuracy | Rule-based only (no LLM-as-judge) | Acceptable in an outage — scores are conservative (lower). Re-score when models return. |
| Cached decision stale | Context changed but cache key didn't | Clear cache: `lean-ctx ctx_knowledge remove --key "score/*"` |
| Model returns garbage | Wrong provider URL or API version | Verify `baseUrl` in config. Check provider docs for latest API version. |
| `scripts/timeout-watchdog.sh` kills the process | Operation exceeds configured timeout | Increase timeout in config, or split the operation into smaller steps. |

### Quick Health Check

```bash
# Check MCP connectivity
scripts/check-mcp.sh

# Validate contract (works without any LLM)
scripts/validate-contract.sh --file session/$(git branch --show-current)/contract.json --score

# Test model availability (requires API key)
curl -s https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-sonnet-4-20250514","max_tokens":10,"messages":[{"role":"user","content":"ping"}]}'
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Timeout Handling

Long-running operations (crawling, complex code generation, multi-file analysis) have a dedicated timeout watchdog.

**Script**: [`scripts/timeout-watchdog.sh`](../scripts/timeout-watchdog.sh)

```bash
# Monitor a running process with timeout
scripts/timeout-watchdog.sh --pid $PID --timeout 120 --label "code-generation"

# The watchdog will:
# 1. Monitor the process every 5 seconds
# 2. Automatically terminate if it exceeds the timeout
# 3. Log the timeout to session/state.md
# 4. Return exit code 124 (standard timeout convention)
```

**Integration with fallback**: When a watchdog timeout occurs, the orchestrator:

1. Marks the attempt as failed
2. If retries remain → retries with the next fallback model (see § Fallback Strategy 2)
3. If no retries remain → degrades gracefully (see § Fallback Strategy 3)

**Configuration**:

```bash
# Per-operation timeout in opencode.json
{
  "timeoutMs": 120000,        # 2 minutes for standard operations
  "agent": {
    "developer": {
      "timeoutMs": 300000     # 5 minutes for code generation
    }
  }
}
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## See Also

| Resource | What It Covers |
|----------|---------------|
| [`usage/model-fallback.md`](../usage/model-fallback.md) | Model Fallback plugin configuration (JSONC specifics) |
| [`scripts/timeout-watchdog.sh`](../scripts/timeout-watchdog.sh) | Process timeout monitoring |
| [`scripts/check-mcp.sh`](../scripts/check-mcp.sh) | MCP connectivity and API key verification |
| [`usage/lean-ctx.md`](../usage/lean-ctx.md) | Knowledge caching for decision reuse |
| [`doc/workflow.md`](workflow.md) | Orchestration state machine, scoring pipeline |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

[model-agnostic-shield]: https://img.shields.io/badge/Model%20Agnostic-跨模型-blue?style=for-the-badge
[model-agnostic-url]: #

*Last updated: 2026-06-19. Part of the Workflow State Engine documentation suite.*
