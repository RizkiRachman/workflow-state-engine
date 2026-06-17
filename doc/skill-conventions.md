<!-- omit from toc -->
# Skill Conventions

[![Doc][doc-shield]][doc-url]

## Directory Structure

Every skill follows this format for cross-agent portability:

```
skills/<name>/
  package.json        # npm metadata
  SKILL.md            # main instruction file
  instructions/       # (optional) additional instruction files
  prompts/            # (optional) reusable prompt templates
  .cursor/rules/      # (optional) Cursor-specific rules
  .windsurf/rules/    # (optional) Windsurf-specific rules
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Cross-Agent Placement

Each skill is compatible with these agents depending on the target:

| Agent | File Location |
|-------|---------------|
| OpenCode | `.opencode/skills/<name>/SKILL.md` |
| Claude Code | Project root `CLAUDE.md` or `instructions/<name>.md` |
| Cursor | `.cursor/rules/<name>.mdc` |
| Windsurf | `.windsurf/rules/<name>.md` |
| Cline | `.clinerules/<name>.md` |
| GitHub Copilot | `.github/copilot-instructions.md` (merged) |

### Skill-to-Agent Mapping

Specific skills and their primary agent assignments:

| Skill | Primary Agent | Purpose |
|-------|--------------|---------|
| `audit-observability` | `tech-lead` | State contract audit trail, orchestration observability, score analytics, cross-service consistency enforcement |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Publishing

Skills can be published to skills.sh via `npx skills deploy`. Each skill must have:
- `package.json` with `name`, `version`, `description`, `keywords`
- `SKILL.md` with the skill instructions

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- REFERENCE LINKS -->

[doc-shield]: https://img.shields.io/badge/DOC-文档-blue?style=for-the-badge
[doc-url]: #

[docs-shield]: https://img.shields.io/badge/DOCS-文档-blue?style=for-the-badge
[docs-url]: #

[github-shield]: https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github
[github-url]: #
