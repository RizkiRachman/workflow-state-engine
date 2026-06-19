# Making Firecrawl Optional (G10)

> **Firecrawl is an optional dependency.** The toolkit works without it. Every feature that depends on Firecrawl degrades gracefully.

[![Firecrawl Optional][firecrawl-optional-shield]][firecrawl-optional-url]

<a id="readme-top"></a>

## Table of Contents

1. [Statement](#statement)
2. [What Firecrawl Provides](#what-firecrawl-provides)
3. [Fallback Mechanisms](#fallback-mechanisms)
4. [Availability Checking](#availability-checking)
5. [Configuration](#configuration)
6. [Implementation Guidance](#implementation-guidance)
7. [Agent Degradation](#agent-degradation)
8. [See Also](#see-also)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Statement

**Firecrawl is optional. The toolkit works — and works well — without it.**

The core orchestration engine (state machine, contract envelope, scoring pipeline, agent delegation, knowledge persistence) has **zero dependency** on Firecrawl. Only specific research, scraping, and monitoring features require it, and every one of those features has a defined fallback.

The toolkit defines Firecrawl as an optional MCP in `opencode.json.template`:

```jsonc
// opencode.json.template — Firecrawl is one MCP among many
{
  "mcp": {
    "firecrawl": {
      "disabled": true,  // Safe default — enable only when needed
      "command": "npx",
      "args": ["firecrawl-mcp"],
      "env": {
        "FIRECRAWL_API_KEY": "YOUR_FIRECRAWL_API_KEY"
      }
    }
  }
}
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## What Firecrawl Provides

| Feature | Tool | What Degrades Without It |
|---------|------|--------------------------|
| **Web search** | `firecrawl_search` | Falls back to `websearch_cited` or manual URL input |
| **Page scraping** | `firecrawl_scrape` | Falls back to `lean-ctx ctx_read` for local files; manual fetch for URLs |
| **Document parsing** | `firecrawl_parse` | Falls back to `lean-ctx ctx_read` for text files; manual conversion for PDFs/DOCX |
| **Site crawling** | `firecrawl_crawl` | Skipped — use manual URL-by-URL approach |
| **Site mapping** | `firecrawl_map` | Skipped — use manual exploration |
| **Browser interaction** | `firecrawl_interact` | Skipped — not available without Firecrawl |
| **Monitoring** | `firecrawl_monitor_*` | Skipped — monitors unavailable |
| **Deep research** | `firecrawl_agent` | Falls back to multi-query `websearch_cited` approach |
| **Structured extraction** | `firecrawl_extract` | Falls back to manual analysis of retrieved content |

**Graceful degradation rule**: Agents check Firecrawl availability at session start. If unavailable, they skip Firecrawl MCP calls entirely — no errors, no warnings to the user, just reduced research depth.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Fallback Mechanisms

### Web Search Fallback

When `firecrawl_search` is unavailable, agents use the `websearch_cited` tool (part of the `opencode-websearch-cited` plugin):

```bash
# Before (with Firecrawl):
firecrawl_search({query: "Spring Boot 3.4 virtual threads", limit: 5})

# After (without Firecrawl):
websearch_cited({query: "Spring Boot 3.4 virtual threads"})
```

**What changes**:

| Aspect | With Firecrawl | Without Firecrawl |
|--------|---------------|-------------------|
| Result format | Full page markdown | Summaries with inline citations |
| Source depth | Scrape entire pages | Snippet-level only |
| Concurrency | Multi-page scrape | Single query at a time |
| Credit cost | 2 credits per search | Free (websearch) |

If `websearch_cited` is also unavailable, fall back to asking the user for direct URLs:

```
⚠️ Web search unavailable. Please provide specific URLs to scrape, or skip this research step.
```

### Document Parsing Fallback

Without `firecrawl_parse`, use:

- **Text files** (`.md`, `.txt`, `.java`, `.json`, `.yaml`): `lean-ctx ctx_read` handles these natively with compression.
- **PDFs**: Suggest the user convert to text manually, or use the operating system's built-in text extraction (`pdftotext` on Linux/macOS, `python -m pdfminer` as a fallback).
- **Office documents** (`.docx`, `.xlsx`): Fall back to manual conversion or skip.

```bash
# With Firecrawl:
firecrawl_parse({filePath: "./report.pdf", formats: ["markdown"]})

# Without Firecrawl:
lean-ctx ctx_read --path "./report.md"  # works for text files

# For PDFs, suggest:
echo "Unable to parse PDF without Firecrawl. Try:"
echo "  pdftotext report.pdf report.txt"
echo "  # or convert via an online tool, then re-run the research step"
```

### Monitoring Fallback

Monitors (`firecrawl_monitor_create`, `firecrawl_monitor_check`) are entirely unavailable without Firecrawl. The toolkit:

1. Skips any monitor setup steps
2. Notes the gap in the agent report
3. Does not degrade core orchestration

### Deep Research Fallback

Without `firecrawl_agent` for deep research:

1. Run 3–5 separate `websearch_cited` queries from different angles
2. Synthesize results manually
3. Flag that depth is limited

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Availability Checking

### Health Check Script

The `scripts/health-check.sh` script checks for Firecrawl availability as part of its MCP connectivity lens:

```bash
scripts/health-check.sh
# Output includes:
#   🔍 MCP: firecrawl → ✅ FIRECRAWL_API_KEY set
#   🔍 MCP: firecrawl → ❌ FIRECRAWL_API_KEY not set — Firecrawl disabled
```

### Dedicated Dependency Check

```bash
scripts/check-mcp.sh
# Sample output:
#   ✅ MCP firecrawl: available (FIRECRAWL_API_KEY is set)
#   ❌ MCP firecrawl: NOT available — run: export FIRECRAWL_API_KEY=your_key
```

### In-Process Check (for agents)

Agents check availability at session start:

```bash
# Check if Firecrawl MCP is configured and key is set
if [ -n "$FIRECRAWL_API_KEY" ] && command -v npx &>/dev/null; then
  FIRECRAWL_AVAILABLE=true
else
  FIRECRAWL_AVAILABLE=false
fi
```

### Environment Variable

Firecrawl availability is determined by the `FIRECRAWL_API_KEY` environment variable:

```bash
# Set in .env or shell profile
export FIRECRAWL_API_KEY="fc-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Check current state
echo "${FIRECRAWL_API_KEY:+Firecrawl available}${FIRECRAWL_API_KEY:-Firecrawl NOT available}"
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Configuration

### Enabling Firecrawl

```bash
# 1. Get an API key from https://firecrawl.dev
# 2. Set the environment variable
export FIRECRAWL_API_KEY="fc-your-key-here"

# 3. Enable the MCP in opencode.json
```

### opencode.json Configuration

```jsonc
{
  "mcp": {
    "firecrawl": {
      "disabled": false,                    // Enable Firecrawl MCP
      "command": "npx",
      "args": ["firecrawl-mcp"],
      "env": {
        "FIRECRAWL_API_KEY": "${FIRECRAWL_API_KEY}"
      }
    }
  }
}
```

### Proxy Configuration (Enterprise)

If behind a corporate proxy:

```jsonc
{
  "mcp": {
    "firecrawl": {
      "command": "npx",
      "args": ["firecrawl-mcp"],
      "env": {
        "FIRECRAWL_API_KEY": "${FIRECRAWL_API_KEY}",
        "HTTP_PROXY": "http://proxy.company.com:8080",
        "HTTPS_PROXY": "http://proxy.company.com:8080",
        "NO_PROXY": "localhost,127.0.0.1"
      }
    }
  }
}
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Implementation Guidance

### Health Check Script

The health check should verify Firecrawl but not fail if missing:

```bash
# In scripts/health-check.sh — Firecrawl check lens
check_firecrawl() {
  if [ -n "$FIRECRAWL_API_KEY" ]; then
    echo "✅ Firecrawl API key set — web search available"
    return 0
  else
    echo "ℹ️  Firecrawl not configured — web search degraded (websearch_cited fallback)"
    return 0  # Non-failing — optional dependency
  fi
}
```

### Installer Script

The installer (`scripts/install.sh`) should NOT require Firecrawl:

```bash
# In scripts/install.sh — MCP setup section
setup_mcp_firecrawl() {
  if [ -z "${FIRECRAWL_API_KEY:-}" ]; then
    echo "ℹ️  Skipping Firecrawl MCP (FIRECRAWL_API_KEY not set)"
    echo "   Install later: export FIRECRAWL_API_KEY=your_key && npx firecrawl-mcp"
    return 0
  fi

  echo "✅ Configuring Firecrawl MCP..."
  # ... configuration logic ...
}
```

### Agent Instructions

Every agent that references Firecrawl MCP tools should include a fallback path in its instruction file:

```markdown
## Research Fallback

This agent prefers Firecrawl for web research. If Firecrawl is unavailable:

1. **Web search**: Use `websearch_cited` tool instead of `firecrawl_search`
2. **Document parsing**: Use `lean-ctx ctx_read` for text files; skip binary formats
3. **Deep research**: Run multiple `websearch_cited` queries and synthesize
4. **Monitoring**: Skip monitor features — note in report that they were skipped

Check availability: `scripts/check-mcp.sh` or test for `$FIRECRAWL_API_KEY`
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Agent Degradation

### Developer-Librarian (`@librarian`)

**Primary tools**: `firecrawl_search`, `firecrawl_scrape`, `firecrawl_crawl`, `firecrawl_parse`, `context7_query_docs`, `gh_grep`, `websearch`

**Without Firecrawl**:

| Capability | Degraded Behavior |
|------------|-------------------|
| Web search | Falls back to `websearch_cited` — summaries only, no full page scraping |
| Documentation lookup | Unaffected — uses `context7_query_docs` (independent MCP) |
| Code example search | Unaffected — uses `gh_grep` (independent MCP) |
| Document parsing | Falls back to `lean-ctx ctx_read` for text files; cannot parse PDFs/DOCX |
| Site crawling | Skipped — must provide specific URLs |
| Deep research | Falls back to multi-query `websearch_cited` — less depth, fewer sources |

**Research quality impact**: Medium. The librarian loses the ability to scrape full page content, but can still retrieve summaries and citations via `websearch_cited`. Documentation lookups via `context7` are unaffected.

### Quality Analyst

**Primary tools**: `postgres_*`, `gitnexus`, `graphify`, `lean-ctx`

**Firecrawl relevance**: None. The quality analyst does not use Firecrawl — its MCP section lists `firecrawl` under **denied** MCPs (see `agents/quality-analyst.md`).

**Quality impact**: None.

### Orchestrator (Tech Lead)

**Primary tools**: `lean-ctx`, `gitnexus`, `graphify`

**Firecrawl relevance**: The orchestrator delegates Firecrawl-dependent research to the `@librarian` subagent. It does not call Firecrawl directly.

**Quality impact**: None directly. Research results from `@librarian` may be less comprehensive.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## See Also

| Resource | What It Covers |
|----------|---------------|
| [`usage/firecrawl.md`](../usage/firecrawl.md) | Firecrawl tool reference and usage patterns |
| [`scripts/health-check.sh`](../scripts/health-check.sh) | Health check with MCP dependency verification |
| [`scripts/check-mcp.sh`](../scripts/check-mcp.sh) | Dedicated MCP connectivity checker |
| [`scripts/install.sh`](../scripts/install.sh) | Installer — handles Firecrawl as optional |
| [`agents/developer-librarian.md`](../agents/developer-librarian.md) | Librarian agent — primary Firecrawl consumer |
| [`doc/model-fallback.md`](model-fallback.md) | Broader model fallback strategies |
| [`usage/websearch.md`](../usage/websearch.md) | `websearch_cited` tool reference |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

[firecrawl-optional-shield]: https://img.shields.io/badge/Firecrawl-Optional-green?style=for-the-badge
[firecrawl-optional-url]: #

*Last updated: 2026-06-19. Part of the Workflow State Engine documentation suite.*
