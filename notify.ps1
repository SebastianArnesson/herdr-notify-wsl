# herdr-notify (Windows): raise a Windows 11 toast when an agent needs you.
#
# Wired to the `pane.agent_status_changed` event. Rather than trust the event payload, it reads
# `herdr pane list` for every agent pane's current status and diffs it against the last-seen
# status (a JSON state file), so it notifies exactly on the transitions that matter:
#
#   working -> done | idle   -> "turn finished"
#   working -> blocked       -> "needs input"
#
# Native Windows toast via WinRT (no BurntToast/Node needed); herdr's `bash` on Windows is WSL, so
# this is a PowerShell script routed by the manifest's `platforms = ["windows"]`.
#
# Dot-source it (`. .\notify.ps1`) to load the functions without running — used by notify.tests.ps1.
#
# `-Test` fires one sample toast so you can confirm delivery (Focus Assist off, notifications on).
param([switch]$Test)

$ErrorActionPreference = 'Stop'

$script:Herdr = if ($env:HERDR_BIN_PATH) { $env:HERDR_BIN_PATH } else { 'herdr' }
$script:StateDir = if ($env:HERDR_PLUGIN_STATE_DIR) { $env:HERDR_PLUGIN_STATE_DIR } else { $env:TEMP }
$script:StatePath = Join-Path $script:StateDir 'agent-status.json'

# Statuses that mean "the agent stopped and wants you", keyed to the message shown.
$script:DoneStates = @('done', 'idle')

function Invoke-Herdr {
    $out = & $script:Herdr @args 2>$null
    if ($LASTEXITCODE -ne 0) { throw "herdr $($args -join ' ') failed" }
    ($out | Out-String).Trim()
}

# Current agent panes as pane_id -> @{ status; agent; workspace } (workspace is the id here).
function Get-AgentPanes {
    $out = Invoke-Herdr pane list
    $panes = if ($out) { ($out | ConvertFrom-Json).result.panes } else { @() }
    $map = @{}
    foreach ($p in $panes) {
        if (-not $p.agent) { continue }
        $map[$p.pane_id] = @{ status = [string]$p.agent_status; agent = [string]$p.agent; workspace = [string]$p.workspace_id }
    }
    $map
}

# Pure decision logic (unit-tested): given the previous status map (pane_id -> status string) and
# the current pane map, return the notifications to raise. Only a working->rest edge fires, so a
# fresh pane (no prior status) and steady states stay quiet.
function Get-Notifications([hashtable]$prev, [hashtable]$current) {
    $result = @()
    foreach ($id in $current.Keys) {
        $cur = $current[$id]
        $before = if ($prev.ContainsKey($id)) { [string]$prev[$id] } else { '' }
        if ($before -ne 'working') { continue }
        if ($script:DoneStates -contains $cur.status) {
            $result += @{ pane = $id; agent = $cur.agent; workspace = $cur.workspace; kind = 'done' }
        } elseif ($cur.status -eq 'blocked') {
            $result += @{ pane = $id; agent = $cur.agent; workspace = $cur.workspace; kind = 'blocked' }
        }
    }
    $result
}

function Get-WorkspaceLabel([string]$workspaceId) {
    if (-not $workspaceId) { return '' }
    try {
        $ws = (Invoke-Herdr workspace get $workspaceId | ConvertFrom-Json).result.workspace
        $label = [string]$ws.label
        $number = if ($null -ne $ws.number) { [string]$ws.number } else { '' }
        if ($label -and $label -ne $number) { return $label }
    } catch {}
    $workspaceId
}

function Show-Toast([string]$title, [string]$message) {
    # The built-in PowerShell AppUserModelID gives the toast a registered identity so Windows shows
    # it (an unregistered AppId is silently dropped). ToastText02 = bold heading + one body line.
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
        [Windows.UI.Notifications.ToastTemplateType]::ToastText02)
    $texts = $xml.GetElementsByTagName('text')
    [void]$texts.Item(0).AppendChild($xml.CreateTextNode($title))
    [void]$texts.Item(1).AppendChild($xml.CreateTextNode($message))
    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
}

function Send-Notification($n) {
    $label = Get-WorkspaceLabel $n.workspace
    $who = if ($label) { "$($n.agent) · $label" } else { [string]$n.agent }
    $body = if ($n.kind -eq 'blocked') { 'Needs input' } else { 'Turn finished' }
    Show-Toast $who $body
}

function Read-State {
    try {
        $raw = Get-Content -LiteralPath $script:StatePath -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json
        $map = @{}
        foreach ($prop in $obj.PSObject.Properties) { $map[$prop.Name] = [string]$prop.Value }
        $map
    } catch { @{} }
}

function Write-State([hashtable]$current) {
    $flat = @{}
    foreach ($id in $current.Keys) { $flat[$id] = $current[$id].status }
    $dir = Split-Path -Parent $script:StatePath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    ($flat | ConvertTo-Json -Compress) | Set-Content -LiteralPath $script:StatePath -NoNewline
}

function Invoke-Main {
    $current = Get-AgentPanes
    $prev = Read-State
    foreach ($n in (Get-Notifications $prev $current)) { Send-Notification $n }
    Write-State $current
}

# Run only when executed directly (powershell -File notify.ps1), not when dot-sourced for tests.
if ($MyInvocation.InvocationName -ne '.') {
    if ($Test) { Show-Toast 'herdr-notify' 'Test notification - setup OK' }
    else { Invoke-Main }
}
