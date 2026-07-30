#!/bin/bash
# Watchdog that clears one Claude Code session's alert when the session dies.
#
#   $1  pid of the claude process that owns the session
#   $2  notification group id (claude-<session_id>)
#   $3  path to this session's watcher state file
#
# Claude Code runs its SessionEnd hook only on a graceful exit (/quit, Ctrl-D,
# /clear). Closing a terminal window or a tmux pane sends SIGHUP, and the
# signal handler calls process.exit(), which does not await the async hook. A
# SIGKILL or a crash skips it too. In all of those cases the sticky alert would
# outlive the session. This process is started with nohup, so it survives the
# hangup, waits for the claude process to disappear, then removes the alert.
NOTIFIER="/Users/alecraymond/.claude/hooks/Claude Code.app/Contents/MacOS/terminal-notifier"

pid=$1
group=$2
state=$3
[[ -n "$pid" && -n "$group" ]] || exit 0

# Record the process start time. Comparing it each poll means a recycled pid
# reads as "gone" instead of keeping the watcher alive against a stranger.
start=$(/bin/ps -o lstart= -p "$pid" 2>/dev/null)
[[ -n "$start" ]] || exit 0

while :; do
  now=$(/bin/ps -o lstart= -p "$pid" 2>/dev/null)
  [[ -z "$now" || "$now" != "$start" ]] && break
  /bin/sleep 3
done

"$NOTIFIER" -remove "$group" >/dev/null 2>&1
[[ -n "$state" ]] && /bin/rm -f "$state"
exit 0
