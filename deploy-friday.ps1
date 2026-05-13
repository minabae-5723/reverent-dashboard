# =============================================================
#  Friday 16:30 KST deploy — Peer table + IPO list (weekly snapshot)
#
#  Runs after KOSPI/KOSDAQ close (15:30) with 60-minute buffer.
#  Fetches peer.json + ipo.json, commits, pushes to GitHub.
#  Cloudflare Pages auto-deploys within 1-2 minutes.
#
#  Usage: powershell -ExecutionPolicy Bypass -File .\deploy-friday.ps1
# =============================================================
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Friday Deploy - Peer & IPO snapshot" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# 1. Peer table
Write-Host ""
Write-Host "[1/3] Fetch Peer table (Yahoo + Naver)..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'fetch-peer.ps1')

# 2. IPO list
Write-Host ""
Write-Host "[2/3] Fetch IPO new-listings (38.co.kr + Naver)..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'fetch-ipo.ps1')

# 3. Commit + push
Write-Host ""
Write-Host "[3/3] Commit + push..." -ForegroundColor Yellow
$gitStatus = git status --porcelain 2>&1
if ([string]::IsNullOrWhiteSpace($gitStatus)) {
    Write-Host "  No changes detected." -ForegroundColor DarkGray
} else {
    git add -f peer.json ipo.json peer-config.json 2>&1 | Out-Null
    git add -A 2>&1 | Out-Null
    Write-Host "  Staged:" -ForegroundColor DarkGray
    git status --short | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    git commit -m "Friday snapshot $ts (peer + IPO)" 2>&1 | Out-Null
    Write-Host "  Pushing to origin/main..." -ForegroundColor DarkGray
    git push 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Green }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Done. Cloudflare Pages will auto-deploy" -ForegroundColor Green
Write-Host " within 1-2 minutes." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Cyan
