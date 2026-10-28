# =============================================================
#  Host-role guard  (ops/hosts.json)
#
#  Several PCs can run this repo at once (co-management), but only ONE may run
#  each publishing job, otherwise their auto-commits race each other on main.
#  ops/hosts.json maps a role ("primary", "us-close") to the COMPUTERNAME that
#  owns it. Handing the dashboard to someone else = edit that file + push;
#  every PC picks it up on its next RepoSync pull, no re-install needed.
#
#  Two ways to use it:
#    1) Dot-source from a job script:
#         . (Join-Path $PSScriptRoot 'ops\role.ps1')
#         if (-not (Test-ReverentRole 'primary')) { exit 0 }
#    2) CLI (Claude scheduled-task prompts):
#         powershell -NoProfile -ExecutionPolicy Bypass -File ops\role.ps1 -Role primary
#       Prints a JSON line; exit code 0 = this host owns the role, 3 = it does not.
#
#  Host id = $env:REVERENT_HOST_ID if set, else $env:COMPUTERNAME.
#  Missing/unreadable hosts.json fails OPEN (job runs) so an old checkout keeps
#  behaving exactly as before this file existed.
#
#  One-day stand-in: hosts.json may carry
#    "today": { "date": "2026-10-29", "roles": { "primary": "<PC>" }, ... }
#  On that date (local time) it overrides "roles"; on any other date it is
#  ignored, so the default owner takes over again the next day with no cleanup.
#  ops/take-today.ps1 writes and clears it. ($env:REVERENT_TODAY overrides the
#  date, for testing only.)
# =============================================================
param([string]$Role)

function Get-ReverentHostId {
    if ($env:REVERENT_HOST_ID) { return $env:REVERENT_HOST_ID }
    return $env:COMPUTERNAME
}

function Get-ReverentToday {
    if ($env:REVERENT_TODAY) { return $env:REVERENT_TODAY }
    return (Get-Date).ToString('yyyy-MM-dd')
}

function Get-ReverentRoleOwner([string]$Role) {
    $path = Join-Path (Split-Path $PSScriptRoot -Parent) 'ops\hosts.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $j = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($j.today -and ("$($j.today.date)" -eq (Get-ReverentToday))) {
            $t = $j.today.roles.PSObject.Properties[$Role]
            if ($null -ne $t -and -not [string]::IsNullOrWhiteSpace([string]$t.Value)) { return [string]$t.Value }
        }
        $p = $j.roles.PSObject.Properties[$Role]
        if ($null -eq $p) { return '' }
        return [string]$p.Value
    } catch {
        return $null
    }
}

function Test-ReverentRole([string]$Role) {
    $owner = Get-ReverentRoleOwner $Role
    if ($null -eq $owner) { return $true }          # no/broken hosts.json -> fail open
    if ($owner -eq '*') { return $true }
    if ([string]::IsNullOrWhiteSpace($owner)) { return $false }
    return ($owner.Trim() -ieq (Get-ReverentHostId))
}

if ($Role -and $MyInvocation.InvocationName -ne '.') {
    $owner = Get-ReverentRoleOwner $Role
    $active = Test-ReverentRole $Role
    [ordered]@{ role = $Role; host = (Get-ReverentHostId); owner = $owner; active = $active } |
        ConvertTo-Json -Compress
    if ($active) { exit 0 } else { exit 3 }
}
