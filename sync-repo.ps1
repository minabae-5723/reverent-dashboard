# =============================================================
#  Bi-directional repo sync  (Windows task: ReverentDashboard-RepoSync, 5 min)
#
#  INBOUND  : pull other-PC commits (reliable — fetch/pull work in the task).
#  OUTBOUND : push committed local work origin lacks. NOTE: user-state edits are
#             pushed immediately by serve.ps1's /save-state handler (which runs
#             in the interactive session where git push is reliable); the
#             scheduled task's own push is only a backstop because a windowless
#             task occasionally exits 0xC000013A on push. So RepoSync mainly
#             keeps this PC pulled-up-to-date.
# =============================================================
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

# Never block on an interactive git/GCM credential prompt.
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE = 'Never'

# Register the user-state.json entry-union merge driver (per-PC, idempotent).
& git -C $root config merge.userstate.name 'user-state.json entry-union' 2>&1 | Out-Null
& git -C $root config merge.userstate.driver 'powershell -NoProfile -ExecutionPolicy Bypass -File merge-userstate.ps1 %O %A %B' 2>&1 | Out-Null

# ── 0. Self-heal: clear a half-finished rebase/merge left by a crashed run ──
foreach ($d in '.git\rebase-merge', '.git\rebase-apply') {
    if (Test-Path (Join-Path $root $d)) { & git -C $root rebase --abort 2>&1 | Out-Null }
}
if (Test-Path (Join-Path $root '.git\MERGE_HEAD')) { & git -C $root merge --abort 2>&1 | Out-Null }

# ── 1. Fetch latest from origin/main ──
& git -C $root fetch origin main 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "fetch failed" -ForegroundColor Yellow; exit 1 }

# ── 2. INBOUND: integrate other-PC commits (origin wins generated-file conflicts) ──
$behind = & git -C $root rev-list --count HEAD..origin/main 2>&1
if (($behind -match '^\d+$') -and ([int]$behind -gt 0)) {
    & git -C $root pull --rebase --autostash origin main 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        & git -C $root rebase --abort 2>&1 | Out-Null
        & git -C $root pull --rebase --autostash --strategy-option=ours origin main 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            & git -C $root rebase --abort 2>&1 | Out-Null
            Write-Host "inbound conflict unresolved -- will retry next run" -ForegroundColor Yellow
        } else {
            Write-Host "Pulled (conflicts auto-resolved to origin)" -ForegroundColor Green
        }
    } else {
        Write-Host ("Pulled " + $behind + " commit(s) from origin/main") -ForegroundColor Green
    }
}

# ── 3. Auto-commit a modified user-state.json (backstop; serve.ps1 usually beat us) ──
#     Skip if a prior stash-pop left conflict markers — never commit those.
$us = & git -C $root status --porcelain user-state.json 2>&1
if (-not [string]::IsNullOrWhiteSpace($us)) {
    $hasMarkers = $false
    if (Test-Path (Join-Path $root 'user-state.json')) {
        $hasMarkers = [bool](Select-String -Path (Join-Path $root 'user-state.json') -Pattern '^(<<<<<<<|>>>>>>>)' -Quiet)
    }
    if (-not $hasMarkers) {
        $ts = '{0:yyyy-MM-dd HH:mm}' -f (Get-Date)
        & git -C $root add user-state.json 2>&1 | Out-Null
        & git -C $root commit -m "Auto-sync user-state $ts" 2>&1 | Out-Null
    } else {
        Write-Host "user-state.json has conflict markers -- skipping commit" -ForegroundColor Yellow
    }
}

# ── 4. OUTBOUND: push committed local commits origin doesn't have yet ──
$ahead = & git -C $root rev-list --count origin/main..HEAD 2>&1
if (($ahead -match '^\d+$') -and ([int]$ahead -gt 0)) {
    & git -C $root push origin main 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("Pushed " + $ahead + " commit(s) to origin/main") -ForegroundColor Green
    } else {
        Write-Host "push rejected/failed -- serve.ps1 push-on-save covers user-state; next run retries" -ForegroundColor Yellow
    }
}
