# ccmux

ccmux is a macOS AI session multiplexer and notification layer for Claude Code and Codex.
It keeps many independent AI sessions visible in one Ghostty window.
It also tells you which session is working, finished, or waiting for you.

Each AI instance runs as a normal CLI process in its own tmux window.
ccmux does not proxy prompts, route model traffic, or combine agent context.
It multiplexes sessions and attention instead: start them, switch among them, and return when an alert needs you.

The two core parts are:

- **AI multiplexer:** one persistent board for Claude Code, Codex, and ordinary shells.
- **Notification system:** session-aware macOS alerts that return to the exact tmux window that raised them.

## A session in practice

1. Open ccmux.
2. Choose Claude Code, Codex, or Terminal.
3. Choose a working directory.
4. Start work in the new tmux window.
5. Switch to another session while the first agent runs.
6. Watch the sidebar or wait for a macOS alert.
7. Click the alert to return to the exact session.

You can open the same directory more than once.
Each choice creates a separate process with separate conversation state.
Closing the final work session returns to the launcher instead of ending the board.

## The AI multiplexer

ccmux uses one shared tmux session named `claude`.
The first tmux window is a persistent launcher.
Each later window owns one Claude Code process, Codex process, or login shell.

Every work window contains two panes:

- A fixed 28-column sidebar on the left.
- The selected AI client or shell on the right.

tmux keeps the processes alive when you detach or close the terminal window.
The launcher stays alive so the board has a stable home between work sessions.
If an agent process exits, ccmux closes the work window after only its sidebar remains.
ccmux never auto-closes the launcher.

ccmux starts each instance with these commands:

| Instance | Command |
| --- | --- |
| Claude Code | `claude --permission-mode auto` |
| Codex | `codex --search --approve-for-me` |
| Terminal | `$SHELL -l` |

These are standard CLI clients.
They keep their normal configuration, plugins, skills, tools, and local session data.

### Starting ccmux

Run ccmux with no arguments to open the launcher:

```sh
ccmux
```

Pass directories to create Claude Code instances immediately:

```sh
ccmux ~/Projects/api ~/Projects/web
```

Choose another instance type before the directories:

```sh
ccmux --codex ~/Projects/api
ccmux --terminal ~/Projects/api
```

The directory picker has two stages.
The first stage chooses the instance type.
The second stage chooses a directory.

The picker combines:

- Recent directories from the selected AI client's history.
- Zoxide results when Zoxide is installed.
- A cached Spotlight index of useful directories under the home directory.
- Any valid path that you type directly.

A marker shows that a directory already has an open instance.
Selecting that directory still creates a new instance.

## The board

The sidebar is the shared view of all open instances.
The same sidebar appears in every tmux window because tmux panes belong to one window.

```text
┌──── ccmux sidebar ───────┬────────────────────────────────────┐
│ ███████░░░  68%          │                                    │
│ resets 4:10p · in 2h 18m │        selected AI or shell        │
├──────────────────────────┤                                    │
│ • Fix usage reset      x │                                    │
│ ✳ ccmux              /   │                                    │
├──────────────────────────┤                                    │
│   Review query plan    x │                                    │
│ › search-service      $  │                                    │
├──────────────────────────┤                                    │
│                        x │                                    │
│   scratch             $  │                                    │
├──────────────────────────┤                                    │
│            +             │                                    │
└──────────────────────────┴────────────────────────────────────┘
```

Each instance occupies a two-line row.
The top line contains the session topic and close target.
The bottom line contains the provider mark, directory, and activity mark.

| Mark | Meaning |
| --- | --- |
| `✳` | Claude Code instance |
| `›` | Codex instance |
| no left mark and `$` on the right | Ordinary terminal |
| white row border | Selected instance |
| amber dot | Claude needs input |
| blue dot | The agent finished a turn |
| rotating line | The selected process is generating |
| `$` | The instance owns an open shell |
| `x` | Close target |
| `+` | Open the new-instance picker |

The notification dot means “new since last viewed.”
It does not mean that a task remains unresolved.
Opening the window clears the dot and its matching macOS alert.

