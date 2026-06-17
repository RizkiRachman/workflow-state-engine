# Model Fallback Plugin

**Auto failover between LLM models on API error or rate-limit.** Keeps agents running when the primary model is unavailable — the fallback chain is transparent to the agent.

---

## What It Does

When OpenCode gets an API error, rate-limit, or timeout from the primary LLM, the Model Fallback plugin automatically retries the request against the next model in the configured chain. The agent sees no interruption — the response arrives as if the primary model handled it.

## How It Works

```
Primary model → Fallback model (1st) → Fallback model (2nd) → ... → Error
```

- On API error / rate-limit / timeout: the plugin retries the **exact same request** (same messages, tools, temperature) against the next model in the chain.
- The switch is transparent: the agent does not know a fallback occurred.
- If **all models** in the chain fail, the error propagates to the agent as normal.
- Used for both chat completions and streaming requests.

## Configuration

File: `.opencode/opencode-model-fallback.jsonc`

```jsonc
{
  "models": [
    {
      "provider": "openai",
      "model": "gpt-4o",
      "apiKeyEnv": "OPENAI_API_KEY"
    },
    {
      "provider": "anthropic",
      "model": "claude-sonnet-4-20250514",
      "apiKeyEnv": "ANTHROPIC_API_KEY"
    },
    {
      "provider": "openai",
      "model": "gpt-4o-mini",
      "apiKeyEnv": "OPENAI_API_KEY"
    }
  ],
  "timeoutMs": 60000,
  "maxRetries": 2
}
```

| Field | Description |
|-------|-------------|
| `models[]` | Ordered list of models — first is primary, rest are fallbacks |
| `models[].provider` | LLM provider name (e.g. `openai`, `anthropic`, `google`) |
| `models[].model` | Model identifier string |
| `models[].apiKeyEnv` | Environment variable holding the API key |
| `timeoutMs` | Request timeout per model in milliseconds |
| `maxRetries` | Retries **per model** before moving to next fallback |

## When It Triggers

The plugin activates on any of these errors from the current model:

- **API errors** — 4xx/5xx responses (auth failure, quota exceeded, server error)
- **Rate limits** — 429 Too Many Requests, token bucket exhausted
- **Timeouts** — Request exceeds `timeoutMs` with no response
- **Connection errors** — DNS failure, dropped connection, TLS errors

It does **not** trigger on content moderation refusals, tool-call errors, or agent-level logic failures — those are passed through.

## Model Priority

Models are tried in **declared order**. The first entry in `models[]` is the primary. Subsequent entries are fallbacks tried in sequence. There is no scoring, no adaptive routing — strict failover chain only.

```
1. gpt-4o         (primary — used for most requests)
2. claude-sonnet  (first fallback — used when gpt-4o fails)
3. gpt-4o-mini    (second fallback — used when both above fail)
```

## Best Practices

1. **Always configure at least one fallback.** A single model is a single point of failure — rate limits and outages happen.
2. **Use different providers** for primary and fallback. If OpenAI is down, Anthropic is likely still up.
3. **Set `maxRetries` to 1–2.** Too many retries per model delays fallback unnecessarily.
4. **Keep `timeoutMs` reasonable.** 30–60 seconds gives the model enough time without holding up the agent indefinitely.
5. **Test failover behavior.** Temporarily set an invalid API key on the primary model and verify the fallback kicks in.

## Troubleshooting

| Symptom | Likely Cause | Check |
|---------|-------------|-------|
| Both models fail | All API keys are invalid or expired | Verify `apiKeyEnv` values |
| Fallback never triggers | Timeout too long or `maxRetries` too high | Reduce `timeoutMs` or `maxRetries` |
| Slow fallback | Primary model keeps timing out before fallback | Lower `timeoutMs` |
| Fallback not configured | Only one model in `models[]` | Add at least one fallback entry |
| Config not found | File missing or at wrong path | Confirm `.opencode/opencode-model-fallback.jsonc` exists |

## See Also

- Model Fallback plugin README in `~/.config/opencode/plugins/model-fallback/`
- OpenCode provider configuration in `opencode.json`
