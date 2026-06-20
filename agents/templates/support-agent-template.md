# Support Service Agent Overlay
**Applies to:** automation, agent-helper, claude-service, properties
**Tech Stack:** Python or Node scripts, no persistence, lightweight automation

## Domain Context
- **Domains:** scheduled tasks, LLM prompts, configuration management, property files
- **No persistent storage** — stateless automation and configuration
- **Minimal surface area** — focus on correctness and reliability

## Integration Notes
- Submodule path: `.workflow-engine/`
- opencode.json: uses template with `sumopod/deepseek-v4-flash` model
- Ponytail intensity: **low** — simple scripts, low risk of abstraction bloat

## Threshold Overrides
| Gate | Value |
|------|-------|
| Score threshold | 65 |
| Max debt items | 8 |
| SDD gate | never |
