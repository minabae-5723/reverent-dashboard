# =============================================================
#  Friday 16:30 KST deploy — Korean market close (weekly snapshot)
#
#  Runs after KOSPI/KOSDAQ close (15:30) with 60-minute buffer.
#  1) Naver Seoul-close FX  2) refresh Capital Market (index/rate/fx)
#  3) Peer table  4) IPO list  5) commit + push to GitHub.
#  US side finalized by deploy-us-close.ps1 on 부PC (Sat ~06:30 KST).
#  Cloudflare Pages auto-deploys within 1-2 minutes.
#
#  Usage: powershell -ExecutionPolicy Bypass -File .\deploy-friday.ps1
# =============================================================
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

# Never block on an interactive git/GCM credential prompt (scheduled-task hang
# guard — see sync-repo.ps1). Cached creds work; else git fails fast.
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE = 'Never'

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Friday Deploy - Peer & IPO snapshot" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# 1. Korean Capital Market close (KOSPI/KOSDAQ 15:30 + buffer)
#    Naver Seoul-close FX snapshot first, then refresh (index per-exchange daily,
#    Rate/CDS frozen into capmkt-freeze.json on Friday). US side finalized
#    separately by deploy-us-close.ps1 on 부PC (Sat ~06:30 KST after US close).
Write-Host ""
Write-Host "[1/5] Fetch Naver Seoul-close FX snapshot..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'fetch-naver-fx.ps1')

Write-Host ""
Write-Host "[2/5] Refresh Capital Market (index/rate/fx -> data.json)..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'refresh.ps1')

# 3. Peer table
Write-Host ""
Write-Host "[3/5] Fetch Peer table (Yahoo + Naver)..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'fetch-peer.ps1')

# 4. IPO list
Write-Host ""
Write-Host "[4/5] Fetch IPO new-listings (38.co.kr + Naver)..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'fetch-ipo.ps1')

# 5. Commit + push
Write-Host ""
Write-Host "[5/5] Commit + push..." -ForegroundColor Yellow
$gitStatus = git status --porcelain 2>&1
if ([string]::IsNullOrWhiteSpace($gitStatus)) {
    Write-Host "  No changes detected." -ForegroundColor DarkGray
} else {
    git add -f peer.json ipo.json peer-config.json 2>&1 | Out-Null
    git add -A 2>&1 | Out-Null
    Write-Host "  Staged:" -ForegroundColor DarkGray
    git status --short | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    $ts = '{0:yyyy-MM-dd HH:mm}' -f (Get-Date)
    git commit -m "Friday KR-close snapshot $ts (capmkt + peer + IPO)" 2>&1 | Out-Null
    Write-Host "  Pushing to origin/main..." -ForegroundColor DarkGray
    git push 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Green }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Done. Cloudflare Pages will auto-deploy" -ForegroundColor Green
Write-Host " within 1-2 minutes." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Cyan
