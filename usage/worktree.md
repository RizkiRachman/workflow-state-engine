<!-- omit from toc -->
# Worktree Usage Guide
[![Worktree Plugin][worktree-shield]][worktree-url] [![GitHub][github-shield]][github-url]

> **Plugin**: `opencode-worktree` ([github.com/arturosdg/opencode-worktree](https://github.com/arturosdg/opencode-worktree))
>

> **Purpose**: TUI for managing git worktrees and launching OpenCode in the selected worktree.

## Features

- List all worktrees with branch, path, and metadata
- Status indicators: `[main]`, `[*]` dirty, `[local]` branch

- Create new worktrees
- Create branch from worktree commit

- Post-create hooks (e.g., `npm install`)
- Open worktree in file manager or custom editor

- Unlink / delete worktrees (multi-select delete mode)
- Customizable launch command: `opencode`, `cursor`, `claude`, `code`, etc.

## Keybindings

| Key | Action |
|---|---|
| `Up`/`Down` or `j`/`k` | Navigate |
| `Enter` | Open worktree in configured tool |
| `o` | Open folder in file manager / editor |
| `d` | Enter multi-select delete mode |
| `n` | Create new worktree |
| `b` | Create branch from worktree commit |
| `c` | Edit configuration |
| `r` | Refresh list |
| `q` / `Esc` | Quit / cancel |

## Configuration

Stored at `~/.config/opencode-worktree/config.json` with per-repo overrides.

```json
{

  "default": {

    "postCreateHook": "",

    "openCommand": "",

    "launchCommand": "opencode"

  },

  "repos": {

    "github.com/user/repo": {

      "postCreateHook": "npm install",

      "launchCommand": "cursor"

    }

  }

}
```
| Option | Description | Default |
|---|---|---|
| `postCreateHook` | Command after creating a worktree | none |
| `openCommand` | Command for `o` key (open folder) | system default |
| `launchCommand` | Command for `Enter` key | `opencode` |

## Usage

```bash
# Run in current repo

opencode-worktree

# Or specify repo path

opencode-worktree /path/to/repo

[worktree-shield]: https://img.shields.io/badge/Worktree-Plugin-blue?style=for-the-badge
[worktree-url]: #
[github-shield]: https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github
[github-url]: #

```
