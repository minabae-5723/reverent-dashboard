# One-time setup: register the ReverentDashboard-KeepAlive scheduled task.
# Checks localhost:8000 every 5 min (and at logon) and restarts serve.ps1 hidden
# if it is down. Mirrors DealAngleRadar-KeepAlive / FrontOfficeKeepAlive.
#
# Run once:  powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-keepalive-task.ps1
$vbs = Join-Path $env:USERPROFILE '.scripts\silent-ps.vbs'
$ka  = Join-Path $PSScriptRoot 'keepalive-check.ps1'
if (-not (Test-Path $vbs)) { throw "missing launcher: $vbs" }
if (-not (Test-Path $ka))  { throw "missing health check: $ka" }

$act = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"{0}" "{1}"' -f $vbs, $ka)
$t1  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
         -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration ([TimeSpan]::MaxValue)
$t2  = New-ScheduledTaskTrigger -AtLogOn
$set = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
         -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
         -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName 'ReverentDashboard-KeepAlive' -Action $act -Trigger $t1,$t2 `
    -Settings $set -Force `
    -Description 'Restart reverent-dashboard serve.ps1 (localhost:8000) if it is down. Every 5 min + at logon.' |
    Select-Object TaskName, State | Format-List

# The old ReverentDashServer task had a one-time 2026-08-12 trigger and launched
# START.bat in a console (died with STATUS_CONTROL_C_EXIT). Disable it so it can
# never spawn a duplicate console server; the keepalive task replaces it.
try {
    Disable-ScheduledTask -TaskName 'ReverentDashServer' -ErrorAction Stop |
        Select-Object TaskName, State | Format-List
} catch { Write-Host "ReverentDashServer: not found or already disabled" }
