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
Write-Host "[2/4] Refresh calendar data..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'fetch-calendar.ps1')

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
    $forceFiles = @('data.json', 'calendar.json', 'calendar-week.json') +
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
