# ccmux

ccmux is a macOS terminal session multiplexer and notification layer for coding agents.
It keeps independent agent sessions and shells in one tmux board.
The sidebar shows which session is working, finished, or waiting for input.
When a session needs attention, a macOS notification returns you to its exact tmux window.

ccmux works at the terminal process and lifecycle-event layer.
It does not inspect prompts or depend on a specific model.
Each client keeps its own authentication, configuration, context, and network connection.

Current adapters support Claude Code and Codex.
Ordinary terminal sessions are also first-class entries on the board.
The included Ghostty profile is an optional front end, not part of the core design.

The two core parts are:

- **Session multiplexer:** start, view, switch, reorder, and close many terminal sessions.
- **Notification system:** track agent state and route each alert back to its owning session.

## How it works

ccmux creates one tmux window for each agent or shell.
A persistent launcher opens new sessions without ending the board.
tmux keeps sessions alive when the terminal detaches.

You can open the same directory more than once.
Each entry remains an independent process with separate conversation state.

## Start sessions

Open the launcher:

```sh
ccmux
```

Start sessions in specific directories:

```sh
ccmux ~/Projects/api ~/Projects/web
ccmux --codex ~/Projects/api
ccmux --terminal ~/Projects/api
```

Claude Code is the default client.
The launcher can also choose the client and working directory interactively.

## Sidebar

The 28-column sidebar shows:

- Account usage and reset time for the selected client.
- One two-line row per agent or shell.
- A white border around the selected row.
- An amber dot when a session needs input.
- A blue dot when a turn finishes.
- A rotating line while a session works.
- A shell mark when an agent owns an open shell.
- A `+` row for starting another session.

Opening a session clears its dot and macOS alert.
The dot means “new since last viewed,” not “still unresolved.”

### Controls

| Control | Action |
| --- | --- |
| Click a row | Select the session |
| Click `x` | Close the session |
| Click `+` | Open the launcher |
| `Option-Tab` / `Option-Shift-Tab` | Select the next or previous session |
| `Option-Up` / `Option-Down` | Reorder the selected session |
| `Option-N` / `Option-W` | Open or close a session |
| `Ctrl-b Tab` | Open the session manager |
| `Ctrl-b b` | Hide or show the sidebar |
| `Ctrl-b d` | Detach from tmux |

## Notifications

Lifecycle hooks turn client events into sidebar state and macOS alerts.

- A finished turn creates a blue dot and Glass alert.
- When a client reports that it needs input, ccmux creates an amber dot and Ping alert.
- Automatic permission review stays quiet while the session remains busy.
- Clicking an alert selects its exact tmux window and main pane.
- Opening, answering, closing, or ending a session removes its alert.
- A watchdog removes alerts left by a crash or killed process.

Alert titles use the session topic.
Alert messages use a short excerpt from the client's last response.
A newer alert replaces the older alert from the same session.

Alerts use a dedicated `ccmux Notifier.app` identity.
Set its macOS notification style to **Alerts** so notifications remain visible.

## Usage meter

The meter follows the client in the selected window.
It reports account usage, not usage for one ccmux session.

The Claude adapter reads the account usage endpoint.
The Codex adapter reads local rate-limit snapshots.
Both retain the highest value seen until the active limit window resets.

## Key files

| Path | Purpose |
| --- | --- |
| `bin/ccmux` | Starts or attaches to the tmux board |
| `bin/ccnew` | Chooses the client and directory |
| `bin/claude-sidebar` | Draws the board and handles clicks |
| `hooks/*-notify.sh` | Maps lifecycle events to state and alerts |
| `hooks/*-notify-watch.sh` | Removes alerts after a process exits |
| `hooks/claude-focus.sh` | Returns an alert click to its session |
| `tmux.conf` | Creates sidebars and defines controls |

## Requirements

- macOS and a terminal
- tmux 3.x
- Claude Code or Codex CLI
- fzf and jq
- Python 3 with fontTools
- Spotlight
- Zoxide, optionally

## Setup

This repository reflects a personal installation, not a portable installer.
Some files contain paths for `/Users/alecraymond` and need edits for another account.

1. Copy `bin/` scripts to a directory on `PATH`.
2. Copy each notification adapter to its client's hooks directory.
3. Merge the example hook configuration for each installed client.
4. Merge `tmux.conf` into `~/.tmux.conf`.
5. Run `python3 tools/build-icon-font.py` for the aligned sidebar marks.
6. Install or repoint the notifier bundle used by the hook scripts.

The current focus helper recognizes the ccmux and Ghostty application names.
Change `hooks/claude-focus.sh` if notification clicks must activate another terminal.

macOS can suppress alerts while the display is mirrored or shared.
Enable **Allow notifications when mirroring or sharing** when needed.
