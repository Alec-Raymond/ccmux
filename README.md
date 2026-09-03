# ccmux

A tmux session board plus a persistent notification system for running many Claude Code instances side by side, inside Ghostty on macOS. One tmux window per Claude session, each carrying a 28-column sidebar pane that shows every session at a glance: a 5-hour usage meter, one clickable row per session with an alert dot when a session needs you, an activity spinner while it generates, and a "+" row to open a new project. Each session also posts one sticky macOS alert when it finishes (Glass sound) or needs input (Ping sound), titled with the session's topic and bodied with the first clause of Claude's actual final message. Alerts auto-dismiss when you respond, when you open the session, when the session ends, and when the owning process dies.

## The board

- `bin/ccmux` - entry point. `ccmux [dir...]` creates or attaches the board session, one window per project, idempotent.
- `bin/ccnew` - fzf picker over candidate project directories (Claude Code history first, then zoxide), deduped, with already-open projects marked.
- `bin/claude-sidebar` - the sidebar renderer. Usage bar, per-session rows with alert dots and activity spinner, click handling.
- `bin/claude-usage` - real 5-hour window usage, read from the OAuth usage endpoint with the token from the login keychain. Cached and rate-limit friendly; never stores the token.
- `bin/claude-shells` - detects which sessions have a shell running underneath them, with a cached one-pass `ps` walk.
- `bin/claude-tab` / `bin/claude-move` / `bin/claude-close` - option-tab cycling between sessions, option-arrow row reordering, guarded window close.
- `bin/claude-switch`, `bin/claude-new`, `bin/claude-launcher`, `bin/claude-sidebar-toggle`, `bin/claude-dismiss`, `bin/claude-pin-sidebar`, `bin/claude-fleet` - switcher popup, launcher window plumbing, alert dismissal on open, sidebar width pinning, and the older flat board.
- `tmux.conf` - the hooks that create a sidebar in every new window, pin its width, and clear notifications when you open a session.
- `ghostty/config` - a dedicated Ghostty profile (used via `XDG_CONFIG_HOME`) so the board runs as its own app identity.

## The notifications

- `hooks/claude-notify.sh` - the main hook, wired to the Stop, Notification, UserPromptSubmit, SessionStart and SessionEnd events. Extracts the alert title and message from the session transcript (width-weighted title truncation, clause-boundary message splitting), filters out idle-prompt noise, maintains the tmux window state the sidebar reads (alert dots, busy flag, window titles), and mutes configured directories.
- `hooks/claude-notify-watch.sh` - a per-session watchdog so alerts die with the session even on SIGKILL or a crash, which run no hook at all.
- `hooks/claude-focus.sh` - runs when an alert is clicked: focuses the right tmux window and activates the terminal.
- `settings.hooks.example.json` - the hook wiring for `~/.claude/settings.json`.

Alerts are posted through a rebranded copy of terminal-notifier 2.0.0 (own bundle id, own icon) so they appear as "Claude Code" in Notification Center and can be removed by group. Make your own: copy terminal-notifier.app, change `CFBundleIdentifier`, `CFBundleName` and the icon in `Contents/Resources`, and point the `NOTIFIER` variable at it. Set the app's notification style to Alerts in System Settings so they persist.

## Requirements

tmux 3.x, fzf, zoxide (optional), Ghostty, terminal-notifier, and Claude Code.

## Install

Copy the `bin/` scripts somewhere on your PATH, install the `hooks/` scripts to `~/.claude/hooks/` and merge `settings.hooks.example.json` into `~/.claude/settings.json`, merge `tmux.conf` into `~/.tmux.conf`, and adjust paths to taste. The scripts assume macOS (`stat -f`, `security` for the keychain read).

## Notes

macOS silently suppresses all alerts while the display is mirrored or shared unless "Allow notifications when mirroring or sharing" is enabled. If alerts vanish, check that before debugging the hook.
