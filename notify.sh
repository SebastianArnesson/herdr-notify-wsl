#!/usr/bin/env bash
# herdr-notify (WSL -> Windows): raise a Windows 11 toast when an agent needs you.
#
# WSL-native adaptation of the upstream Windows plugin. herdr runs as the Linux
# binary inside WSL, so the status query/diff happens here in bash; we only cross
# into Windows (via powershell.exe) for the actual toast.
#
# Wired to the `pane.agent_status_changed` event. Rather than trust the event
# payload, it reads `herdr pane list` for every agent pane's status and diffs it
# against the last-seen status (a JSON state file), notifying on exactly:
#
#   working -> done | idle   -> "Turn finished"
#   working -> blocked       -> "Needs input"
#
# `--test` fires one sample toast to confirm delivery (Focus Assist off, notifications on).
set -euo pipefail

HERDR_BIN="${HERDR_BIN_PATH:-herdr}"
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}}"
STATE_PATH="$STATE_DIR/agent-status.json"
PS="${WINDIR:+$WINDIR/System32/WindowsPowerShell/v1.0/powershell.exe}"
PS="${PS:-powershell.exe}"

# Raise a native Windows toast. Args: title, message, skip_if_terminal_focused (1/0). Text is
# passed as base64 to dodge any quoting/encoding hazard crossing the WSL->Windows boundary.
# ponytail: "terminal focused" = foreground process is Windows Terminal; can't tell which WT
# tab is active, so another WT tab in front also suppresses. Add other terminal names here if needed.
show_toast() {
  local title_b64 msg_b64 skip_focused="${3:-0}"
  title_b64=$(printf '%s' "$1" | base64 -w0)
  msg_b64=$(printf '%s' "$2" | base64 -w0)
  "$PS" -NoProfile -Command "
if ($skip_focused) {
  Add-Type -Namespace HerdrNotify -Name Win32 -MemberDefinition '
    [DllImport(\"user32.dll\")] public static extern IntPtr GetForegroundWindow();
    [DllImport(\"user32.dll\")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);'
  [uint32]\$fgPid = 0
  [void][HerdrNotify.Win32]::GetWindowThreadProcessId([HerdrNotify.Win32]::GetForegroundWindow(), [ref]\$fgPid)
  if ((Get-Process -Id \$fgPid -ErrorAction SilentlyContinue).ProcessName -eq 'WindowsTerminal') { exit }
}
\$title = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$title_b64'))
\$msg   = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$msg_b64'))
\$appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
\$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
\$t = \$xml.GetElementsByTagName('text')
[void]\$t.Item(0).AppendChild(\$xml.CreateTextNode(\$title))
[void]\$t.Item(1).AppendChild(\$xml.CreateTextNode(\$msg))
\$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(\$appId).Show(\$toast)
" >/dev/null 2>&1
}

if [[ "${1:-}" == "--test" || "${1:-}" == "-Test" ]]; then
  show_toast 'herdr-notify' 'Test notification - setup OK'
  exit 0
fi

# Current agent panes -> JSON object { pane_id: {status, agent, workspace, focused} }
current=$("$HERDR_BIN" pane list 2>/dev/null | jq -c '
  [.result.panes[] | select(.agent != null and .agent != "")
    | {key: .pane_id, value: {status: (.agent_status // ""), agent: (.agent // ""), workspace: (.workspace_id // ""),
                              focused: (.focused == true)}}]
  | from_entries')

# Previous status map { pane_id: status }; empty object if no state yet.
# Missing, empty, corrupt or non-object state all fall back to {} so a bad file can't wedge us.
prev=$(jq -cs '.[0] | objects // {}' "$STATE_PATH" 2>/dev/null) || prev='{}'

# Notifications: only a working -> rest edge fires. Emits agent<US>workspace<US>kind<US>focused, using the
# non-whitespace 0x1f separator so an empty field isn't collapsed by `read` (tab would be).
notifs=$(jq -rn --argjson prev "$prev" --argjson cur "$current" '
  $cur | to_entries[]
  | . as $e
  | ($prev[$e.key] // "") as $before
  | select($before == "working")
  | (if (["done","idle"] | index($e.value.status)) then "done"
     elif $e.value.status == "blocked" then "blocked"
     else empty end) as $kind
  | [$e.value.agent, $e.value.workspace, $kind, ($e.value.focused | tostring)] | join("\u001f")')

# Resolve a workspace id to a human label, falling back to the id.
workspace_label() {
  local id="$1" label
  [[ -z "$id" ]] && { echo ""; return; }
  label=$("$HERDR_BIN" workspace get "$id" 2>/dev/null \
    | jq -r '.result.workspace | (.label // "") as $l | (.number|tostring) as $n
             | if ($l != "" and $l != $n) then $l else "" end' 2>/dev/null || echo "")
  [[ -n "$label" ]] && echo "$label" || echo "$id"
}

if [[ -n "$notifs" ]]; then
  while IFS=$'\x1f' read -r agent workspace kind focused; do
    [[ -z "$agent" ]] && continue
    label=$(workspace_label "$workspace")
    who="$agent"
    [[ -n "$label" ]] && who="$agent · $label"
    body="Turn finished"
    [[ "$kind" == "blocked" ]] && body="Needs input"
    # Pane already in view in herdr: stay quiet unless the terminal isn't the foreground window.
    skip=0
    [[ "$focused" == "true" ]] && skip=1
    show_toast "$who" "$body" "$skip"
  done <<< "$notifs"
fi

# Persist current statuses as { pane_id: status } for the next diff.
mkdir -p "$STATE_DIR"
echo "$current" | jq -c 'map_values(.status)' > "$STATE_PATH"