The activity spinner cycles through `|`, `/`, `─`, and `\` while an agent works.
The shell mark appears when an agent leaves an active shell below the AI process.
The spinner takes priority when both states apply.

AI rows use the generated session topic as their title.
They fall back to the directory name when no topic exists.
Duplicate directory names gain a number from the second instance onward.
Ordinary terminal rows omit the topic and provider mark.

### Controls

| Control | Action |
| --- | --- |
| Click either line of a row | Select that instance |
| Click `x` | Close that instance |
| Click `+` | Open the new-instance picker |
| `Option-Tab` | Select the next instance |
| `Option-Shift-Tab` | Select the previous instance |
| `Option-Up` / `Option-Down` | Move the selected row |
| `Option-N` | Open the new-instance picker |
| `Option-W` | Close the selected instance |
| `Ctrl-b Tab` | Open the window manager popup |
| `Ctrl-b b` | Hide or show the sidebar |
| `Ctrl-b C` | Open the new-instance picker |
| `Ctrl-b X` | Confirm and close the selected instance |
| `Ctrl-b d` | Detach from ccmux |
| `Ctrl-b` then a number | Jump to that tmux window |

`Option-Tab` delays the switch until rapid key taps stop.
This lets you scan several rows before ccmux redraws the selected window.

The window manager popup shows full paths and current alert states.
Press a window number to select it.
Press `x` and a number to close it.
Press `n` to create another instance.

## Notifications

ccmux turns AI lifecycle events into sidebar state and macOS alerts.
The notification hooks know the tmux socket, stable window ID, process, and working directory.
That data lets an alert return to the session that created it.

| Provider event | Sidebar state | macOS result |
| --- | --- | --- |
| Claude finishes a turn | Blue dot | Alert with Glass sound |
| Claude asks a question | Amber dot | Alert with Ping sound |
| Codex finishes a turn | Blue dot | Alert with Glass sound |
| Automatic permission review | Busy state remains | No alert or dot |
| You submit another prompt | Alert state clears | Existing alert closes |
| You open the window | Dot clears | Existing alert closes |
| The session ends | State clears | Existing alert closes |

Codex currently has no separate amber “needs input” path.
Its automatic permission events stay quiet because `--approve-for-me` handles them.
Claude permission-review events also stay quiet while its automatic reviewer decides.

Each alert uses the session topic as its title.
The message comes from the first clause of the agent's last real response.
ccmux truncates the message to 140 characters.
Codex messages start with `›` so they remain distinct without changing the title.

Alerts use a dedicated `ccmux Notifier.app` bundle.
The separate bundle identifier gives ccmux its own icon and notification settings.
Set its macOS notification style to **Alerts** so notifications remain visible.

### Alert routing and cleanup

ccmux groups alerts by session.
A newer alert replaces the older alert from the same session.

Clicking an alert runs `claude-focus.sh`.
The script selects the stored tmux window ID and its main pane.
It then brings the ccmux app or Ghostty to the foreground.

Opening a window runs `claude-dismiss`.
That removes the macOS alert and marks the row as viewed.

A watchdog follows each process that owns an alert.
The watchdog removes the alert after a normal exit, crash, `SIGKILL`, or closed pane.
New alerts also sweep stale notification groups left after a reboot.

Claude notifications are muted for working directories below `/openclaw`.
This rule prevents background automation from filling Notification Center.

### Notification data flow

```text
Claude or Codex lifecycle event
              │
              ▼
       provider notify hook
          │             │
          │             └──────────────► ccmux Notifier.app
          ▼                                      │
   tmux window options                           │ click
          │                                      ▼
          └──────────► every sidebar      exact tmux window
