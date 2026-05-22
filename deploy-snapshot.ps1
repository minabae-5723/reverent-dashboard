# =============================================================
#  Deploy snapshot for Cloudflare Pages
#
#  Refreshes market + calendar data, regenerates index.json for
#  every clipping folder (news / market / deals), then force-adds
#  runtime files (normally gitignored) so the deployed static
#  site has the latest data baked in.
#
#  Usage:
#    powershell -ExecutionPolicy Bypass -File .\deploy-snapshot.ps1
#
#  Cloudflare Pages auto-deploys on every push to main.
# =============================================================
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Deploy Snapshot - Reverent Dashboard" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# Folders that have YYYY-MM-DD.md files served as JSON-indexed lists.
# Each gets an `index.json` regenerated from its .md file basenames.
$INDEXED_FOLDERS = @('news', 'market', 'deals')

# 1. Refresh market data (Yahoo Finance)
Write-Host "[1/4] Refresh market data..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'refresh.ps1')

# 2. Refresh calendar (Investing.com -- may fail if Cloudflare blocking)
Write-Host ""
Write-Host "[2/5] Refresh calendar data..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'fetch-calendar.ps1')

# 2.5. Refresh semiconductor trade data (Korea Customs OpenAPI) — last 2 years only
Write-Host ""
Write-Host "[2.5/5] Refresh trade data (SSD/NAND/DRAM, last 2 years)..." -ForegroundColor Yellow
$tradeScript = Join-Path $root 'fetch-trade.ps1'
$thisYear = (Get-Date).Year
$startYear = $thisYear - 1
& powershell -NoProfile -ExecutionPolicy Bypass -File $tradeScript -StartYear $startYear

# 2.7. Refresh Shiller P/E (CAPE)
Write-Host ""
Write-Host "[2.7/5] Refresh Shiller P/E ratio..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'fetch-shiller.ps1')

# 2.8. Refresh FedWatch (Fed rate probability)
Write-Host ""
Write-Host "[2.8/5] Refresh FedWatch (Fed rate probability)..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'fetch-fedwatch.ps1')

# 2.9. Prune daily-rotation files older than 7 days
#       `market/` (Daily Market Briefing) + `news/` (News Clipping) keep only
#       the last week of YYYY-MM-DD.md snapshots — older ones are git-rm'd so
#       the deploy stays lean and the dashboard pills only show recent dates.
#       `deals/` is week-bucketed (Monday Brief) so it's not pruned here.
Write-Host ""
Write-Host "[2.9/5] Prune market/ and news/ files > 7 days old..." -ForegroundColor Yellow
$cutoff = (Get-Date).AddDays(-7).ToString('yyyy-MM-dd')
foreach ($folder in @('market', 'news')) {
    $dir = Join-Path $root $folder
    if (-not (Test-Path $dir)) { continue }
    $stale = Get-ChildItem -LiteralPath $dir -Filter '*.md' -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match '^\d{4}-\d{2}-\d{2}$' -and $_.BaseName -lt $cutoff }
    if ($stale) {
        foreach ($f in $stale) {
            $relPath = "$folder/$($f.Name)"
            # Try git rm first (so deletion is staged); fall back to plain rm
            # for files not yet in git.
            $gitOut = git rm -f $relPath 2>&1
            if ($LASTEXITCODE -ne 0) {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
            }
            Write-Host "    pruned: $relPath" -ForegroundColor DarkGray
        }
        Write-Host ("  $folder/: pruned " + $stale.Count + " file(s) older than " + $cutoff) -ForegroundColor Yellow
    } else {
        Write-Host "  $folder/: no stale files." -ForegroundColor DarkGray
    }
}

# 3. Regenerate index.json for every clipping folder
Write-Host ""
Write-Host "[3/4] Regenerate index.json for clipping folders..." -ForegroundColor Yellow
foreach ($folder in $INDEXED_FOLDERS) {
    $dir = Join-Path $root $folder
    if (-not (Test-Path $dir)) {
        Write-Host "  ${folder}/: (folder missing, skipping)" -ForegroundColor DarkGray
        continue
    }
    $dates = @(Get-ChildItem -LiteralPath $dir -Filter '*.md' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.BaseName } |
        Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}$' } |
        Sort-Object -Descending)
    $json = @{ dates = $dates } | ConvertTo-Json -Compress
    $idxPath = Join-Path $dir 'index.json'
    [System.IO.File]::WriteAllText($idxPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    $sample = if ($dates.Count -gt 0) { " (" + ($dates[0..([Math]::Min($dates.Count, 3) - 1)] -join ', ') + ($(if ($dates.Count -gt 3) { ", ..." } else { "" })) + ")" } else { "" }
    Write-Host ("  {0,-7} -> {1} entries{2}" -f "${folder}/", $dates.Count, $sample) -ForegroundColor Green
}

# 4. Stage + commit + push (force-add normally gitignored data files)
Write-Host ""
Write-Host "[4/4] Commit + push deploy snapshot..." -ForegroundColor Yellow
$gitStatus = git status --porcelain 2>&1
if ([string]::IsNullOrWhiteSpace($gitStatus)) {
    Write-Host "  No changes detected -- nothing to commit." -ForegroundColor DarkGray
} else {
    # Force-add data snapshots (gitignored normally) + all index.json files
    $forceFiles = @('data.json', 'calendar.json', 'calendar-week.json', 'calendar-next-week.json', 'market-update-frozen.json', 'trade.json', 'shiller.json', 'fedwatch.json', 'user-state.json') +
                  ($INDEXED_FOLDERS | ForEach-Object { "$_/index.json" })
    git add -f $forceFiles 2>&1 | Out-Null
    # Add anything else (new .md files, code changes, etc.)
    git add -A 2>&1 | Out-Null

    Write-Host "  Staged:" -ForegroundColor DarkGray
    git status --short | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    git commit -m "Deploy snapshot $timestamp" 2>&1 | Tee-Object -Variable commitOut | Out-Null
    Write-Host "  Commit: $($commitOut | Select-Object -Last 1)" -ForegroundColor DarkGray

    Write-Host "  Pushing to origin/main..." -ForegroundColor DarkGray
    git push 2>&1 | Tee-Object -Variable pushOut | Out-Null
    $pushOut | ForEach-Object { Write-Host "    $_" -ForegroundColor Green }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Done. Cloudflare Pages will auto-deploy" -ForegroundColor Green
Write-Host " within 1-2 minutes." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Cyan
