# Morph Usage Guide — goods-price-comparison-service

> **Plugin**: `@morphllm/opencode-morph-plugin` — MCP plugin for code edits + semantic search across codebases and public GitHub repos.
>
> **Tools**: `morph_edit`, `warpgrep_codebase_search`, `warpgrep_github_search`, `gh_grep_searchGitHub`

## 1. Tool Reference

| Tool | Type | Description |
|------|------|-------------|
| `morph_edit` | Edit | Large/scattered file edits via partial-file merging. Avoids fragile exact-string matching for files 300+ lines or whitespace-sensitive changes. |
| `warpgrep_codebase_search` | Search | Natural-language, agentic code search over the **local** checked-out repo. Multi-turn ripgrep-powered exploration. |
| `warpgrep_github_search` | Search | Natural-language search over **public GitHub repos**. Use for library/SDK internals when docs aren't enough. |
| `gh_grep_searchGitHub` | Search | Exact/semantic search across 1M+ public GitHub repos. Use for finding real-world implementation patterns. |

## 2. morph_edit — Large & Scattered Edits

Use `morph_edit` when:
- Editing files **300+ lines** where exact-string matching is fragile (e.g., `application/domain/service/` services or `infrastructure/adapter/persistence/` repositories)
- **Multiple scattered changes** in one file (e.g., renaming methods, reordering, adding fields across a class)
- **Whitespace-sensitive edits** — Java/Spring Boot files with nested blocks, annotations, and indentation patterns
- **Complex refactors** inside an existing file (extract method, split class, reorganize imports)

Do **NOT** use `morph_edit` for:
- Small exact `oldString` → `newString` replacements — use native `edit` instead
- Creating **brand new files** — use `write` instead
- Edits in **readonly agents** — switch to a write-capable agent (e.g., `developer` or `developer-fixer`)

**Setup**: Requires `MORPH_API_KEY` in environment. If unconfigured, fall back to native `edit`.

## 3. warpgrep_codebase_search — Local Code Search

Use for **natural-language, exploratory queries** against `goods-price-comparison-service`:

```
"How does receipt processing work across services?"
"Find the price comparison flow"
"Where is error handling in the web adapter layer?"
"How does the shopping list event flow work?"
```

Do **NOT** use for exact keyword lookups (function names, variable names, error strings). Use `grep` or `read` instead. The tool is designed for exploration, not precision matching.

This tool is **safe for all agents** (read-only).

## 4. warpgrep_github_search — Public Repo Search

**Always prefer** `warpgrep_github_search` over web search or docs fetching when investigating how an open-source library/SDK works internally.

Use when:
- You need **implementation-level understanding** of a dependency (e.g., "How does Spring Boot `@Async` handle thread pools?")
- **Docs URLs return 404s** or are incomplete
- User asks how an external library works (auth, retries, sessions, internals)

**Parameters**: Provide exactly **one** repository locator:
- `owner_repo`: `"spring-projects/spring-boot"` or `"projectlombok/lombok"`
- `github_url`: `"https://github.com/spring-projects/spring-boot"`

**Inference rule**: When the user doesn't provide a repo, infer the canonical GitHub owner/repo from the package name using the matching ecosystem registry (e.g., `org.springframework.boot` → `spring-projects/spring-boot`).

Do **NOT** use for the current checked-out local repo — use `warpgrep_codebase_search` instead.

## 5. gh_grep_searchGitHub — Public GitHub Pattern Search

Search across **1M+ indexed public GitHub repositories** for implementation patterns:

```json
{"name": "gh_grep_searchGitHub", "arguments": {
  "query": "Hexagonal architecture Spring Boot @Service",
  "language": ["Java"]
}}
```

Use when:
- You need to see how **other projects** implement a pattern (e.g., hexagonal repository adapters, event handling with `@TransactionalEventListener`)
- Finding reference implementations for a specific Spring Boot feature
- Learning idiomatic use of Java 21 features (records, sealed classes, pattern matching) in real codebases

This tool is **safe for all agents** (read-only).

## 6. Fallback Policy

| Primary Tool | If Fails | Fallback |
|---|---|---|
| `morph_edit` | API error or timeout | Native `edit` tool |
| `morph_edit` | Blocked in readonly agent | Switch to `developer` or `developer-fixer` agent |
| `morph_edit` | Entire file replace needed | `write` tool |
| `warpgrep_codebase_search` | Fails or times out | `grep` + `read` (exact searches) |
| `warpgrep_github_search` | Fails | Clone repo locally (only if task justifies setup cost) |

**Always use `lean-ctx ctx_shell`** for shell commands — never `bash` or `snip` (both denied in project permissions).

## 7. Anti-Patterns

- **Do NOT** use `edit` first for large (300+ lines), scattered, or whitespace-sensitive edits — start with `morph_edit`
- **Do NOT** use `morph_edit` to create new files — use `write`
- **Do NOT** force `morph_edit` from readonly agents unless explicitly configured with `morph_edit: true`
- **Do NOT** use `warpgrep_codebase_search` for exact string/keyword lookups — use `grep` instead
- **Do NOT** use `warpgrep_github_search` on the current checked-out local repo — use `warpgrep_codebase_search`
- **Do NOT** use `gh_grep_searchGitHub` when a specific repo is the target — use `warpgrep_github_search` instead
