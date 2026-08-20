#!/bin/bash
# Claude Code notification hook. Reads the hook's JSON payload on stdin.
#   Stop / Notification  -> post a persistent alert (project in bold title,
#                           task as subtitle, outcome/request as message)
#   UserPromptSubmit     -> dismiss this session's alert (user responded)
#   SessionEnd           -> dismiss this session's alert (session is over)
# Posts via a rebranded terminal-notifier bundle so alerts show the Claude
# icon and "Claude Code" as the app name. -remove and -group only work
# within the same bundle, so every call must go through this binary.
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
NOTIFIER="/Users/alecraymond/.claude/hooks/Claude Code.app/Contents/MacOS/terminal-notifier"
WATCHER="/Users/alecraymond/.claude/hooks/claude-notify-watch.sh"
# Runs when the alert is clicked: jumps the tmux board to this session's window.
FOCUS="/Users/alecraymond/.claude/hooks/claude-focus.sh"
STATE_DIR="/Users/alecraymond/.claude/hooks/state"

input=$(cat)
get() { printf %s "$input" | jq -r "$1"; }

event=$(get '.hook_event_name // ""')
sid=$(get '.session_id // "na"')
group="claude-$sid"
# Why this session stopped for you: "permission_prompt", "agent_needs_input",
# "idle_prompt", ... Only a Notification event carries it.
ntype=$(get '.notification_type // ""')

cwd=$(get '.cwd // ""')
tp=$(get '.transcript_path // ""')
dir=${cwd##*/}

# Muted working directories — automated/background agents whose turns aren't
# worth interrupting for. Match is on the cwd path; add one glob per line.
#
# The whole ~/.openclaw tree is muted, not one workspace at a time. This listed
# workspace-scout alone until 2026-08-03, when a second agent workspace
# (~/.openclaw/workspace) started posting the same "HEARTBEAT_OK" alerts and slid
# straight past the list. Every openclaw agent is cron-driven, and no interactive
# session runs in there, so the tree is the right unit. A new workspace is now
# silent from its first run.
#
# In a [[ ]] pattern "*" also matches "/", so one entry covers every depth below
# .openclaw (verified). The bare path is separate because "$HOME/.openclaw/*"
# does not match "$HOME/.openclaw" itself.
MUTED=(
  "$HOME/.openclaw"
  "$HOME/.openclaw/*"
)
for m in "${MUTED[@]}"; do
  # $m unquoted: right side of == is a glob pattern, not a literal.
  [[ "$cwd" == $m ]] && exit 0
done

# The session's auto-generated topic (same text as the terminal tab title). Read
# before any early exit, so resuming a session or sending a message refreshes the
# sidebar's row label too — not only the end of a turn. A session has no topic
# until Claude Code assigns one, so this is empty early on and the sidebar falls
# back to the folder name until it appears.
# Grep first: ai-title lines can sit anywhere in a large transcript.
topic=""
if [[ -f "$tp" ]]; then
  topic=$(grep '"type":"ai-title"' "$tp" 2>/dev/null | tail -1 \
    | jq -r '.aiTitle // ""' 2>/dev/null)
fi

# Flag this session's tmux window so the sidebar and status bar show the same
# state as the notification. $TMUX_PANE is inherited from the shell that started
# Claude, so it identifies the window with no lookup. States are read by
# ~/.local/bin/claude-sidebar and by window-status-format in ~/.tmux.conf.
#   tmux_state needs-input   blocked on the user (Ping)
#   tmux_state done          turn finished (Glass)
#   tmux_state ""            nothing pending (user replied)
tmux_state() {
  [[ -n "$TMUX" && -n "$TMUX_PANE" ]] || return 0
  if [[ -z "$1" ]]; then
    # Sending a message clears the alert for good, so drop the sidebar's
    # seen/left stamps too. Otherwise the next alert would inherit them and its
    # dot would never show.
    tmux set-option -w -t "$TMUX_PANE" -u @claude_state 2>/dev/null
    tmux set-option -w -t "$TMUX_PANE" -u @claude_seen 2>/dev/null
    tmux set-option -w -t "$TMUX_PANE" -u @claude_left 2>/dev/null
  else
    tmux set-option -w -t "$TMUX_PANE" @claude_state "$1" 2>/dev/null
  fi
  # Publish the session topic — the same text this script puts in the alert
  # title — so the sidebar can label the row with it instead of the folder name.
  # $topic is filled in from the transcript further down, so it is empty on the
  # UserPromptSubmit path and on a session that has not been given a topic yet.
  # Only ever overwrite with something, so a title survives once it appears.
  [[ -n "${topic:-}" ]] \
    && tmux set-option -w -t "$TMUX_PANE" @claude_title "$topic" 2>/dev/null
  # Publish the session id too. An alert's group is claude-<session_id>, and the
  # window option is the only way the board can work out which group belongs to
  # the window you just opened. ~/.local/bin/claude-dismiss reads it from the
  # after-select-window hook and removes that alert. Written on every event,
  # SessionStart included, so a window carries it before it can raise an alert.
  tmux set-option -w -t "$TMUX_PANE" @claude_sid "$sid" 2>/dev/null
  # automatic-rename is off, so name the window here. "alecraymond" is the home
  # directory's basename and reads as noise, same as in the alert title.
  wname=${dir:-claude}
  [[ "$cwd" == "$HOME" ]] && wname=home
  tmux rename-window -t "$TMUX_PANE" "$wname" 2>/dev/null
  tmux refresh-client -S 2>/dev/null
}

# @claude_busy drives the sidebar's spinner: set while this session is generating
# a turn, unset otherwise. The value is the epoch it was set, so the sidebar can
# ignore a flag left behind by a session that died without running Stop.
#
# Set on UserPromptSubmit, cleared on Stop, Notification, SessionEnd and
# SessionStart. Notification counts as "not generating" because it means Claude
# has stopped to ask you something. That leaves one gap: approving a permission
# prompt mid-turn fires no hook, so the spinner stays off for the rest of that
# turn. Instances run with --permission-mode auto, which makes prompts rare, and
# the flag corrects itself at the next Stop. Closing the gap would need
# PreToolUse/PostToolUse hooks firing on every single tool call in every session,
# which costs more than the spinner is worth.
tmux_busy() {       # tmux_busy 1|0
  [[ -n "$TMUX" && -n "$TMUX_PANE" ]] || return 0
  if [[ "$1" == "1" ]]; then
    tmux set-option -w -t "$TMUX_PANE" @claude_busy "$(date +%s)" 2>/dev/null
  else
    tmux set-option -w -t "$TMUX_PANE" -u @claude_busy 2>/dev/null
  fi
}

case "$event" in
  UserPromptSubmit)                        tmux_busy 1 ;;
  Stop|Notification|SessionEnd|SessionStart) tmux_busy 0 ;;
