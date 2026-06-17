<!-- gitnexus-owned: GITNEXUS-USAGE.md v1 -->

<!-- omit from toc -->
# GitNexus Usage Guide — goods-price-comparison-service

> **Repository**: [github.com/abhigyanpatwari/GitNexus](https://github.com/abhigyanpatwari/GitNexus) — 42k+ stars, code intelligence knowledge graph
>

> **Index**: 4,929 symbols, 10,965 relationships, 300 execution flows, 316 clusters
>

> **MCP**: `opencode.json` → `npx gitnexus mcp`
>

> **Last analyzed**: see `gitnexus://repo/goods-price-comparison-service/context`

[![GitNexus][gitnexus-shield]][gitnexus-url] [![Docs][docs-shield]][docs-url]

<a id="readme-top"></a>

## Table of Contents
1. [Quick Reference — Tools by Use Case](#1-quick-reference--tools-by-use-case)
2. [Before You Edit — Impact Analysis](#2-before-you-edit--impact-analysis)
3. [Before You Commit — Change Detection](#3-before-you-commit--change-detection)
4. [Exploring Unfamiliar Code](#4-exploring-unfamiliar-code)
5. [Debugging Bugs](#5-debugging-bugs)
6. [Safe Refactoring](#6-safe-refactoring)
7. [API Route Analysis](#7-api-route-analysis)
8. [Execution Flow Tracing](#8-execution-flow-tracing)
9. [Architecture Documentation](#9-architecture-documentation)
10. [Index Management](#10-index-management)
11. [CLI Reference](#11-cli-reference)
12. [Resources](#12-resources)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 1. Quick Reference — Tools by Use Case

| When you want to…                      | Tool                                        | Why this one                                     |
|----------------------------------------|---------------------------------------------|--------------------------------------------------|
| Check what breaks if I change a symbol | `impact({target, direction: "upstream"})`   | Blast radius at depth 1/2/3 with risk level      |
| Check what a symbol depends on         | `impact({target, direction: "downstream"})` | All callees and imports                          |
| See all callers of a function          | `context({name})`                           | Categorized references (calls, imports, extends) |
| Find how code works end-to-end         | `query({query: "auth flow"})`               | Process-grouped results with execution traces    |
| Trace uncommitted changes impact       | `detect_changes()`                          | Maps git diff to affected processes              |
| Pre-commit safety check                | `detect_impact` (prompt)                    | Guided analysis with risk summary                |
| Rename a function across files         | `rename({symbol_name, new_name})`           | Graph-aware multi-file rename                    |
| Find API consumer mismatches           | `shape_check({route})`                      | Response keys versus consumer expectations       |
| Map API routes to handlers             | `route_map()`                               | Handler, route, consumer                         |
| Trace a specific execution path        | `context` or process resource               | Full process trace with steps                    |
| Generate architecture docs             | `generate_map` (prompt)                     | Mermaid diagrams from graph                      |
| Write raw Cypher                       | `cypher({query})`                           | Arbitrary graph queries                          |
| Check index freshness                  | `gitnexus://repo/{name}/context`            | Staleness, symbol counts, tool list              |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 2. Before You Edit — Impact Analysis

**Mandatory** before any symbol modification. Prevents breaking changes.

### Standard flow

```javascript
// Check blast radius BEFORE touching code
gitnexus_impact({target: "CategoryService", direction: "upstream"})
// Returns: risk (LOW/MEDIUM/HIGH/CRITICAL), byDepth, affected_processes
```
### What the result means

| Risk                        | Action                                |
|-----------------------------|---------------------------------------|
| LOW (0-3 consumers)         | Safe to proceed                       |
| MEDIUM (4-9 consumers)      | Review before editing                 |
| HIGH (10+ consumers)        | Warn user, discuss approach           |
| CRITICAL (core abstraction) | Do not edit without explicit approval |

### Common patterns

```javascript
// Before modifying a method
gitnexus_impact({target: "findAll", direction: "upstream", kind: "Method"})
// Before modifying a class
gitnexus_impact({target: "AbstractGenericService", direction: "upstream"})
// Before modifying a file
gitnexus_impact({target: "CategoryService.java", direction: "upstream"})
// Check if a class is a god node (hub abstraction)
gitnexus_impact({target: "AbstractGenericService", direction: "upstream", summaryOnly: true})
```
### Anti-patterns

| Don't                            | Do                                   |
|----------------------------------|--------------------------------------|
| Edit without impact analysis     | Always run `impact()` first          |
| Ignore HIGH/CRITICAL risk        | Discuss with user before proceeding  |
| Use find-and-replace for renames | Use `gitnexus_rename`                |
| Commit without `detect_changes`  | Run `detect_changes()` before commit |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 3. Before You Commit — Change Detection

### Check staged and unstaged changes

```javascript
gitnexus_detect_changes()
// Returns: changed symbols, affected processes, risk summary
```
### Check staged changes only

```javascript
gitnexus_detect_changes({scope: "staged"})
```
### Compare against a branch

```javascript
gitnexus_detect_changes({scope: "compare", base_ref: "main"})
```
### What to look for

- Only expected files changed — proceed
- Unintended files modified — review before commit

- Critical processes affected — discuss approach

---

## 4. Exploring Unfamiliar Code

### Step 1: Query by concept

```javascript
// Find everything related to a concept
gitnexus_query({query: "price comparison", task_context: "understanding product pricing flow"})
// Returns processes (execution flows) ranked by relevance
```
### Step 2: Deep-dive into a symbol

```javascript
// 360-degree view of a specific symbol
gitnexus_context({name: "PriceComparisonService"})
// Returns: callers, callees, extends, implements, methods, properties, process participation
```
### Step 3: Read execution traces from resources

```text
gitnexus://repo/goods-price-comparison-service/process/{name}
```
### Step 4: Cross-reference clusters

```text
gitnexus://repo/goods-price-comparison-service/clusters
// Shows all functional areas (Leiden communities)
```
### Quick navigation cheat sheet

```javascript
// "How does X work?"
gitnexus_query({query: "how does product search work", goal: "understand search flow"})
// "What calls this method?"
gitnexus_context({name: "findByCategory", kind: "Method"})
// "Trace this API endpoint"
gitnexus_route_map({route: "/api/products"})
// "Find all providers for this interface"
gitnexus_cypher({
  query: "MATCH (c:Class)-[:CodeRelation {type: 'IMPLEMENTS'}]->(i:Interface {name: 'ProductService'}) RETURN c.name"
})
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 5. Debugging Bugs

### Trace a bug through call chains

```javascript
// Start with known symbol
gitnexus_context({name: "ProductController"})
// Check all callers, callees, and process participation
// Find execution flow
gitnexus_query({query: "product price calculation error", goal: "find bug in price calc"})
// Trace path between two symbols
gitnexus_trace({source: "findPrice", target: "calculateDiscount"})
```
### Full bug investigation flow

1. `gitnexus_query({query: "<error symptom>"})` — find relevant process
2. `gitnexus_context({name: "<suspected class>"})` — see all callers and callees

3. Read process resource — full step-by-step trace
4. `gitnexus_detect_changes()` — check recent changes

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 6. Safe Refactoring

### Rename a symbol

```javascript
// Preview first (dry_run: true by default)
gitnexus_rename({symbol_name: "oldMethodName", new_name: "newMethodName"})
// Graphs finds high-confidence references, text search finds lower-confidence
// Each edit tagged with: "graph" (safe) or "text_search" (review carefully)
```
### Extract or split or refactor

```javascript
// Check blast radius of target BEFORE refactoring
gitnexus_impact({target: "CategoryService", direction: "upstream"})
// After refactoring, verify scope
gitnexus_detect_changes()
```
### Safe rename checklist

- [x] Run `impact()` before touching the symbol
- [x] Use `rename()` (not find-and-replace)

- [x] Review `text_search`-tagged edits for false positives
- [x] Run `detect_changes()` before commit

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 7. API Route Analysis

### Map routes to handlers

```javascript
// All routes
gitnexus_route_map()
// Specific route
gitnexus_route_map({route: "/api/products"})
// Returns: handler files, middleware chain, consumer components
```
### Pre-change impact for API routes

```javascript
// Before modifying an API handler
gitnexus_api_impact({route: "/api/products"})
// Returns: consumer files, response shape, risk level
// Or by handler file
gitnexus_api_impact({file: "src/main/java/.../ProductController.java"})
```
### Check response shape mismatches

```javascript
gitnexus_shape_check({route: "/api/products"})
// Detects: consumer accessing keys not in route's response shape
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 8. Execution Flow Tracing

### Find all processes

```text
gitnexus://repo/goods-price-comparison-service/processes
```
### Read a specific process

```text
gitnexus://repo/goods-price-comparison-service/process/{name}
```
### Or via Cypher

```cypher
MATCH (s)-[r:CodeRelation {type: 'STEP_IN_PROCESS'}]->(p:Process)
WHERE p.heuristicLabel = "ProductSearch"
RETURN s.name, r.step ORDER BY r.step
```
### Process properties

- `heuristicLabel` — human-readable name
- `processType` — for example, "controller"

- `stepCount` — number of steps
- `communities` — functional areas touched

- `entryPointId` and `terminalId` — start and end symbols

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 9. Architecture Documentation

### Generate mermaid diagrams

Trigger the `generate_map` prompt (built into GitNexus MCP):

```javascript
// The prompt returns architecture documentation from the knowledge graph
// with mermaid diagrams
```
### Communities (functional areas)

```text
gitnexus://repo/goods-price-comparison-service/clusters
```
Each cluster has: `heuristicLabel`, `cohesion`, `symbolCount`, `keywords`, `description`.

### God nodes (most connected symbols)

```cypher
MATCH (n)-[r:CodeRelation]->()
WITH n, COUNT(r) AS degree
RETURN n.name, n.kind, degree
ORDER BY degree DESC
LIMIT 10
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 10. Index Management

### Keep the index fresh

```bash
# Standard analyze (wraps --skip-agents-md to avoid CLAUDE.md generation)
bash scripts/gitnexus-analyze.sh
# Or manual flags
npx gitnexus analyze --skip-agents-md
# Full rebuild (if index corrupt)
npx gitnexus analyze --force
# Just update index — no file injection at all
npx gitnexus analyze --index-only
```
### When to re-index

| Trigger                            | Command                                      |
|------------------------------------|----------------------------------------------|
| After significant code changes     | `bash scripts/gitnexus-analyze.sh`           |
| After git pull or merge            | `bash scripts/gitnexus-analyze.sh`           |
| Before a risky refactor            | `bash scripts/gitnexus-analyze.sh`           |
| Index stale (more than 1 hour old) | `npx gitnexus analyze --force`               |
| Index corrupt or weird results     | `npx gitnexus clean && npx gitnexus analyze` |

### Check index status

```bash
npx gitnexus status
# Shows: lastCommit, indexedAt, symbol and relationship counts
```
### Project configuration (`.gitnexusrc`)

```json
{
  "defaultBranch": "develop",
  "skipAgentsMd": true,
  "skipSkills": true
}
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 11. CLI Reference

### Core commands

```bash
npx gitnexus analyze               # Index or update
npx gitnexus analyze --force        # Full rebuild
npx gitnexus analyze --index-only   # Pure index, no file injection
npx gitnexus status                 # Index freshness
npx gitnexus clean                  # Delete index
npx gitnexus list                   # All indexed repos
npx gitnexus wiki                   # Generate docs from graph
```
### Dev workflow wrapper

```bash
bash scripts/gitnexus-analyze.sh    # analyze plus --skip-agents-md
```
### Analyze flags

| Flag                       | Effect                                   |
|----------------------------|------------------------------------------|
| `--force`                  | Full re-index even if up-to-date         |
| `--embeddings`             | Enable semantic search (50k node cap)    |
| `--embeddings 0`           | Embeddings with no cap                   |
| `--skip-agents-md`         | Do not regenerate CLAUDE.md or AGENTS.md |
| `--index-only`             | Pure index — skip all file injection     |
| `--skip-skills`            | Do not install skill files               |
| `--skills`                 | Generate repo-specific skill files       |
| `--default-branch develop` | Branch for regression-compare example    |
| `--worker-timeout 60`      | Increase parse timeout for slow files    |
| `--repair-fts`             | Rebuild FTS indexes only                 |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 12. Resources

### MCP Resources (read-only context)

| Resource                                                        | Description                          |
|-----------------------------------------------------------------|--------------------------------------|
| `gitnexus://repos`                                              | All indexed repositories             |
| `gitnexus://repo/goods-price-comparison-service/context`        | Codebase stats, staleness, tool list |
| `gitnexus://repo/goods-price-comparison-service/clusters`       | All functional clusters              |
| `gitnexus://repo/goods-price-comparison-service/cluster/{name}` | Cluster details                      |
| `gitnexus://repo/goods-price-comparison-service/processes`      | All execution flows                  |
| `gitnexus://repo/goods-price-comparison-service/process/{name}` | Process trace with steps             |
| `gitnexus://repo/goods-price-comparison-service/schema`         | Graph schema for Cypher              |

### MCP Prompts

| Prompt          | Description                             |
|-----------------|-----------------------------------------|
| `detect_impact` | Guided pre-commit change analysis       |
| `generate_map`  | Architecture docs with mermaid diagrams |

### Related skills

| Skill           | Location                                                    | Use When…                     |
|-----------------|-------------------------------------------------------------|-------------------------------|
| Exploring       | `toolkit/skills/gitnexus/gitnexus-exploring/SKILL.md`       | Understanding unfamiliar code |
| Impact Analysis | `toolkit/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` | Pre-edit blast radius         |
| Debugging       | `toolkit/skills/gitnexus/gitnexus-debugging/SKILL.md`       | Tracing bugs                  |
| Refactoring     | `toolkit/skills/gitnexus/gitnexus-refactoring/SKILL.md`     | Safe renames and extractions  |
| Guide           | `toolkit/skills/gitnexus/gitnexus-guide/SKILL.md`           | Tool reference                |
| CLI             | `toolkit/skills/gitnexus/gitnexus-cli/SKILL.md`             | CLI commands                  |

### Index statistics

- **Symbols**: 4,929
- **Relationships**: 10,965

- **Execution flows**: 300
- **Communities (clusters)**: 316

- **Parsed languages**: Java (primary), plus 15 others

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- REFERENCE LINKS -->

[gitnexus-shield]: https://img.shields.io/badge/GitNexus-Code%20Intelligence-181717?style=for-the-badge&logo=git
[gitnexus-url]: #
[docs-shield]: https://img.shields.io/badge/DOCS-文档-blue?style=for-the-badge
[docs-url]: #

