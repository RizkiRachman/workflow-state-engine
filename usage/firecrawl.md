# Firecrawl Usage Guide

> **Repository**: [github.com/firecrawl/firecrawl-mcp-server](https://github.com/firecrawl/firecrawl-mcp-server) — web scraping + search + crawling for AI agents
> **MCP**: `firecrawl-mcp` in opencode.json | **API key**: `$FIRECRAWL_API_KEY`

## Tools by category

### Search

| Tool                        | When to use                                  |
|-----------------------------|----------------------------------------------|
| `firecrawl_search`          | Web search with full page content extraction |
| `firecrawl_search_feedback` | Send feedback + earn credit refund           |

### Scrape

| Tool               | When to use                                              |
|--------------------|----------------------------------------------------------|
| `firecrawl_scrape` | Single page content — markdown, JSON, or structured data |
| `firecrawl_parse`  | Parse local files (PDF, DOCX, XLSX, etc.)                |

### Crawl / Map

| Tool              | When to use                              |
|-------------------|------------------------------------------|
| `firecrawl_crawl` | Bulk extract content from an entire site |
| `firecrawl_map`   | Discover all URLs on a website           |

### Interact

| Tool                      | When to use                                      |
|---------------------------|--------------------------------------------------|
| `firecrawl_interact`      | Click buttons, fill forms, login flows on a page |
| `firecrawl_interact_stop` | Free the browser session                         |

### Monitor

| Tool                                   | When to use                                    |
|----------------------------------------|------------------------------------------------|
| `firecrawl_monitor_create`             | Watch a page for changes (pricing, docs, etc.) |
| `firecrawl_monitor_check`              | Get diff results for a monitor check           |
| `firecrawl_monitor_list/delete/update` | Manage monitors                                |

### Agent / Extract

| Tool                     | When to use                                   |
|--------------------------|-----------------------------------------------|
| `firecrawl_agent`        | Autonomous multi-page research agent          |
| `firecrawl_agent_status` | Poll agent for results                        |
| `firecrawl_extract`      | Structured data extraction from specific URLs |

## Quick pattern

```javascript
// Search first
firecrawl_search({query: "latest Spring Boot 3.4 features", limit: 5})
// Then scrape the best result
firecrawl_scrape({url: "https://example.com/article", formats: ["markdown"]})
// For specific data, use JSON schema
firecrawl_scrape({
  url: "https://example.com/pricing",
  formats: ["json"],
  jsonOptions: { prompt: "Extract pricing tiers", schema: { /* ... */ } }
})
```