esac

# Walk up the process tree to the claude process that owns this session. The
# hook runs as a child of it, so the answer is one or two levels up; the loop
# is bounded in case a wrapper shell is added later.
claude_pid() {
  local p=$PPID d=0 line ppid comm
  while [[ -n "$p" && "$p" -gt 1 && $d -lt 10 ]]; do
    line=$(/bin/ps -o ppid=,comm= -p "$p" 2>/dev/null | awk '{print $1, $2}')
    [[ -z "$line" ]] && return 1
    ppid=${line%% *}
    comm=${line#* }
    [[ "${comm##*/}" == "claude" ]] && { printf %s "$p"; return 0; }
    p=$ppid
    d=$((d + 1))
  done
  return 1
}

# SessionStart fires on a fresh start and on every resume. There is nothing to
# notify about, but it is the moment the window needs its name and row label:
# a resumed session already has a topic, and without this the sidebar would show
# the folder name until the first turn finished.
if [[ "$event" == "SessionStart" ]]; then
  tmux_state ""
  exit 0
fi

# Claude Code raises its own Notification once the prompt sits untouched for
# `messageIdleNotifThresholdMs` (default 60000), with notification_type
# "idle_prompt" and the fixed text "Claude is waiting for your input". Nothing
# new has happened by then. The Stop alert for that same turn went out a minute
# earlier, so this only re-posted an alert you had already read and dismissed,
# and flipped the sidebar dot from done to needs-input for a session nobody is
# blocked on. Drop it. Real requests for input still post: permission_prompt,
# agent_needs_input, elicitation_*.
if [[ "$event" == "Notification" && "$ntype" == "idle_prompt" ]]; then
  exit 0
fi

# UserPromptSubmit: the user answered, so the alert has served its purpose.
# SessionEnd: the session is over, so nothing is left to go back to.
if [[ "$event" == "UserPromptSubmit" || "$event" == "SessionEnd" ]]; then
  tmux_state ""
  if [[ "$event" == "SessionEnd" ]]; then
    # The watchdog exists only to catch exits this hook misses. This is not one
    # of them, so retire it rather than leave it polling a dying pid. Field 1
    # of the state file is the watcher pid, field 2 is the claude pid.
    wpid=$(cut -d' ' -f1 "$STATE_DIR/$sid.watch" 2>/dev/null)
    [[ -n "$wpid" ]] && /bin/kill "$wpid" 2>/dev/null
    /bin/rm -f "$STATE_DIR/$sid.watch"
  fi
  exec "$NOTIFIER" -remove "$group"
fi

# The final assistant message may not be flushed to the transcript yet when
# Stop fires; give the writer a moment before reading.
[[ "$event" == "Stop" ]] && sleep 0.7

outcome=""
if [[ -f "$tp" ]]; then
  # $topic is already read further up, before the early exits, so every event can
  # refresh the label. Re-read it here because Stop waited for the flush above and
  # the topic may have been assigned in the meantime.
  topic=$(grep '"type":"ai-title"' "$tp" 2>/dev/null | tail -1 \
    | jq -r '.aiTitle // ""' 2>/dev/null)
  # First 140 chars of Claude's final message this turn. Skip sidechain
  # (subagent) entries — their text isn't what the user was told.
  #
  # The window is 1200 lines, not 300. A turn that runs long enough to raise a
  # Notification is exactly the turn that writes hundreds of tool-call lines
  # after its last piece of prose, so a 300-line window often held no assistant
  # text at all and the alert fell back to its generic wording.
  outcome=$(tail -n 1200 "$tp" | jq -rs \
    '[.[]? | select(.type=="assistant" and (.isSidechain != true))
      | .message.content[]? | select(.type=="text") | .text] | last // ""' \
    2>/dev/null | tr '\n' ' ')
  # First clause only: cut at the first ", " "; " ". " "! " "? " that sits
  # outside quotes, backticks, and brackets, so punctuation inside quoted
  # examples, `code spans`, or (parentheticals) never splits the clause.
  # ! and ? are kept; a period mid-token (settings.json, v2.0) or after an
  # abbreviation (e.g., i.e., etc., vs., cf.) doesn't count.
  outcome=$(printf %s "$outcome" | awk '{
    s = $0; n = length(s); depth = 0; dq = 0; bt = 0; out = s
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1); nc = (i < n) ? substr(s, i + 1, 1) : " "
      if (bt) { if (c == "`") bt = 0; continue }
      if (dq) { if (c == "\"") dq = 0; continue }
      if (c == "`") { bt = 1; continue }
      if (c == "\"") { dq = 1; continue }
      if (c == "(" || c == "[" || c == "{") { depth++; continue }
      if (c == ")" || c == "]" || c == "}") { if (depth) depth--; continue }
      if (depth) continue
      if ((c == "," || c == ";") && nc == " ") { out = substr(s, 1, i - 1); break }
      if (c == "." && nc == " ") {
        w = ""
        for (j = i - 1; j >= 1 && substr(s, j, 1) != " "; j--) w = substr(s, j, 1) w
        lw = tolower(w)
        if (lw == "e.g" || lw == "i.e" || lw == "etc" || lw == "vs" || lw == "cf") continue
        out = substr(s, 1, i - 1); break
      }
      if ((c == "!" || c == "?") && nc == " ") { out = substr(s, 1, i); break }
    }
    print out
  }')
  # Length cap as a backstop (no break found), without chopping mid-word.
  if (( ${#outcome} > 140 )); then
    outcome="${outcome:0:140}"; outcome="${outcome% *}"
  fi
fi

if [[ "$event" == "Notification" ]]; then
  # Claude Code fills .message with a fixed string — "Claude is waiting for your
  # input", "Claude needs your permission to use Bash" — which is the same text
  # on every alert and says nothing about which session this is. Claude's own
  # last words say what it is in the middle of, so lead with those and keep the
  # fixed string only for a session that has not written any prose yet.
  msg=$outcome
  if [[ -z "$msg" ]]; then
    msg=$(get '.message // ""')
    [[ -z "$msg" ]] && msg="Needs your input"
  fi
  sound="Ping"
  tmux_state needs-input
else
  msg=${outcome:-"Finished responding"}
  sound="Glass"
  tmux_state done
fi

# End the message on a period (keep ! and ? when the clause ends there).
msg=$(printf %s "$msg" | sed -E 's/[[:space:]:;,.—-]+$//')
case "$msg" in
  *! | *\? ) ;;
  *… ) msg="${msg%…}." ;;
  * ) msg+="." ;;
