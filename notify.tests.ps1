# Unit tests for the pure transition logic in notify.ps1. Run: powershell -File notify.tests.ps1
. (Join-Path $PSScriptRoot 'notify.ps1')

$failed = 0
function Assert([bool]$cond, [string]$name) {
    if ($cond) { Write-Host "  ok   $name" } else { Write-Host "  FAIL $name" -ForegroundColor Red; $script:failed++ }
}

function Cur([string]$status) { @{ status = $status; agent = 'claude'; workspace = 'w1' } }

# working -> done fires "done"
$n = @(Get-Notifications @{ 'w1:p1' = 'working' } @{ 'w1:p1' = (Cur 'done') })
Assert ($n.Count -eq 1 -and $n[0].kind -eq 'done') 'working->done notifies done'

# working -> idle fires "done"
$n = @(Get-Notifications @{ 'w1:p1' = 'working' } @{ 'w1:p1' = (Cur 'idle') })
Assert ($n.Count -eq 1 -and $n[0].kind -eq 'done') 'working->idle notifies done'

# working -> blocked fires "blocked"
$n = @(Get-Notifications @{ 'w1:p1' = 'working' } @{ 'w1:p1' = (Cur 'blocked') })
Assert ($n.Count -eq 1 -and $n[0].kind -eq 'blocked') 'working->blocked notifies blocked'

# idle -> working (turn start) is silent
$n = @(Get-Notifications @{ 'w1:p1' = 'idle' } @{ 'w1:p1' = (Cur 'working') })
Assert ($n.Count -eq 0) 'idle->working is silent'

# blocked -> working (mid-turn resume) is silent
$n = @(Get-Notifications @{ 'w1:p1' = 'blocked' } @{ 'w1:p1' = (Cur 'working') })
Assert ($n.Count -eq 0) 'blocked->working is silent'

# steady working is silent (no edge)
$n = @(Get-Notifications @{ 'w1:p1' = 'working' } @{ 'w1:p1' = (Cur 'working') })
Assert ($n.Count -eq 0) 'working->working is silent'

# a brand-new pane already resting (no prior status) is silent (avoids startup spam)
$n = @(Get-Notifications @{} @{ 'w1:p1' = (Cur 'done') })
Assert ($n.Count -eq 0) 'unknown-prev->done is silent'

# unknown transient is not a done state
$n = @(Get-Notifications @{ 'w1:p1' = 'working' } @{ 'w1:p1' = (Cur 'unknown') })
Assert ($n.Count -eq 0) 'working->unknown is silent'

# multiple panes: only the transitioning one fires
$n = @(Get-Notifications @{ 'w1:p1' = 'working'; 'w2:p1' = 'idle' } @{ 'w1:p1' = (Cur 'done'); 'w2:p1' = (Cur 'working') })
Assert ($n.Count -eq 1 -and $n[0].pane -eq 'w1:p1') 'only the transitioning pane fires'

if ($failed -eq 0) { Write-Host "`nAll tests passed." -ForegroundColor Green } else { Write-Host "`n$failed failed." -ForegroundColor Red; exit 1 }
