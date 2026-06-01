# =============================================================
#  user-state.json auto-sync
#
#  Runs every 5 minutes via Windows scheduled task. If user-state.json
#  has uncommitted changes (user edited comments/valuations between the
#  daily 07:00 deploy cycles), commits + pushes ONLY that file so
#  Cloudflare reflects the latest saves within ~5 minutes.
#
#  - Uses `git commit --only` to commit just user-state.json, leaving
#    other modified files (calendar/data/etc.) for deploy-snapshot.ps1.
#  - Silently exits if nothing changed.
#  - Pulls --rebase before pushing to avoid conflicts with concurrent deploys.
# =============================================================
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

$file = 'user-state.json'
$status = & git -C $root status --porcelain $file 2>&1
if ([string]::IsNullOrWhiteSpace($status)) {
    # No changes — quiet exit
    exit 0
}

$ts = (Get-Date).ToString('yyyy-MM-dd HH:mm')

# Commit only this one file (ignores other modified files in the tree)
& git -C $root commit --only $file -m "Auto-sync user-state $ts" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "user-state commit failed (LASTEXITCODE=$LASTEXITCODE)" -ForegroundColor Yellow
    exit 1
}

# Rebase + push
& git -C $root pull --rebase 2>&1 | Out-Null
& git -C $root push 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Auto-sync user-state.json pushed @ $ts" -ForegroundColor Green
} else {
    Write-Host "push failed (LASTEXITCODE=$LASTEXITCODE)" -ForegroundColor Red
}
