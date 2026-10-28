# =============================================================
#  Daily KR market close deploy (Mon-Fri 15:45 KST)
#
#  Runs 15 min after KOSPI/KOSDAQ close (15:30).
#  Captures fresh Korean-market-close data:
#    - Naver Seoul-close FX snapshot
#    - Capital Market refresh (index/rate/fx via Yahoo)
#    - FedWatch (CME fed funds futures)
#    - Shiller CAPE
#  Then commits + pushes to GitHub -> Cloudflare Pages auto-deploy.
#
#  On Fridays deploy-friday.ps1 (16:30) additionally fetches peer + IPO.
#
#  Usage: powershell -ExecutionPolicy Bypass -File .\deploy-kr-close.ps1
# =============================================================
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

# Role guard: only the host that owns "primary" in ops/hosts.json runs this job.
$roleGuard = Join-Path $root 'ops\role.ps1'
if (Test-Path -LiteralPath $roleGuard) {
    . $roleGuard
    if (-not (Test-ReverentRole 'primary')) {
        Write-Host "Skipped: role 'primary' is owned by another host (ops/hosts.json)" -ForegroundColor DarkGray
        exit 0
    }
}

$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE = 'Never'

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " KR Close deploy - $((Get-Date).ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# 0. Sync from origin first
Write-Host ""
Write-Host "[0/5] Sync from origin/main..." -ForegroundColor Yellow
foreach ($d in '.git\rebase-merge', '.git\rebase-apply') {
    if (Test-Path (Join-Path $root $d)) { & git -C $root rebase --abort 2>&1 | Out-Null }
}
& git -C $root pull --rebase --autostash origin main 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { & git -C $root rebase --abort 2>&1 | Out-Null }

# 1. Naver Seoul-close FX
Write-Host ""
Write-Host "[1/5] Fetch Naver Seoul-close FX snapshot..." -ForegroundColor Yellow
$fxScript = Join-Path $root 'fetch-naver-fx.ps1'
if (Test-Path -LiteralPath $fxScript) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $fxScript
}

# 2. Market data (Yahoo)
Write-Host ""
Write-Host "[2/5] Refresh Capital Market (data.json)..." -ForegroundColor Yellow
$refreshScript = Join-Path $root 'refresh.ps1'
if (Test-Path -LiteralPath $refreshScript) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $refreshScript
}

# 3. FedWatch
Write-Host ""
Write-Host "[3/5] Refresh FedWatch..." -ForegroundColor Yellow
$fwScript = Join-Path $root 'fetch-fedwatch.ps1'
if (Test-Path -LiteralPath $fwScript) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $fwScript
}

# 4. Shiller CAPE
Write-Host ""
Write-Host "[4/5] Refresh Shiller P/E..." -ForegroundColor Yellow
$capeScript = Join-Path $root 'fetch-shiller.ps1'
if (Test-Path -LiteralPath $capeScript) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $capeScript
}

# 5. Commit + push
Write-Host ""
Write-Host "[5/5] Commit + push..." -ForegroundColor Yellow
$forceFiles = @('data.json','fedwatch.json','shiller.json','fx-naver-snapshot.json','capmkt-freeze.json')
& git -C $root add -f $forceFiles 2>&1 | Out-Null
& git -C $root add -A 2>&1 | Out-Null

$diff = & git -C $root diff --cached --name-only 2>&1
if ([string]::IsNullOrWhiteSpace($diff)) {
    Write-Host "  No changes -- nothing to commit." -ForegroundColor DarkGray
} else {
    Write-Host "  Staged:" -ForegroundColor DarkGray
    & git -C $root status --short | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    & git -C $root commit -m "KR-close deploy $ts" 2>&1 | Out-Null
    & git -C $root pull --rebase --autostash origin main 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { & git -C $root rebase --abort 2>&1 | Out-Null }
    & git -C $root push origin main 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  pushed -> Cloudflare auto-deploys in ~1-2 min" -ForegroundColor Green
    } else {
        Write-Host "  PUSH FAILED -- run .\sync-repo.ps1 then retry" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Done." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Cyan
