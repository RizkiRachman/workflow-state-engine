# Contract — Workflow State Engine

## Overview

The `contract/` directory is the single source of truth for the Workflow State Engine's orchestration protocol. It is divided into **definition files** (committed schemas and templates that define the contract structure) and **runtime state files** (gitignored, mutated every session). `index.md` is the ONE committed definition file — it embeds all schemas, templates, and rules that govern the orchestration envelope.

## Folder Contract

- `index.md` — **COMMITTED**. Single definition file. Rules, schemas, templates. This file.
- `contract.json` — **GITIGNORED**. Runtime state envelope. Mutates every session.
- `state.md` — **GITIGNORED**. Runtime state log. Mutates every session.
- *(No separate schema files — all definitions embedded inline above)*

## State Machine

```
INIT -> PLAN -> PLAN_SCORED -> EXECUTE -> EXECUTE_SCORED -> REVIEW -> REVIEW_SCORED -> COMPLETE

Any -> BLOCKED (score < 50 or retry >= 3)
```

### Transitions

| Transition | Gate | Condition |
|---|---|---|
| INIT → PLAN | Session created | Always |
| PLAN → PLAN_SCORED | Plan produced | Always |
| PLAN_SCORED → EXECUTE | Spec gate | Score ≥ 70 |
| EXECUTE → EXECUTE_SCORED | Implementation done | Always |
| EXECUTE_SCORED → REVIEW | Code review | Score ≥ 70 |
| REVIEW → REVIEW_SCORED | Review done | Always |
| REVIEW_SCORED → COMPLETE | All gates pass | Score ≥ 70 |
| Any → BLOCKED | Escalation | Score < 50 or retry ≥ 3 |

## Scoring Pipeline (Three-Tier)

### Tier 1 — Rule-Based Checks
- Schema validation failed (-15)
- Permissions violated (-40)
- Blast radius HIGH (-40)
- Writing order wrong (-15)
- Required fields missing (-15)
- Subtotal ≥ 70 → proceed to Tier 2

### Tier 2 — LLM-as-Judge
Scores 0-100 on:
- Requirements fulfillment (0-40)
- Governance compliance (0-30)
- Completeness (0-20)
- Edge cases (0-10)

### Tier 3 — Combined Verdict
- **PASS** (≥ 70): Transition to next state
- **RETRY** (50-69, max 3 attempts): Retry with guidance
- **BLOCKED** (< 50): Human intervention required

