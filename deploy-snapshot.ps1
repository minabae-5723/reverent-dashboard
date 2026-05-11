# =============================================================
#  Deploy snapshot for Cloudflare Pages
#
#  Refreshes market + calendar data, generates news index, then
#  force-adds runtime files (normally gitignored) so the deployed
#  static site has the latest data baked in.
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
Write-Host " Deploy Snapshot — Reverent Dashboard" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# 1. Refresh market data (Yahoo Finance)
Write-Host "[1/4] Refresh market data..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'refresh.ps1')

# 2. Refresh calendar (Investing.com — may fail if Cloudflare blocking)
Write-Host ""
Write-Host "[2/4] Refresh calendar data..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'fetch-calendar.ps1')

# 3. Generate news/index.json from news/*.md files
Write-Host ""
Write-Host "[3/4] Generate news/index.json..." -ForegroundColor Yellow
$newsDir = Join-Path $root 'news'
$dates = @()
if (Test-Path $newsDir) {
    $dates = Get-ChildItem -LiteralPath $newsDir -Filter '*.md' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.BaseName } |
        Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}$' } |
        Sort-Object -Descending
}
$indexJson = @{ dates = @($dates) } | ConvertTo-Json -Compress
$indexPath = Join-Path $newsDir 'index.json'
[System.IO.File]::WriteAllText($indexPath, $indexJson, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  $($dates.Count) news clipping dates → news/index.json" -ForegroundColor Green

# 4. Stage + commit + push (force-add normally gitignored data files)
Write-Host ""
Write-Host "[4/4] Commit + push deploy snapshot..." -ForegroundColor Yellow
$gitStatus = git status --porcelain 2>&1
if ([string]::IsNullOrWhiteSpace($gitStatus)) {
    Write-Host "  No changes detected — nothing to commit." -ForegroundColor DarkGray
} else {
    # Force-add data snapshots (gitignored normally)
    git add -f data.json calendar.json calendar-week.json news/index.json 2>&1 | Out-Null
    # Add anything else staged-worthy in the regular tree
    git add -A 2>&1 | Out-Null

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    git commit -m "Deploy snapshot $timestamp" 2>&1 | Tee-Object -Variable commitOut | Out-Null
    Write-Host "  Commit: $commitOut" -ForegroundColor DarkGray

    Write-Host "  Pushing to origin/main..." -ForegroundColor DarkGray
    git push 2>&1 | Tee-Object -Variable pushOut | Out-Null
    Write-Host "  $pushOut" -ForegroundColor Green
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Done. Cloudflare Pages will auto-deploy" -ForegroundColor Green
Write-Host " within 1-2 minutes." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Cyan
