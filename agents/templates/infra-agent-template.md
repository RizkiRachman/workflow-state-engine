# Infrastructure Service Agent Overlay
**Applies to:** deployer (goods-price-comparison-deployer)
**Tech Stack:** Docker, shell scripts, Terraform, CI/CD pipelines

## Domain Context
- **Domains:** CI/CD, deployment pipelines, infrastructure provisioning, container orchestration
- **No application code** — infrastructure-as-code and automation only
- **High risk tolerance required** — deployment failures are expensive

## Integration Notes
- Submodule path: `.workflow-engine/`
- opencode.json: uses template with `sumopod/deepseek-v4-flash` model
- Ponytail intensity: **high** — infrastructure shortcuts can cause production outages
- validate-toolkit.sh patched for macOS find compatibility

## Threshold Overrides
| Gate | Value |
|------|-------|
| Score threshold | 80 |
| Max debt items | 2 |
| SDD gate | always |