## Contract Schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "contract/contract.schema.json",
  "title": "Workflow State Engine — Contract Schema",
  "description": "Validates the shared orchestration envelope (contract/contract.json). This Draft 2020-12 schema enforces the state machine transitions, scoring pipeline, governance, and audit trail for AI agent workflow orchestration.",
  "type": "object",
  "additionalProperties": true,
  "required": [
    "state",
    "contract_version",
    "state_machine_version",
    "session",
    "scope",
    "requirements",
    "decisions",
    "governance",
    "validation",
    "outputs",
    "score",
    "retry",
    "metrics",
    "token_budget",
    "lessons_learned",
    "audit_log"
  ],
  "properties": {
    "state": {
      "description": "Current state machine state. Transitions: INIT → PLAN → PLAN_SCORED → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE. Any → BLOCKED on escalation.",
      "type": "string",
      "enum": ["INIT", "PLAN", "PLAN_SCORED", "EXECUTE", "EXECUTE_SCORED", "REVIEW", "REVIEW_SCORED", "COMPLETE", "BLOCKED"]
    },
    "contract_version": {
      "description": "Semantic version of the contract schema structure.",
      "type": "string",
      "pattern": "^\\d+\\.\\d+\\.\\d+(-[a-zA-Z0-9.]+)?(\\+[a-zA-Z0-9.]+)?$"
    },
    "state_machine_version": {
      "description": "Semantic version of the state machine definition (rules.json).",
      "type": "string",
      "pattern": "^\\d+\\.\\d+\\.\\d+(-[a-zA-Z0-9.]+)?(\\+[a-zA-Z0-9.]+)?$"
    },
    "session": {
      "type": "object",
      "required": ["task_id", "branch", "created_at", "archived_at"],
      "properties": {
        "task_id": {
          "description": "Unique identifier for this task session (e.g. 'developer-fixer-standalone-20260617').",
          "type": "string"
        },
        "branch": {
          "description": "Git branch name from which this session operates.",
          "type": "string"
        },
        "created_at": {
          "description": "ISO 8601 timestamp when this session was created.",
          "type": "string"
        },
        "archived_at": {
          "description": "ISO 8601 timestamp when this session was archived (null if active).",
          "type": ["string", "null"]
        }
      }
    },
    "scope": {
      "type": "object",
      "required": ["included", "excluded", "boundary", "parallel_eligible", "max_parallel_agents"],
      "properties": {
        "included": {
          "description": "File paths, directories, or patterns that are in scope for this task.",
          "type": "array",
          "items": { "type": "string" }
        },
        "excluded": {
          "description": "File paths, directories, or patterns explicitly excluded from scope.",
          "type": "array",
          "items": { "type": "string" }
        },
        "boundary": {
          "description": "Root boundary for scope evaluation (e.g. 'project-root').",
          "type": "string"
        },
        "parallel_eligible": {
          "description": "Whether this task may be parallelized across multiple agents.",
          "type": "boolean"
        },
        "max_parallel_agents": {
          "description": "Maximum number of parallel agents allowed (1-10).",
          "type": "integer",
          "minimum": 1,
          "maximum": 10
        }
      }
    },
    "requirements": {
      "type": "object",
      "required": ["goal", "acceptance_criteria", "constraints"],
      "properties": {
        "goal": {
          "description": "High-level goal statement for this session/task.",
          "type": "string"
        },
        "acceptance_criteria": {
          "description": "List of specific, testable acceptance criteria.",
          "type": "array",
          "items": { "type": "string" }
        },
        "constraints": {
          "description": "List of constraints (technical, time, resource, etc.).",
          "type": "array",
          "items": { "type": "string" }
        }
      }
    },
    "decisions": {
      "type": "object",
      "required": ["approved_architecture", "coding_standard", "rejected_approaches", "adr_log"],
      "properties": {
        "approved_architecture": {
          "description": "Approved architectural approach, or null if not yet decided.",
          "type": ["string", "null"]
        },
        "coding_standard": {
          "description": "Coding conventions and standards to follow.",
          "type": ["string", "null"]
        },
        "rejected_approaches": {
          "description": "Approaches considered and rejected, with rationale.",
          "type": "array",
          "items": { "type": "string" }
        },
        "adr_log": {
          "description": "Architecture Decision Record entries.",
          "type": "array",
          "items": { "$ref": "#/$defs/adr_entry" }
        }
      }
    },
    "governance": {
      "type": "object",
      "required": ["active_agent", "mode", "applicable_skills", "rules_references", "current_guidance", "permissions", "prev_blockers"],
      "properties": {
        "active_agent": {
          "description": "The currently active agent role (e.g. 'developer', 'quality-analyst').",
          "type": "string"
        },
        "mode": {
          "description": "Operating mode of the active agent.",
          "type": "string",
          "enum": ["task-exec", "spec", "review"]
        },
        "applicable_skills": {
          "description": "Names of applicable skills to be loaded for this task.",
          "type": "array",
          "items": { "type": "string" }
        },
        "rules_references": {
          "description": "References to rule files/sections governing this session.",
          "type": "array",
          "items": {
            "type": "object",
            "required": ["source", "sections"],
            "properties": {
              "source": { "type": "string" },
              "sections": {
                "type": "array",
                "items": { "type": "string" }
              }
            }
          }
        },
        "current_guidance": {
          "description": "Current execution guidance or directive from the orchestrator.",
          "type": "object",
          "required": ["do", "dont", "allowed_exec"],
          "properties": {
            "do": {
              "description": "Actions that are explicitly permitted for the active agent.",
              "type": "array",
              "items": { "type": "string" }
            },
            "dont": {
              "description": "Actions that are explicitly forbidden for the active agent.",
              "type": "array",
              "items": { "type": "string" }
            },
            "allowed_exec": {
              "type": "object",
              "required": ["tools", "denied"],
              "properties": {
                "tools": {
                  "description": "Allowed execution tools (e.g. 'lean-ctx_*', 'ctx_shell').",
                  "type": "array",
                  "items": { "type": "string" }
                },
                "denied": {
                  "description": "Explicitly denied execution tools (e.g. 'bash', 'snip').",
                  "type": "array",
                  "items": { "type": "string" }
                }
              }
            }
          }
        },
        "permissions": {
          "type": "object",
          "properties": {
            "read": { "type": "array", "items": { "type": "string" } },
            "write": { "type": "array", "items": { "type": "string" } }
          }
        },
        "prev_blockers": {
          "description": "Previously encountered blockers that were resolved.",
          "type": "array",
          "items": { "type": "string" }
        }
      }
    },
    "validation": {
      "type": "object",
      "required": ["block_on", "rule_overrides"],
      "properties": {
        "block_on": {
          "type": "object",
          "required": ["max_test_failures", "max_score_drop", "max_compile_errors"],
          "properties": {
            "max_test_failures": {
              "description": "Maximum allowed test failures before blocking (0-10).",
              "type": "integer",
              "minimum": 0,
              "maximum": 10
            },
            "max_score_drop": {
              "description": "Maximum allowed score drop percentage (0-100).",
              "type": "integer",
              "minimum": 0,
              "maximum": 100
            },
            "max_compile_errors": {
              "description": "Maximum allowed compile errors before blocking (0-10).",
              "type": "integer",
              "minimum": 0,
              "maximum": 10
            }
          }
        },
        "rule_overrides": {
          "description": "Overrides for specific validation rules. Free-form object.",
          "type": "object"
        }
      }
    },
    "outputs": {
      "type": "object",
      "required": ["plan", "architecture", "code_changes", "test_results", "agent_reports", "score_summary"],
      "properties": {
        "plan": {
          "description": "Implementation plan produced by system-analyst or planner, or null if not yet produced.",
          "type": ["string", "null"]
        },
        "architecture": {
          "description": "Architecture documentation output, or null if not yet produced.",
          "type": ["string", "null"]
        },
        "code_changes": {
          "description": "List of code changes made during this session.",
          "type": "array",
          "items": { "$ref": "#/$defs/code_change" }
        },
        "test_results": {
          "description": "Aggregate test results, or null if not yet run.",
          "type": ["string", "null"]
        },
        "agent_reports": {
          "description": "Reports produced by agents during execution.",
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "agent": { "type": "string" },
              "report": { "type": "string" }
            }
          }
        },
        "score_summary": {
          "description": "Summary of scoring results, or null if not yet scored.",
          "type": ["string", "null"]
        }
      }
    },
    "score": {
      "description": "Three-tier scoring pipeline: rule checks → LLM-as-judge → combined verdict.",
      "type": "object",
      "required": ["rules", "judge", "combined", "verdict"],
      "properties": {
        "rules": {
          "description": "Rule-based scoring results (tier 1).",
          "type": "object",
          "required": ["pass", "fail", "deductions", "subtotal"],
          "properties": {
            "pass": {
              "description": "Number of passing rule-based checks.",
              "type": "integer",
              "minimum": 0
            },
            "fail": {
              "description": "Number of failing rule-based checks.",
              "type": "integer",
              "minimum": 0
            },
            "deductions": {
              "description": "Total deduction from failed checks.",
              "type": "integer",
              "minimum": 0
            },
            "subtotal": {
              "description": "Subtotal score from tier 1 rule checks (0-100).",
              "type": "integer",
              "minimum": 0,
              "maximum": 100
            }
          }
        },
        "judge": {
          "description": "LLM-as-judge evaluation (tier 2).",
          "type": "object",
          "required": ["score", "rationale", "missing_items"],
          "properties": {
            "score": {
              "description": "Judge score from 0-100.",
              "type": "integer",
              "minimum": 0,
              "maximum": 100
            },
            "rationale": {
              "description": "Rationale for the judge score.",
              "type": "string"
            },
            "missing_items": {
              "description": "Items identified as missing or inadequate by the judge.",
              "type": "array",
              "items": { "type": "string" }
            }
          }
        },
        "combined": {
          "description": "Combined score from tier 3 (weighted/aggregated) (0-100).",
          "type": "integer",
          "minimum": 0,
          "maximum": 100
        },
        "verdict": {
          "description": "Combined verdict. INIT for unscored, PASS (≥70), RETRY (50-69), BLOCKED (<50 or max retries).",
          "type": "string",
          "enum": ["INIT", "PASS", "RETRY", "BLOCKED"]
        }
      }
    },
    "retry": {
      "type": "object",
      "required": ["current_phase", "attempt", "max_attempts", "score_threshold", "escalation_threshold", "issues", "phase_issues", "escalation_trace"],
      "properties": {
        "current_phase": {
          "description": "Current retry phase name, or null if no retry in progress.",
          "type": ["string", "null"]
        },
        "attempt": {
          "description": "Current attempt number (0 = first attempt).",
          "type": "integer",
          "minimum": 0
        },
        "max_attempts": {
          "description": "Maximum allowed retry attempts (1-10).",
          "type": "integer",
          "minimum": 1,
          "maximum": 10
        },
        "score_threshold": {
          "description": "Score threshold for PASS (≥ this value = pass).",
          "type": "integer",
          "minimum": 0,
          "maximum": 100
        },
        "escalation_threshold": {
          "description": "Score below which escalation/BLOCKED is triggered.",
          "type": "integer",
          "minimum": 0,
          "maximum": 100
        },
        "issues": {
          "description": "Issues encountered (legacy field, overlaps with phase_issues).",
          "type": "array",
          "items": { "type": "string" }
        },
        "phase_issues": {
          "description": "Issues encountered during the current phase.",
          "type": "array",
          "items": { "type": "string" }
        },
        "escalation_trace": {
          "description": "Trace of escalation decisions made during retries.",
          "type": "array",
          "items": { "type": "string" }
        }
      }
    },
    "metrics": {
      "type": "object",
      "required": ["cost_tokens", "elapsed_ms", "agents_used", "phases_completed", "phase_durations"],
      "properties": {
        "cost_tokens": {
          "description": "Total token cost incurred during this session.",
          "type": "integer",
          "minimum": 0
        },
        "elapsed_ms": {
          "description": "Total elapsed time in milliseconds.",
          "type": "integer",
          "minimum": 0
        },
        "agents_used": {
          "description": "Names of agents that were used in this session.",
          "type": "array",
          "items": { "type": "string" }
        },
        "phases_completed": {
          "description": "Phases/states that have been completed.",
          "type": "array",
          "items": { "type": "string" }
        },
        "phase_durations": {
          "description": "Duration per phase in milliseconds, keyed by phase name.",
          "type": "object",
          "additionalProperties": { "type": "integer", "minimum": 0 }
        }
      }
    },
    "token_budget": {
      "description": "Token budget enforcement settings for this session.",
      "type": "object",
      "required": ["max_per_session", "warning_threshold", "hard_limit", "max_per_phase", "max_per_subagent_call", "current_session_usage", "phase_usage"],
      "properties": {
        "max_per_session": {
          "description": "Maximum tokens allowed per session.",
          "type": "integer",
          "minimum": 0
        },
        "warning_threshold": {
          "description": "Fraction (0.0-1.0) of budget that triggers a warning.",
          "type": "number",
          "minimum": 0,
          "maximum": 1
        },
        "hard_limit": {
          "description": "Fraction (0.0-1.0) of budget that triggers a hard block.",
          "type": "number",
          "minimum": 0,
          "maximum": 1
        },
        "max_per_phase": {
          "description": "Per-phase token budgets, keyed by phase name.",
          "type": "object",
          "additionalProperties": { "type": "integer", "minimum": 0 }
        },
        "max_per_subagent_call": {
          "description": "Maximum tokens per subagent delegation.",
          "type": "integer",
          "minimum": 0
        },
        "current_session_usage": {
          "description": "Current token usage for this session.",
          "type": "integer",
          "minimum": 0
        },
        "phase_usage": {
          "description": "Current per-phase token usage, keyed by phase name.",
          "type": "object",
          "additionalProperties": { "type": "integer", "minimum": 0 }
        }
      }
    },
    "lessons_learned": {
      "description": "Cross-session lessons, gotchas, and patterns discovered during execution.",
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "category": { "type": "string" },
          "key": { "type": "string" },
          "value": { "type": "string" },
          "severity": { "type": "string", "enum": ["critical", "warning", "info"] }
        }
      }
    },
    "audit_log": {
      "description": "Append-only log of state machine transitions and scoring snapshots.",
      "type": "array",
      "items": { "$ref": "#/$defs/audit_entry" }
    }
  },
  "$defs": {
    "adr_entry": {
      "description": "An Architecture Decision Record entry.",
      "type": "object",
      "properties": {
        "id": {
          "description": "ADR identifier (e.g. 'ADR-001').",
          "type": "string"
        },
        "title": {
          "description": "Short title of the decision.",
          "type": "string"
        },
        "status": {
          "description": "Decision status (proposed, accepted, deprecated, superseded).",
          "type": "string"
        },
        "context": {
          "description": "Context and motivation for the decision.",
          "type": "string"
        },
        "decision": {
          "description": "The decision made.",
          "type": "string"
        },
        "consequences": {
          "description": "Consequences of the decision.",
          "type": "string"
        },
        "date": {
          "description": "ISO 8601 date of the decision.",
          "type": "string"
        }
      }
    },
    "code_change": {
      "description": "A single code change entry (file created, modified, or deleted).",
      "type": "object",
      "properties": {
        "file": {
          "description": "Path of the changed file.",
          "type": "string"
        },
        "action": {
          "description": "Type of change.",
          "type": "string",
          "enum": ["created", "modified", "deleted"]
        },
        "lines_added": {
          "description": "Number of lines added.",
          "type": "integer",
          "minimum": 0
        },
        "lines_removed": {
          "description": "Number of lines removed.",
          "type": "integer",
          "minimum": 0
        },
        "summary": {
          "description": "Brief summary of the change.",
          "type": "string"
        }
      }
    },
    "audit_entry": {
      "description": "A single state machine transition audit entry.",
      "type": "object",
      "required": ["timestamp", "prev_state", "new_state", "triggered_by", "transition_reason"],
      "properties": {
        "timestamp": {
          "description": "ISO 8601 timestamp of the transition.",
          "type": "string"
        },
        "prev_state": {
          "description": "Previous state before the transition.",
          "type": "string"
        },
        "new_state": {
          "description": "New state after the transition.",
          "type": "string"
        },
        "triggered_by": {
          "description": "Agent or entity that triggered the transition.",
          "type": "string"
        },
        "transition_reason": {
          "description": "Reason or justification for the transition.",
          "type": "string"
        },
        "score_snapshot": {
          "description": "Snapshot of the score object at the time of transition (nullable).",
          "anyOf": [
            { "$ref": "#/$defs/scoring_snapshot" },
            { "type": "null" }
          ]
        }
      }
    },
    "scoring_snapshot": {
      "description": "Snapshot of scoring state at a point in time.",
      "type": "object",
      "properties": {
        "rules_subtotal": {
          "description": "Rule-based scoring subtotal.",
          "type": "integer",
          "minimum": 0,
          "maximum": 100
        },
        "judge_score": {
          "description": "LLM judge score.",
          "type": "integer",
          "minimum": 0,
          "maximum": 100
        },
        "combined": {
          "description": "Combined score.",
          "type": "integer",
          "minimum": 0,
          "maximum": 100
        },
        "verdict": {
          "description": "Verdict at snapshot time.",
          "type": "string",
          "enum": ["INIT", "PASS", "RETRY", "BLOCKED"]
        }
      }
    }
  }
}