```

The hooks store only small state values in tmux window options.
The sidebar reads those values during each redraw.
No ccmux service sits between the AI client and its provider.

## Usage meter

The top of the sidebar shows account usage for the provider in the selected window.
Claude windows show Claude usage.
Codex windows show Codex usage.
Terminal windows deliberately show Claude usage.

The meter is green below 75 percent.
It turns amber at 75 percent and red at 90 percent.

| Provider | Source | Refresh behavior |
| --- | --- | --- |
| Claude | Anthropic OAuth usage endpoint | Caches valid data for 180 seconds |
| Codex | Newest rate-limit snapshot in local Codex session logs | Caches data for 10 seconds |

The Claude reader gets the OAuth token from the macOS login Keychain at request time.
It does not store the token in the cache.
It can show the last good value for up to two hours during endpoint failures.

The Codex reader does not make another network request.
It selects the shortest populated active window from Codex's local rate-limit snapshots.
Some plans expose only a seven-day window.

Both readers keep a high-water value within one reset window.
An older or out-of-order sample cannot make the displayed bar fall.
A later reset timestamp starts a new window and permits a lower value.

The meter reports account usage.
It does not measure usage by ccmux instance.

## Repository map

| Path | Responsibility |
| --- | --- |
| `bin/ccmux` | Creates or attaches to the board and starts requested instances |
| `bin/ccnew` | Runs the instance-type and directory picker |
| `bin/claude-launcher` | Keeps the first tmux window alive and hosts the picker |
| `bin/claude-sidebar` | Draws rows, usage, activity, alerts, and mouse targets |
| `bin/claude-switch` | Implements the window manager popup |
| `bin/claude-usage` | Reads and caches Claude account usage |
| `bin/codex-usage` | Reads and caches Codex account usage |
| `bin/claude-dismiss` | Clears the alert for the selected window |
| `hooks/claude-notify.sh` | Maps Claude lifecycle events to alerts and tmux state |
| `hooks/codex-notify.sh` | Maps Codex lifecycle events to alerts and tmux state |
| `hooks/*-notify-watch.sh` | Removes alerts when their owning process disappears |
| `hooks/claude-focus.sh` | Routes an alert click to its exact tmux window |
| `tmux.conf` | Creates sidebars and binds board controls |
| `ghostty/config` | Defines the dedicated ccmux Ghostty profile |
| `settings.hooks.example.json` | Shows the Claude hook registrations |
| `codex.hooks.example.json` | Shows the Codex hook registrations |
| `tools/build-icon-font.py` | Builds the aligned local provider-glyph font |

## Requirements

- macOS
- Ghostty
- tmux 3.x
- Claude Code
- Codex CLI
- fzf
- jq
- Spotlight and `mdfind`
- Python 3
- fontTools
- Zoxide, optionally

The scripts also use macOS commands such as `security` and `stat -f`.

## Installation status

This repository describes the source layout for a personal installation.
It is not a portable or one-command installer yet.
Several scripts contain paths for `/Users/alecraymond` and need edits for another account.

The repository also assumes two prebuilt application bundles:

- `/Applications/ccmux.app`, a Ghostty bundle with the ccmux identity and icon.
- `~/Applications/ccmux Notifier.app`, a `terminal-notifier` 2.0.0 bundle with the ccmux identity and icon.

The repository does not contain a build recipe for those bundles.
You can run `ccmux` from a normal Ghostty window without the first bundle.
macOS alerts require the notifier bundle or corresponding hook changes.

To reproduce the current command and hook layout:

1. Copy the scripts under `bin/` to a directory on `PATH`, such as `~/.local/bin/`.
2. Copy `claude-notify.sh`, `claude-notify-watch.sh`, and `claude-focus.sh` to `~/.claude/hooks/`.
3. Copy `codex-notify.sh` and `codex-notify-watch.sh` to `~/.codex/hooks/`.
4. Copy `claude-focus.sh` to `~/.local/bin/` for the Codex click handler.
5. Merge `settings.hooks.example.json` into `~/.claude/settings.json`.
6. Merge `codex.hooks.example.json` into `~/.codex/hooks.json`.
7. Merge `tmux.conf` into `~/.tmux.conf`.
8. Install `ghostty/config` at `~/.config/ccmux/ghostty/config` for the dedicated Ghostty profile.
9. Run `python3 tools/build-icon-font.py` to install the aligned provider-glyph font.
10. Set the ccmux notifier's macOS notification style to **Alerts**.

Codex asks you to review changed lifecycle hooks the first time it loads them.
The dedicated Ghostty profile maps the left Option key to Alt for the board shortcuts.

## Caveats

macOS can suppress notifications while the display is mirrored or shared.
Enable **Allow notifications when mirroring or sharing** if alerts disappear during screen sharing.

Codex live web search works because ccmux starts Codex with `--search`.
The in-app Browser panel did not attach in the tested standalone Ghostty session.
Browser-panel control remains a desktop-hosted feature in this setup.
