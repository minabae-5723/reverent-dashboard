# =============================================================
#  Bi-directional repo sync  (Windows task: ReverentDashboard-RepoSync)
#
#  Keeps the dashboard repo in sync across the two work PCs via
#  origin/main. Hardened 2026-06-15 after cross-PC changes stopped
#  propagating:
#    * old version exit-1'd in the middle of a failed rebase and then
#      stayed stuck forever (every later run hit "rebase in progress").
#    * old version only PUSHED user-state.json, so any other committed
#      work waited for a manual push that often never happened.
#
#  Now:
#    0. self-heal — abort any half-finished rebase/merge from a crash
#    1. fetch
#    2. INBOUND  — replay onto origin; on file conflict keep origin's
#                  copy of generated snapshots (local re-deploys anyway)
#    3. user-state.json — auto-commit live dashboard edits
#    4. OUTBOUND — push ALL committed local work origin lacks (not just
#                  user-state). Real code edits still need a manual
#                  `git commit`, but once committed they now ship here.
# =============================================================
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

# Never block on an interactive credential / GCM prompt. When this runs as the
# RepoSync scheduled task (non-interactive session), Git Credential Manager
# would try to pop a UI it can't render and HANG until Task Scheduler killed it
# at the 5-min limit (exit 0xC000013A) — so user-state never got pushed and
# edits "didn't reflect". Cached creds still work; if they ever expire, git now
# fails fast (logged) instead of hanging.
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE = 'Never'

# Register the user-state.json entry-union merge driver (per-PC, idempotent)
# so cross-PC merges never clobber manual inputs or leave conflict markers.
# Use a repo-ROOT-RELATIVE script path: git runs the driver from the worktree
# top, so this dodges the non-ASCII / spaced absolute-path quoting that
# otherwise stops git from launching it.
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

# ── 2. INBOUND: integrate other-PC commits ──
#     Done BEFORE the user-state commit so there's nothing local to
#     collide. On conflict, prefer origin's copy (--strategy-option=ours
#     during a rebase favours the upstream side) — never get stuck.
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

# ── 3. Auto-commit a modified user-state.json (live comments / valuations) ──
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

# ── 4. OUTBOUND: push every committed local commit origin doesn't have yet ──
$ahead = & git -C $root rev-list --count origin/main..HEAD 2>&1
if (($ahead -match '^\d+$') -and ([int]$ahead -gt 0)) {
    & git -C $root push origin main 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("Pushed " + $ahead + " commit(s) to origin/main") -ForegroundColor Green
    } else {
        Write-Host "push rejected (origin moved) -- next run rebases & retries" -ForegroundColor Yellow
    }
}
