# Postgres MCP Usage Guide

> **MCP**: `@yawlabs/postgres-mcp` in opencode.json | **Connection**: `$PG_MCP_URL`
>

> **Purpose**: Database inspection, schema review, query analysis, and performance tuning.

## Tools by Category

### Read & Query

| Tool | When to use |
|------|-------------|
| `pg_query` | Execute SQL (requires ALLOW_WRITES=1 for writes) |
| `pg_readonly` | Safe read-only SQL (always wrapped in READ ONLY txn) |
| `pg_explain` | Get query plan with optional ANALYZE + hypothetical indexes |

### Schema Inspection

| Tool | When to use |
|------|-------------|
| `pg_describe_table` | Get full table schema: columns, PK, FKs, indexes, constraints |
| `pg_list_tables` | List all tables in a schema with estimated row counts |
| `pg_list_views` | List views with SQL definitions |
| `pg_list_schemas` | List non-system schemas |
| `pg_search_columns` | Find which tables have a column by name (LIKE pattern) |
| `pg_list_functions` | List functions/procedures with signatures |
| `pg_list_extensions` | Check installed extensions (pgvector, uuid-ossp, etc.) |

### Performance & Health

| Tool | When to use |
|------|-------------|
| `pg_health` | Quick server snapshot: version, db size, connections, active queries |
| `pg_top_queries` | Top N slow queries by total/mean time (requires pg_stat_statements) |
| `pg_unused_indexes` | Indexes never scanned — candidates for removal |
| `pg_table_bloat` | Tables with high dead tuple ratio — need VACUUM |
| `pg_seq_scan_tables` | Tables with high seq scan ratio — missing index candidates |
| `pg_inspect_locks` | Current lock contention — blocked/blocking sessions |

### Security & Admin

| Tool | When to use |
|------|-------------|
| `pg_advisor` | Rolled-up DBA lint: sequence exhaustion, tables without PK, RLS gaps |
| `pg_table_privileges` | Which roles have which privileges on tables |
| `pg_list_roles` | List database roles with attributes |
| `pg_replication_status` | Replication slots, connected replicas, WAL position |
| `pg_kill` | Cancel (SIGINT) or terminate (SIGTERM) a backend by PID |

## When to Use (by Agent Role)

| Agent | Postgres Tools | Use Case |
|-------|---------------|----------|
| **quality-analyst** | `describe_table`, `query`, `readonly`, `search_columns`, `unused_indexes`, `seq_scan_tables`, `health` | DB schema review, query analysis, index/performance review |
| **quality-analyst-learner** | `health`, `describe_table` | Verify DB changes as part of post-learning validation |
| **developer** | `describe_table`, `readonly` | Understand schema before writing data access code |
| **system-analyst** | `describe_table`, `search_columns` | Impact analysis — which tables/columns are affected by a change |
| **All others** | No postgres access needed | Delegate DB review to quality-analyst |

## Usage Patterns

### Schema review (quality-analyst during code review)

```javascript
// Check table structure

pg_describe_table({table: "products"})

// Check for unused indexes

pg_unused_indexes({schema: "public"})

// Check for tables needing VACUUM

pg_table_bloat({schema: "public", minDeadRatio: 0.2})

// Check for query performance issues

pg_seq_scan_tables({schema: "public", minSize: 1000})

```
### Impact analysis (system-analyst during planning)

```javascript
// Find columns affected by a change

pg_search_columns({pattern: "product_id"})

// Check table schema

pg_describe_table({table: "receipts"})

```
### Quick health check

```javascript
pg_health()

// Returns: version, db_size, connections, active queries, table count

```
## Safety Notes

- All agents have `read`/`edit`/`grep`/`bash` blocked. Postgres tools are read-capable via `pg_readonly` (guaranteed read-only).
- Use `pg_readonly` for all analysis queries unless you explicitly need to write (requires env ALLOW_WRITES=1).

- Large result sets are truncated to 1000 rows with a `truncated: true` flag.