esac

# Title: session topic, falling back to folder name, then a generic label.
title=${topic:-${dir:-Claude Code}}
[[ -z "$topic" && "$cwd" == "$HOME" ]] && title="Claude Code"

# Alert titles wrap instead of truncating; cap to one line ourselves.
# The title renders in a proportional font, so character count alone is a
# bad predictor — weight narrow/wide glyphs and cut on estimated width.
# If titles ever wrap again, lower the budget (31) a notch.
title=$(printf %s "$title" | awk '{
  n = length($0); wsum = 0; cut = 0
  for (i = 1; i <= n; i++) {
    c = substr($0, i, 1)
    if (index("filjrt-. ,:;!|()[]", c)) w = 0.6
    else if (index("mwMW@", c)) w = 1.5
    else if (c >= "A" && c <= "Z") w = 1.25
    else w = 1.0
    wsum += w
    if (wsum > 31) { cut = i; break }
  }
  if (cut) {
    kept = substr($0, 1, cut - 1)
    if (substr($0, cut, 1) != " ") sub(/ [^ ]*$/, "", kept)
    sub(/ +$/, "", kept)
    printf "%s…", kept
  } else print
}')

# Make sure this session has a watchdog before it gets an alert it could leave
# behind. SessionEnd covers /quit, Ctrl-D and /clear. It does not cover a
# closed terminal window, a closed tmux pane, a SIGKILL or a crash, because
# Claude Code's signal handler exits without awaiting async hooks. The watchdog
# is the backstop for those. One per session: re-check the recorded pid instead
# of spawning a second watcher on every turn.
/bin/mkdir -p "$STATE_DIR"
watch_file="$STATE_DIR/$sid.watch"

