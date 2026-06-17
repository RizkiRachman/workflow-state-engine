# Notify Plugin — In-App Notifications

**Plugin**: `opencode-notify`  
**Status**: Auto-configured on install — no project-level config file needed.

## What It Does

Shows native OS notifications (popups with actionable buttons) for OpenCode events. When an agent needs permission or has a question, you get a popup you can respond to directly — no need to switch back to the terminal. Also fires on long-running task completion and subagent input requests.

## How Notifications Fire

| Trigger | Behavior | Action Buttons |
|---------|----------|----------------|
| Agent requests permission (shell, file edit, network) | Native OS notification with "Allow / Deny / Allow Always" | Yes — respond from popup |
| Long-running task completes (>30s) | Notification: "Task X completed" | Opens results |
| Subagent needs your input | Notification with question text | Yes — respond from popup |
| Build/test failure | Notification with exit code summary | Opens terminal output |

## Without Notify Plugin

If the plugin is not installed, OpenCode falls back to in-terminal prompts — you see agent permission requests inline and need to switch back to the terminal to approve. Long tasks show a spinner in the status bar but no popup.

## Platform Support

| Platform | Notifications | Notes |
|----------|:-------------|-------|
| macOS | ✅ Native (Notification Center) | Uses `terminal-notifier` if available, else script |
| Windows | ✅ Toast notifications | Requires Windows 10+ Action Center |
| Linux | ✅ D-Bus notifications | Requires `libnotify` / `notify-send` |
| SSH/Headless | ⚠️ Terminal fallback | No OS notifications; uses terminal bell |

## Troubleshooting

- **Notifications not showing on macOS**: Ensure Notification Center is enabled for your terminal app. Run `osascript -e 'display notification "test" with title "Notify"'` to verify.
- **Notifications not showing on Linux**: Install `libnotify-bin` (`apt install libnotify-bin`). Verify with `notify-send "test"`.
- **No notification on task completion**: Task must run >30s to trigger. Shorter tasks complete synchronously without notification.
- **Stale notifications**: Dismiss before switching contexts — the plugin queues one notification per event and drops duplicates to reduce noise.

## Configuration (Advanced)

Notifications are auto-configured. If you want to suppress specific categories:
```jsonc
// ~/.config/opencode/opencode.json
{
  "plugins": {
    "opencode-notify": {
      "enabled": true,
      "suppress": ["permission", "task_complete"]
    }
  }
}
```

Suppression keys: `permission`, `task_complete`, `subagent_input`, `build_failure`.
