# =============================================================
#  One-day stand-in for the "primary" role (ops/hosts.json "today")
#
#  The default operator stays in roles.primary. When they cannot run RMM on a
#  given day, a stand-in who already installed everything runs this on their
#  own PC; from then until midnight every guarded job (deploys, Claude
#  routines, WiseReport, semi-dashboard) runs on the stand-in's PC and skips
#  everywhere else. Next day the entry is stale and the default owner is back
#  automatically - nothing to undo.
#
#    powershell -NoProfile -ExecutionPolicy Bypass -File ops\take-today.ps1            # I'm on duty today
#    ... -Release     clear today's entry (default owner takes over again now)
#    ... -Status      show who is on duty, change nothing
#    ... -NoCommit    write hosts.json locally only (testing)
#
#  Prints one JSON line; exit 0 = done, 1 = could not push (nothing changed remotely).
# =============================================================
param([switch]$Release, [switch]$Status, [switch]$NoCommit)
$ErrorActionPreference = 'Continue'
$repo = Split-Path $PSScriptRoot -Parent
Set-Location $repo
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE = 'Never'
$hostsPath = Join-Path $PSScriptRoot 'hosts.json'
$utf8 = New-Object System.Text.UTF8Encoding($false)

. (Join-Path $PSScriptRoot 'role.ps1')

function Read-Roster { [System.IO.File]::ReadAllText($hostsPath, $utf8) | ConvertFrom-Json }

function Write-Roster($j) {
    # Hand-formatted so the file stays easy to edit by hand.
    $q = { param($s) ConvertTo-Json ([string]$s) }
    $out = @('{', ('  "_comment": {0},' -f (& $q $j._comment)), '  "roles": {')
    $r = @($j.roles.PSObject.Properties)
    for ($i = 0; $i -lt $r.Count; $i++) {
        $out += ('    "{0}": {1}{2}' -f $r[$i].Name, (& $q $r[$i].Value), $(if ($i -lt $r.Count - 1) { ',' } else { '' }))
    }
    if ($j.today) {
        $out += '  },'
        $out += '  "today": {'
        $out += ('    "date": {0},' -f (& $q $j.today.date))
        $out += ('    "roles": {{ "primary": {0} }},' -f (& $q $j.today.roles.primary))
        $out += ('    "by": {0},' -f (& $q $j.today.by))
        $out += ('    "at": {0}' -f (& $q $j.today.at))
        $out += '  }'
    } else {
        $out += '  }'
    }
    $out += '}'
    [System.IO.File]::WriteAllText($hostsPath, (($out -join "`r`n") + "`r`n"), $utf8)
}

function Show([string]$note) {
    $j = Read-Roster
    $todayOwner = if ($j.today -and "$($j.today.date)" -eq (Get-ReverentToday)) { "$($j.today.roles.primary)" } else { '' }
    [ordered]@{
        date         = (Get-ReverentToday)
        defaultOwner = "$($j.roles.primary)"
        todayOwner   = $todayOwner
        thisPc       = (Get-ReverentHostId)
        thisPcOnDuty = (Test-ReverentRole 'primary')
        note         = $note
    } | ConvertTo-Json -Compress
}

# Latest roster first, so we never overwrite someone else's change.
if (-not $NoCommit) { & git pull -q --rebase --autostash origin main 2>&1 | Out-Null }

if ($Status) { Show 'status only'; exit 0 }

$j = Read-Roster
$me = Get-ReverentHostId
$today = Get-ReverentToday
$hasToday = ($j.PSObject.Properties['today'] -ne $null)

if ($Release) {
    if (-not $hasToday) { Show 'nothing to release'; exit 0 }
    $j.PSObject.Properties.Remove('today')
    $msg = "ops: duty back to default owner ($today)"
} else {
    if ($hasToday -and "$($j.today.date)" -eq $today -and "$($j.today.roles.primary)" -ieq $me) { Show 'already on duty today'; exit 0 }
    $entry = [pscustomobject]@{ date = $today; roles = [pscustomobject]@{ primary = $me }; by = $me; at = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz') }
    if ($hasToday) { $j.today = $entry } else { $j | Add-Member -NotePropertyName today -NotePropertyValue $entry }
    $msg = "ops: $me is on duty today ($today)"
}
Write-Roster $j
if ($NoCommit) { Show 'written locally (not committed)'; exit 0 }

& git add ops/hosts.json 2>&1 | Out-Null
& git commit -q -m $msg -- ops/hosts.json 2>&1 | Out-Null
for ($try = 1; $try -le 3; $try++) {
    & git push -q origin HEAD:main 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Show 'pushed'; exit 0 }
    Start-Sleep -Seconds 5
    & git pull -q --rebase --autostash origin main 2>&1 | Out-Null
}
Show 'PUSH FAILED - check GitHub access (git push) and retry'
exit 1
