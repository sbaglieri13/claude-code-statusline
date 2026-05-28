# Claude Code Statusline

A status bar for Claude Code on Windows that surfaces real-time session data directly in the prompt — model, context usage, rate limits, response time, and git branch.

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

To adjust them, open `statusline.ps1` and edit the two functions marked `# set your thresholds here!`.

## Installation

### Download

```bash
git clone https://github.com/sbaglieri13/claude-code-statusline.git
```

Or download the ZIP from GitHub and extract it.

### Copy the files

Copy `statusline.ps1` and `prompt-start-hook.ps1` to your Claude config folder:

```
C:\Users\YOUR_USERNAME\.claude\
```

### Edit `settings.json`

Open `C:\Users\YOUR_USERNAME\.claude\settings.json` (create it if it doesn't exist) and add the following. If the file already has other settings, merge the keys — do not duplicate existing ones.

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -ExecutionPolicy Bypass -File \"C:\\Users\\YOUR_USERNAME\\.claude\\statusline.ps1\""
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell -ExecutionPolicy Bypass -File \"C:\\Users\\YOUR_USERNAME\\.claude\\prompt-start-hook.ps1\"",
            "shell": "powershell",
            "async": true
          }
        ]
      }
    ]
  }
}
```

> Replace every `YOUR_USERNAME` with your actual Windows username.

### Restart Claude Code

Close and reopen Claude Code. The status bar appears at the bottom of the prompt.

## Uninstall

Remove the `statusLine` and `hooks` keys from `settings.json`, then delete `statusline.ps1` and `prompt-start-hook.ps1` from `~\.claude\`.

## License

MIT — free to use, modify, and distribute.
