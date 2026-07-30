#!/bin/bash
# claude-focus — jump to the session that raised an alert.
#
#   claude-focus <tmux-socket> <window-id> [terminal-app]
#
# terminal-notifier runs this through -execute when the notification is clicked.
# It selects that Claude session's tmux window, points every attached client at
# the right tmux session, and brings the terminal app to the front. The window is
# addressed by tmux window id (@3), not index, because indices shift whenever a
# window closes and renumber-windows is on.
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
sock=${1:-}
win=${2:-}
app=${3:-Ghostty}
[[ -n "$sock" && -n "$win" ]] || exit 0

tm() { tmux -S "$sock" "$@" 2>/dev/null; }

# Gone already: the board was closed, or that window was. Nothing to jump to.
tm has-session || exit 0
sess=$(tm display-message -p -t "$win" '#{session_name}') || exit 0
[[ -n "$sess" ]] || exit 0

tm select-window -t "$win" || exit 0
# Land in the Claude pane, not the sidebar.
pane=$(tm list-panes -t "$win" -F '#{pane_id} #{@claude_sidebar}' \
  | awk '$2 != "1" { print $1; exit }')
[[ -n "$pane" ]] && tm select-pane -t "$pane"

# Any client looking at a different session gets pointed at this one, so the
# board is already showing the right window when the terminal comes forward.
while IFS= read -r client; do
  [[ -n "$client" ]] || continue
  on=$(tm display-message -p -t "$client" '#{session_name}')
  [[ "$on" == "$sess" ]] || tm switch-client -c "$client" -t "$sess"
done < <(tm list-clients -F '#{client_name}')

# The board normally runs in /Applications/ccmux.app (a rebranded Ghostty), but
# it may also be a plain Ghostty window. Activate whichever is actually running;
# never name an app that is not, because "activate" would launch it and open an
# unwanted second board window.
if [[ -n "${3:-}" ]]; then
  /usr/bin/osascript -e "tell application \"$app\" to activate" >/dev/null 2>&1
elif /usr/bin/pgrep -f '/Applications/ccmux\.app/Contents/MacOS' >/dev/null 2>&1; then
  /usr/bin/osascript -e 'tell application "ccmux" to activate' >/dev/null 2>&1
elif /usr/bin/pgrep -f '/Applications/Ghostty\.app/Contents/MacOS' >/dev/null 2>&1; then
  /usr/bin/osascript -e 'tell application "Ghostty" to activate' >/dev/null 2>&1
fi
exit 0
