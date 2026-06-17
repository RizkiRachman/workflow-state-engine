<!-- omit from toc -->
## VibeGuard Plugin Usage
[![VibeGuard Plugin][vibeguard-shield]][vibeguard-url]

**What it does**: Redacts secrets, credentials, and PII from prompts before they're sent to LLM providers. Replaces sensitive values with placeholders (`__VG_API_KEY_abc123__`), then restores them after the response.

### How to Use

VibeGuard runs automatically — no manual action needed. It hooks into the message pipeline and redacts matching patterns on the fly.

### Configuration

Config file: `vibeguard.config.json` at project root.

| Field | Default | Description |
|-------|---------|-------------|
| `enabled` | `true` | Master toggle |
| `placeholder_prefix` | `__VG_` | Prefix for redaction placeholders |
| `session.ttl` | `1h` | How long mappings are remembered |
| `session.max_mappings` | `100000` | Max concurrent placeholder mappings |

### Pattern Types

- **keywords**: Exact string matches (e.g., `"my-api-key-123"`)
- **regex**: Regex patterns (e.g., OpenAI keys `sk-...`, GitHub tokens, AWS keys)
- **builtin**: Built-in detectors — `email`, `ipv4`, `ipv6`, `mac`, `uuid`, `china_phone`, `china_id`
- **exclude**: Values never to redact (e.g., `localhost`)

### Safety

- VibeGuard is a **no-op** if `vibeguard.config.json` is missing or `enabled=false`
- Placeholders are **irreversible to the provider** (HMAC-based, session-scoped)
- If a redacted value is referenced in a tool result, it's restored before the tool executes

[vibeguard-shield]: https://img.shields.io/badge/VibeGuard-Plugin-blue?style=for-the-badge
[vibeguard-url]: #
