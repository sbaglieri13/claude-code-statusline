# Claude Code Statusline

A cross-platform status bar for Claude Code that surfaces real-time session data directly in the prompt — model, context usage, rate limits, response time, and git branch.

Works on **Linux**, **macOS**, and **Windows** (via Git Bash or WSL).

![Preview](screenshots/demo.png)

## What it shows

| Element | Description |
|---------|-------------|
| 🤖 Model | Active Claude model (e.g. Sonnet 4.6, Opus 4.7) |
| 📁 Folder | Current working directory |
| 🌿 Branch | Git branch — green if clean, yellow if uncommitted changes |
| ⚡ Time | True end-to-end response time: from pressing Enter to response complete |
| 🧠 Context bar | Visual progress of context window consumption with exact token count |
| 🔋 Rate limits | % of the Daily and Weekly quota consumed |
| ⏳ Reset | Exact local time when each quota window resets (e.g. `7:00 PM` or `May 29, 10:00 AM`) |

### Color thresholds

The context bar and rate limit percentages change color to give you an at-a-glance warning level:

| | Green | Yellow | Red |
|-|-------|--------|-----|
| 🧠 Context | < 60% | 60–79% | ≥ 80% |
| 🔋 Rate limits | < 70% | 70–94% | ≥ 95% |
| 🌿 Branch | clean | uncommitted changes | — |

To adjust them, open `statusline.sh` and edit the two functions marked `# set your thresholds here`.

## Prerequisites

The installer needs these tools available in your shell:

| Tool | Why |
|------|-----|
| `bash` | Runs the installer and the statusline script |
| `jq`   | Smart-merges your `settings.json` and parses Claude's session data |
| `git`  | Reads the current branch + dirty state |

### Installing the prerequisites

| OS | Install command |
|----|-----------------|
| **Debian / Ubuntu** | `sudo apt install bash jq git` |
| **Fedora / RHEL**   | `sudo dnf install bash jq git` |
| **Arch**            | `sudo pacman -S bash jq git` |
| **macOS**           | `brew install jq git` (bash ships with the OS) |
| **Windows**         | Install [Git for Windows](https://git-scm.com/download/win) (includes `bash` + `git`), then install `jq` (see below). Alternatively use [WSL](https://learn.microsoft.com/windows/wsl/install) and follow the Linux instructions inside it. |

> On Windows the statusline is run by Claude Code through `bash` — so Git for Windows (or WSL) must be installed and `bash` must be reachable from your PATH.

#### Installing jq on Windows (Git Bash, no admin required)

```bash
curl -L -o /usr/local/bin/jq https://github.com/jqlang/jq/releases/latest/download/jq-windows-amd64.exe
chmod +x /usr/local/bin/jq
jq --version
```

Or via package managers if available:

```powershell
winget install jqlang.jq   # Windows 11 built-in
choco install jq           # Chocolatey
scoop install jq           # Scoop
```

## Installation

### 1. Clone the repo

```bash
git clone https://github.com/sbaglieri13/claude-code-statusline.git
cd claude-code-statusline
```

### 2. Run the installer

```bash
bash install.sh
```

The installer:

- Detects your OS (Linux / macOS / Windows-GitBash / WSL).
- Copies `statusline.sh` and `prompt-start-hook.sh` into `~/.claude/` and makes them executable.
- **Smart-merges** `~/.claude/settings.json`:
  - Backs up the existing file as `settings.json.bak.<timestamp>` before touching anything.
  - Adds the `statusLine` key only if you don't already have one (or replaces it only if it was previously installed by this script).
  - Appends a single entry to `hooks.UserPromptSubmit` without removing or modifying any other hooks you've configured.
  - Marks every entry it adds with `"_managed": "claude-code-statusline"` so `--uninstall` can remove exactly those entries later.

### 3. Restart Claude Code

The status bar appears at the bottom of the prompt.

### Useful flags

```bash
bash install.sh --dry-run     # Preview every change without writing anything.
bash install.sh --uninstall   # Cleanly remove only the entries this script added.
bash install.sh --help        # Show usage.
```

## Uninstall

```bash
bash install.sh --uninstall
```

This:

- Removes the `statusLine` key only if it's the one this script installed.
- Removes only the `hooks.UserPromptSubmit` entries marked as managed by this script (your other hooks stay intact).
- Prunes empty `hooks.UserPromptSubmit` / `hooks` containers.
- Deletes `~/.claude/statusline.sh` and `~/.claude/prompt-start-hook.sh`.
- Leaves any `settings.json.bak.*` backups in place — delete them yourself once you're sure you don't need them.

## How it works

- `statusline.sh` reads a JSON payload on stdin from Claude Code each time the status line refreshes, then prints two ANSI-coloured lines.
- `prompt-start-hook.sh` runs on every `UserPromptSubmit` and writes a millisecond timestamp to `$TMPDIR/claude-prompt-start.txt`; the statusline reads it back to compute the ⚡ response time.
- Rate-limit data is cached in `$TMPDIR/claude-rl-cache.json` so the 🔋 / ⏳ values stay visible across refreshes that don't include fresh limits.

## License

MIT — free to use, modify, and distribute.
