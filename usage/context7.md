# Context7 Usage Guide

> **Repository**: [github.com/upstash/context7](https://github.com/upstash/context7) — up-to-date library docs and code examples for AI agents
> **MCP**: `@upstash/context7-mcp` in opencode.json

## Tools

| Tool                          | What it does                                                |
|-------------------------------|-------------------------------------------------------------|
| `context7_resolve_library_id` | Resolves a package name to a Context7-compatible library ID |
| `context7_query_docs`         | Queries library docs with specific questions                |

## When to use

| When you need…                     | Use                                                 |
|------------------------------------|-----------------------------------------------------|
| How to use a library/framework API | `context7_query_docs({libraryId, query})`           |
| Find the correct library ID        | `context7_resolve_library_id({libraryName, query})` |

## Usage pattern

```javascript
// 1. Resolve the library

context7_resolve_library_id({libraryName: "Next.js", query: "how to do auth"})

// 2. Query docs with the resolved ID

context7_query_docs({libraryId: "/vercel/next.js", query: "middleware authentication"})

```
