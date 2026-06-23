# =============================================================
#  Refresh market data (data.json) + push to origin/Cloudflare — but ONLY when
#  the market NUMBERS actually changed (ignores the updated/updatedKr timestamp
#  so a flat/closed market doesn't spam commits).
#
#  Launched DETACHED by serve.ps1's /refresh-market endpoint, which the
#  dashboard's 5-min auto-refresh timer hits. Running here (a child of the
#  INTERACTIVE serve.ps1) means git push is reliable — unlike the windowless
#  RepoSync/DailyDeploy scheduled tasks that exit 0xC000013A on push. Detached
#  so the ~40s Yahoo fetch never blocks serve.ps1's HTTP listener.
# =============================================================
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE = 'Never'

$refresh = Join-Path $root 'refresh.ps1'
if (Test-Path -LiteralPath $refresh) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $refresh 2>&1 | Out-Null
}
if (-not (Test-Path -LiteralPath (Join-Path $root 'data.json'))) { return }

& git -C $root add -f data.json 2>&1 | Out-Null
$diff = & git -C $root diff --cached -U0 -- data.json 2>&1
$meaningful = @($diff | Where-Object {
    ($_ -match '^[+-]') -and ($_ -notmatch '^(\+\+\+|---)') -and ($_ -notmatch '"updated(Kr)?"\s*:')
})
if ($meaningful.Count -gt 0) {
    $ts = '{0:yyyy-MM-dd HH:mm}' -f (Get-Date)
    & git -C $root commit -m "Market data $ts (auto 5min)" 2>&1 | Out-Null
    & git -C $root pull --rebase --autostash origin main 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { & git -C $root rebase --abort 2>&1 | Out-Null }
    & git -C $root push origin main 2>&1 | Out-Null
} else {
    # Only the timestamp changed -> discard so the tree stays clean (no churn).
    & git -C $root checkout HEAD -- data.json 2>&1 | Out-Null
}