# Sweep other sessions first. A reboot kills every watcher without clearing the
# alerts it was guarding, and Notification Center keeps delivered records across
# a restart. Each state file records its own claude pid, so a dead pid here
# means an orphaned alert. Whichever session posts next clears them.
for f in "$STATE_DIR"/*.watch; do
  [[ -e "$f" && "$f" != "$watch_file" ]] || continue
  other_cpid=$(cut -d' ' -f2 "$f" 2>/dev/null)
  [[ -n "$other_cpid" ]] && /bin/kill -0 "$other_cpid" 2>/dev/null && continue
  other_sid=${f##*/}
  "$NOTIFIER" -remove "claude-${other_sid%.watch}" >/dev/null 2>&1
  /bin/rm -f "$f"
done

# One watchdog per session: respawn only when the recorded watcher is gone.
if [[ ! -s "$watch_file" ]] || ! /bin/kill -0 "$(cut -d' ' -f1 "$watch_file" 2>/dev/null)" 2>/dev/null; then
  cpid=$(claude_pid)
  if [[ -n "$cpid" ]]; then
    # nohup so the closing terminal's SIGHUP does not take the watcher with it.
    nohup "$WATCHER" "$cpid" "$group" "$watch_file" >/dev/null 2>&1 &
    printf '%s %s' "$!" "$cpid" > "$watch_file"
  fi
fi

# Clicking the alert should land on this session. Record which tmux window to go
# to, by window id: indices shift whenever a window closes, ids do not. The
# socket path is the part of $TMUX before the first comma.
click=()
if [[ -n "$TMUX" && -n "$TMUX_PANE" ]]; then
  tmux_sock=${TMUX%%,*}
  tmux_win=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)
  if [[ -n "$tmux_win" ]]; then
    click=(-execute "$FOCUS '$tmux_sock' '$tmux_win'")
  fi
fi

# Remove before posting: a replaced-in-group alert keeps its old spot in the
# stack, but a fresh delivery always lands on top.
"$NOTIFIER" -remove "$group" >/dev/null 2>&1

exec "$NOTIFIER" -title "$title" -message "$msg" -sound "$sound" -group "$group" \
  "${click[@]}"
