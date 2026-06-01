# =============================================================
#  Bi-directional repo sync (every 5 min via Windows scheduled task)
#
#  PURPOSE
#  Keep the dashboard repo in sync across multiple PCs so that code OR
#  data edits on PC-A reach PC-B within ~5 minutes (and vice versa).
#
#  INBOUND (pull from origin):
#    - Always fetch + fast-forward / rebase any commits from other PCs
#    - Picks up: code changes (app.js, .ps1), data refreshes from
#      daily-deploy on the OTHER PC, news/market .md files, etc.
#
#  OUTBOUND (push to origin):
#    - Auto-commit + push user-state.json if modified (user comments /
#      valuations / FIX clicks). Other data files (data.json etc.) are
#      handled by deploy-snapshot.ps1; code changes stay manual.
#
#  Replaces the earlier sync-user-state.ps1.
# =============================================================
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

# ── 1. Fetch latest from origin/main ──
& git -C $root fetch origin main 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "fetch failed" -ForegroundColor Yellow
    exit 1
}

# ── 2. INBOUND: pull if origin has new commits ──
$ahead = & git -C $root rev-list --count HEAD..origin/main 2>&1
$aheadInt = 0
if ($ahead -match '^\d+$') { $aheadInt = [int]$ahead }

if ($aheadInt -gt 0) {
    # rebase --autostash handles uncommitted local changes gracefully
    $pullOut = & git -C $root pull --rebase --autostash origin main 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("Pulled " + $aheadInt + " commit(s) from origin/main") -ForegroundColor Green
    } else {
        Write-Host ("pull failed: " + ($pullOut -join ' ')) -ForegroundColor Red
        exit 1
    }
}

# ── 3. OUTBOUND: auto-commit + push user-state.json if modified ──
$userStateStatus = & git -C $root status --porcelain user-state.json 2>&1
if (-not [string]::IsNullOrWhiteSpace($userStateStatus)) {
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    & git -C $root commit --only user-state.json -m "Auto-sync user-state $ts" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        # pull-rebase once more in case origin moved while we were committing
        & git -C $root pull --rebase --autostash 2>&1 | Out-Null
        & git -C $root push 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host ("Pushed user-state.json @ " + $ts) -ForegroundColor Green
        } else {
            Write-Host "push failed" -ForegroundColor Red
        }
    }
}
