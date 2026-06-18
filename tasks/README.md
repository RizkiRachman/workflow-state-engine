# Task Board — Sprint Workflow

```
tasks/
├── backlogs/      # Gap analyses, research notes, exploration outputs
├── planning/      # Picked from backlog → analyzed and planned
├── development/   # Picked from planning → implemented + reviewed
└── review/        # Picked from dev → reviewed; delete file when done
```

## Workflow

1. **Backlog** — Drop any research, gap analysis, exploration output here
2. **Planning** — Pick a file from backlog, analyze deeper, create implementation plan
3. **Development** — Pick from planning, implement, review
4. **Review** — Pick from development, verify coverage; **delete file when done**

## Rules

- Files move forward only (backlog → planning → dev → review → deleted)
- Each file tracks one topic/decision
- No file stays in review — it either gets done and deleted, or goes back to backlog for more research
- `/tasks/` is gitignored — this is ephemeral sprint board state

## Current Status

| Stage | Files |
|-------|-------|
| 🟡 Backlogs | `architecture-backlog-20260618.md`, `duplication-analysis.md`, `meta-analysis-gaps-20260618.md` |
| 🟢 Planning | (empty) |
| 🔵 Development | (empty) |
| 🟣 Review | `ponytail-explore.md`, `vercel-explore.md` |