# UI Service Agent Overlay
**Applies to:** dashboard (goods-price-comparison-dashboard)
**Tech Stack:** React/TypeScript, charts, REST API client

## Domain Context
- **Domains:** grant management, user settings, visualization
- **APIs consumed:** `GET /api/grants`, `POST /api/grants`
- **No persistence layer** — read-only views from service APIs
- **Legacy agents archived** in `archived-sessions/agents-backup/`

## Integration Notes
- Submodule path: `.workflow-engine/`
- opencode.json: merges toolkit template with existing Sumopod + Bluesminds providers
- Ponytail intensity: **medium** — UI components can tolerate some flexibility

## Threshold Overrides
| Gate | Value |
|------|-------|
| Score threshold | 70 |
| Max debt items | 5 |
| SDD gate | >3 files |