```

## State Template

```markdown
# STATE — Workflow State Engine
## Current Focus
<!-- Current task or phase — updated each session -->

## Known Blockers
<!-- Active blockers preventing progress -->

## Activity Log
<!-- Format: [YYYY-MM-DD] **Task name**: Brief desc of what was done -->
```

## Superpowers Contract

```json
{
  "$schema": "contract/contract.schema.json",
  "$id": "contract/superpowers-contract.json",
  "title": "Workflow State Engine — Superpowers Contract",
  "description": "Registers plugin, skill, MCP server, and configuration overrides for the orchestration superpowers framework. Loaded at session start to enable extended capabilities beyond the core contract.",
  "type": "object",
  "required": [
    "contract_version",
    "plugins",
    "skills",
    "mcp_servers",
    "configuration_overrides",
    "tool_permissions"
  ],
  "properties": {
    "contract_version": {
      "description": "Semantic version of this superpowers contract schema.",
      "type": "string",
      "pattern": "^\\d+\\.\\d+\\.\\d+(-[a-zA-Z0-9.]+)?(\\+[a-zA-Z0-9.]+)?$"
    },
    "plugins": {
      "description": "Registered plugins for the superpowers framework.",
      "type": "object",
      "required": ["available", "active"],
      "properties": {
        "available": {
          "description": "List of all available plugins.",
          "type": "array",
          "items": { "$ref": "#/$defs/plugin_entry" }
        },
        "active": {
          "description": "List of currently active plugin names.",
          "type": "array",
          "items": { "type": "string" }
        }
      }
    },
    "skills": {
      "description": "Registered skills for the superpowers framework.",
      "type": "object",
      "required": ["available", "active"],
      "properties": {
        "available": {
          "description": "List of all available skills.",
          "type": "array",
          "items": { "$ref": "#/$defs/skill_entry" }
        },
        "active": {
          "description": "List of currently active skill names.",
          "type": "array",
          "items": { "type": "string" }
        }
      }
    },
    "mcp_servers": {
      "description": "Registered MCP server configurations.",
      "type": "object",
      "required": ["available", "active"],
      "properties": {
        "available": {
          "description": "List of all available MCP server configs.",
          "type": "array",
          "items": { "$ref": "#/$defs/mcp_server_entry" }
        },
        "active": {
          "description": "List of currently active MCP server names.",
          "type": "array",
          "items": { "type": "string" }
        }
      }
    },
    "configuration_overrides": {
      "description": "Overrides for specific superpowers configuration values.",
      "type": "object",
      "additionalProperties": true
    },
    "tool_permissions": {
      "description": "Tool-level permission overrides for superpowers components.",
      "type": "object",
      "required": ["plugins", "skills", "mcp_servers"],
      "properties": {
        "plugins": {
          "description": "Plugin tool permission overrides, keyed by plugin name.",
          "type": "object",
          "additionalProperties": {
            "type": "object",
            "properties": {
              "allowed_tools": {
                "type": "array",
                "items": { "type": "string" }
              },
              "denied_tools": {
                "type": "array",
                "items": { "type": "string" }
              }
            }
          }
        },
        "skills": {
          "description": "Skill tool permission overrides.",
          "type": "object",
          "additionalProperties": {
            "type": "object",
            "properties": {
              "allowed_tools": {
                "type": "array",
                "items": { "type": "string" }
              },
              "denied_tools": {
                "type": "array",
                "items": { "type": "string" }
              }
            }
          }
        },
        "mcp_servers": {
          "description": "MCP server tool permission overrides.",
          "type": "object",
          "additionalProperties": {
            "type": "object",
            "properties": {
              "allowed_tools": {
                "type": "array",
                "items": { "type": "string" }
              },
              "denied_tools": {
                "type": "array",
                "items": { "type": "string" }
              }
            }
          }
        }
      }
    }
  },
  "$defs": {
    "plugin_entry": {
      "description": "A registered plugin definition.",
      "type": "object",
      "required": ["name", "version", "description", "enabled"],
      "properties": {
        "name": { "type": "string" },
        "version": { "type": "string" },
        "description": { "type": "string" },
        "enabled": { "type": "boolean" },
        "config": {
          "type": "object",
          "additionalProperties": true
        },
        "dependencies": {
          "type": "array",
          "items": { "type": "string" }
        }
      }
    },
    "skill_entry": {
      "description": "A registered skill definition.",
      "type": "object",
      "required": ["name", "version", "description", "enabled"],
      "properties": {
        "name": { "type": "string" },
        "version": { "type": "string" },
        "description": { "type": "string" },
        "enabled": { "type": "boolean" },
        "location": { "type": "string" },
        "triggers": {
          "type": "array",
          "items": { "type": "string" }
        },
        "dependencies": {
          "type": "array",
          "items": { "type": "string" }
        }
      }
    },
    "mcp_server_entry": {
      "description": "A registered MCP server configuration.",
      "type": "object",
      "required": ["name", "version", "command", "enabled"],
      "properties": {
        "name": { "type": "string" },
        "version": { "type": "string" },
        "command": { "type": "string" },
        "args": {
          "type": "array",
          "items": { "type": "string" }
        },
        "env": {
          "type": "object",
          "additionalProperties": { "type": "string" }
        },
        "enabled": { "type": "boolean" },
        "allowed_tools": {
          "type": "array",
          "items": { "type": "string" }
        },
        "denied_tools": {
          "type": "array",
          "items": { "type": "string" }
        }
      }
    }
  }
}

```

## Session Lifecycle Protocol

1. **Load** — Load orchestration envelope from lean-ctx knowledge
2. **Check branch** — Never work on main/master (STOP if on main)
3. **Create branch** — `feature/<YYYYMMDD>-<description>` if needed
4. **Transition** — Step through states with scoring gates at each boundary
5. **Persist** — Save envelope after every state change via `lean-ctx ctx_knowledge remember`
6. **Snapshot** — Archive to `session/` for audit trail via `scripts/snapshot-contract.sh`
7. **Post-flight** — Run impact analysis, detect changes, persist gotchas

## Source Definitions

All three embedded definitions above are defined directly in this file. No separate definition/ directory.