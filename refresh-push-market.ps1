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

# FedWatch rides this same timer, throttled to roughly hourly.
#
# fetch-fedwatch.ps1 computes FOMC probabilities from CME fed funds futures, so
# it tracks near-live (the contracts trade ~23h/day) -- but refetching 6
# contracts plus the NY Fed EFFR every 5 minutes is needless traffic and the
# numbers barely move at that resolution. An hour is the agreed tolerance.
#
# Deliberately NOT subject to the Monday-morning freeze that gates refresh.ps1:
# Capital Market holds the weekend snapshot for the Monday Brief, whereas
# FedWatch is meant to keep moving. refresh.ps1 exiting early on Monday does not
# stop this block, since it runs as a separate process.
$fwPath = Join-Path $root 'fedwatch.json'
$fwStale = $true
if (Test-Path -LiteralPath $fwPath) {
    try {
        $fw = Get-Content -LiteralPath $fwPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($fw.updated) {
            $age = (Get-Date).ToUniversalTime() - ([DateTime]::Parse($fw.updated)).ToUniversalTime()
            $fwStale = ($age.TotalMinutes -ge 55)
        }
    } catch { $fwStale = $true }
}
if ($fwStale) {
    $fwScript = Join-Path $root 'fetch-fedwatch.ps1'
    if (Test-Path -LiteralPath $fwScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $fwScript -Quiet 2>&1 | Out-Null
    }
}

# Shiller P/E (CAPE) rides the same timer on the same terms as FedWatch
# (user rule, 2026-09-14: refresh every cycle regardless of weekday/hour).
#
# Previously CAPE was only refreshed inside deploy-snapshot.ps1, which in
# practice meant a manual Friday run -- so the board could sit on a stale
# value for days. Like FedWatch it is deliberately NOT subject to the
# Monday-morning freeze in refresh.ps1: that freeze exists to hold the
# Capital Market weekly snapshot for the Monday Brief, and CAPE is not part
# of that snapshot.
#
# Same 55-min throttle as FedWatch. multpl.com republishes at most once per
# trading day, so hourly already oversamples the source; the point of this
# block is removing the day/hour gate, not hammering multpl every 5 minutes.
$capePath = Join-Path $root 'shiller.json'
$capeStale = $true
if (Test-Path -LiteralPath $capePath) {
    try {
        $cape = Get-Content -LiteralPath $capePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cape.updated) {
            $age = (Get-Date).ToUniversalTime() - ([DateTime]::Parse($cape.updated)).ToUniversalTime()
            $capeStale = ($age.TotalMinutes -ge 55)
        }
    } catch { $capeStale = $true }
}
if ($capeStale) {
    $capeScript = Join-Path $root 'fetch-shiller.ps1'
    if (Test-Path -LiteralPath $capeScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $capeScript -Quiet 2>&1 | Out-Null
    }
}

# data.json and fedwatch.json are gitignored, hence add -f. shiller.json is
# tracked normally but -f is harmless and keeps the three in one call.
& git -C $root add -f data.json fedwatch.json shiller.json 2>&1 | Out-Null
$diff = & git -C $root diff --cached -U0 -- data.json fedwatch.json shiller.json 2>&1
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
    # Must cover fedwatch.json and shiller.json too, otherwise they sit staged
    # until something else commits and get swept into an unrelated change.
    & git -C $root reset -q HEAD -- data.json fedwatch.json shiller.json 2>&1 | Out-Null
    & git -C $root checkout HEAD -- data.json fedwatch.json shiller.json 2>&1 | Out-Null
}
