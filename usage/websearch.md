# Web Search Usage Guide

Two web search tools are available:

---

## 1. websearch_cited (Gemini-style grounded search)

> **Plugin**: `opencode-websearch-cited` ([github.com/ghoulr/opencode-websearch-cited](https://github.com/ghoulr/opencode-websearch-cited))
> **Model**: configured in opencode.json under `sumopod.provider.websearch_cited`

| Tool              | What it does                                             |
|-------------------|----------------------------------------------------------|
| `websearch_cited` | Grounded web search with inline citations + Sources list |

**When to use**: Quick lookups, fact-checking, news, documentation search.

```javascript
websearch_cited({query: "Spring Boot 3.4 new features"})

// Returns: concise digest with inline citations and source URLs

```
**Limit**: max 5 parallel calls (rate limited by LLM provider).

---

## 2. websearch_web_search_exa (Exa AI)

> **Source**: Exa AI SDK ([github.com/exa-labs/ai-sdk](https://github.com/exa-labs/ai-sdk))
> **Description**: Semantic search — finds results by meaning, not just keywords

| Tool                       | What it does                                      |
|----------------------------|---------------------------------------------------|
| `websearch_web_search_exa` | Semantic web search with clean content extraction |

**When to use**: Complex queries where meaning matters more than exact keywords; finding people, companies, niche topics.

```javascript
// Semantic query (describe the ideal page)

websearch_web_search_exa({

  query: "blog post comparing React and Vue performance",

  numResults: 10

})

// Find people

websearch_web_search_exa({

  query: "category:people John Doe software engineer"

})

// Find companies

websearch_web_search_exa({

  query: "category:company AI startup series A funding"

})

```
**Tip**: Describe the ideal page, not keywords. "blog post comparing React and Vue performance" not "React vs Vue".

