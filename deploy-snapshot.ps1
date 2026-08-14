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

# Never block on an interactive git/GCM credential prompt — when this runs as a
# scheduled task and GCM needs a token refresh it would hang until killed
# (0xC000013A). Cached creds still work; otherwise git fails fast (logged).
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE = 'Never'

# Register the user-state.json entry-union merge driver (per-PC, idempotent).
# Repo-root-relative path — git runs the driver from the worktree top.
& git -C $root config merge.userstate.name 'user-state.json entry-union' 2>&1 | Out-Null
& git -C $root config merge.userstate.driver 'powershell -NoProfile -ExecutionPolicy Bypass -File merge-userstate.ps1 %O %A %B' 2>&1 | Out-Null

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Deploy Snapshot - Reverent Dashboard" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# Folders that have YYYY-MM-DD.md files served as JSON-indexed lists.
# Each gets an `index.json` regenerated from its .md file basenames.
$INDEXED_FOLDERS = @('news', 'market', 'deals', 'daily-report')

# 0. Sync from origin/main first so other-PC commits don't conflict on push.
#    Was --ff-only (silently skipped on any divergence, then the final push
#    was rejected and this PC's data never reached origin/Cloudflare). Now a
#    real rebase that self-aborts instead of leaving the repo half-merged.
Write-Host "[0/5] Sync from origin/main..." -ForegroundColor Yellow
foreach ($d in '.git\rebase-merge', '.git\rebase-apply') {
    if (Test-Path (Join-Path $root $d)) { & git -C $root rebase --abort 2>&1 | Out-Null }
}
# Discard local edits to disposable snapshots (all regenerated below) so a
# day-old dirty data.json can't block the pull on a cross-day / cross-PC run.
$dispose0 = @('data.json','calendar.json','calendar-week.json','calendar-next-week.json',
              'market-update-frozen.json','trade.json','shiller.json','fedwatch.json',
              'fx-naver-snapshot.json','capmkt-freeze.json','peer.json')
foreach ($f in $dispose0) { if (Test-Path (Join-Path $root $f)) { & git -C $root checkout -- $f 2>&1 | Out-Null } }
$pullOut = & git -C $root pull --rebase --autostash origin main 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  $pullOut" -ForegroundColor DarkGray
} else {
    & git -C $root rebase --abort 2>&1 | Out-Null
    Write-Host "  initial pull conflicted -- aborted, reconciled at push: $pullOut" -ForegroundColor Yellow
}

# Helper: run a fetch script only if present (AV may quarantine scripts on
# some PCs); if missing, restore from HEAD before continuing.
function Invoke-FetchScript {
    param([string]$Name, [string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "  $Name missing -- attempting checkout from HEAD..." -ForegroundColor Yellow
        & git -C $root checkout HEAD -- $Name 2>&1 | Out-Null
    }
    if (Test-Path -LiteralPath $Path) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $Path
    } else {
        Write-Host "  $Name still missing (AV blocked?) -- skipping" -ForegroundColor Red
    }
}

# 1. Refresh market data (Yahoo Finance)
Write-Host ""
Write-Host "[1/5] Refresh market data..." -ForegroundColor Yellow
Invoke-FetchScript -Name 'refresh.ps1' -Path (Join-Path $root 'refresh.ps1')

# 2. Refresh calendar (Investing.com -- may fail if Cloudflare blocking)
#
# MONDAY-MORNING FREEZE (user rule, 2026-08-10): on Monday before noon the
# Macro Economy board must keep the weekend's frozen state -- last week's
# Review plus this week's Preview -- because the Monday Brief is written
# against last week. Skip the calendar refresh entirely in that window so
# nothing can re-freeze or roll it; every other deploy path is unchanged.
# The roll is handled by the daily-weekly-calendar task, which runs Tue-Fri.
Write-Host ""
$nowLocal = Get-Date
$mondayFreeze = ($nowLocal.DayOfWeek -eq [DayOfWeek]::Monday -and $nowLocal.Hour -lt 12)
if ($mondayFreeze) {
    Write-Host "[2/5] Calendar refresh SKIPPED - Monday morning freeze" -ForegroundColor Cyan
    Write-Host "        weekend frozen state kept (last week Review / this week Preview)" -ForegroundColor DarkGray
    $frozenPath = Join-Path $root 'market-update-frozen.json'
    if (Test-Path $frozenPath) {
        try {
            $fz = Get-Content -LiteralPath $frozenPath -Raw -Encoding UTF8 | ConvertFrom-Json
            Write-Host ("        reviewRange=" + $fz.reviewRange + "  previewRange=" + $fz.previewRange) -ForegroundColor DarkGray
        } catch {}
    }
} else {
    Write-Host "[2/5] Refresh calendar data..." -ForegroundColor Yellow
    Invoke-FetchScript -Name 'fetch-calendar.ps1' -Path (Join-Path $root 'fetch-calendar.ps1')
}

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

# 2.75. Refresh FX (Naver Seoul-close basis — overrides Yahoo NY-close)
Write-Host ""
Write-Host "[2.75/5] Refresh FX (Naver Seoul-close)..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'fetch-naver-fx.ps1')

# 2.8. Refresh FedWatch (Fed rate probability)
Write-Host ""
Write-Host "[2.8/5] Refresh FedWatch (Fed rate probability)..." -ForegroundColor Yellow
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'fetch-fedwatch.ps1')

# 2.85. Refresh Peer table (Yahoo + Naver) — skip Monday morning
#        Monday Brief uses the Friday-frozen peer data, so re-fetching before
#        KOSPI opens would overwrite it with stale pre-market values.
if ($mondayFreeze) {
    Write-Host ""
    Write-Host "[2.85/5] Peer table refresh SKIPPED - Monday morning freeze" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "[2.85/5] Refresh Peer table (Yahoo + Naver)..." -ForegroundColor Yellow
    $peerScript = Join-Path $root 'fetch-peer.ps1'
    if (Test-Path -LiteralPath $peerScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $peerScript
    } else {
        Write-Host "  fetch-peer.ps1 missing -- skipping" -ForegroundColor Yellow
    }
}

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
    # AV-safety: restore any code files that may have been quarantined during
    # the fetch phase. Without this, `git add -A` would stage their deletion
    # and we'd accidentally push removals to the repo.
    $criticalCodeFiles = @(
        'refresh.ps1', 'fetch-calendar.ps1', 'fetch-shiller.ps1', 'fetch-fedwatch.ps1',
        'fetch-trade.ps1', 'fetch-dart-valuation.ps1', 'fetch-ipo.ps1', 'fetch-peer.ps1',
        'fetch-cd91-history.ps1', 'fetch-cd91.ps1',
        'serve.ps1', 'app.js', 'macro.js', 'chat.js', 'index.html', 'styles.css'
    )
    foreach ($f in $criticalCodeFiles) {
        $fp = Join-Path $root $f
        if (-not (Test-Path -LiteralPath $fp)) {
            & git -C $root cat-file -e "HEAD:$f" 2>$null
            $headHas = ($LASTEXITCODE -eq 0)
            if ($headHas) {
                Write-Host "  ! $f missing on disk -- restoring from HEAD (AV?)" -ForegroundColor Yellow
                & git -C $root checkout HEAD -- $f 2>&1 | Out-Null
            }
        }
    }

    # Force-add data snapshots (gitignored normally) + all index.json files
    $forceFiles = @('data.json', 'calendar.json', 'calendar-week.json', 'calendar-next-week.json', 'market-update-frozen.json', 'trade.json', 'shiller.json', 'fedwatch.json', 'fx-naver-snapshot.json', 'capmkt-freeze.json', 'user-state.json', 'peer.json') +
                  ($INDEXED_FOLDERS | ForEach-Object { "$_/index.json" })
    git add -f $forceFiles 2>&1 | Out-Null
    # Add anything else (new .md files, code changes, etc.)
    git add -A 2>&1 | Out-Null

    Write-Host "  Staged:" -ForegroundColor DarkGray
    git status --short | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    # 4.5. GUARD: never commit unresolved git conflict markers.
    #      A stash-pop conflict left <<<<<<< / >>>>>>> markers in
    #      deals/2026-06-12.md and `git add -A` swept them into a deploy
    #      commit that reached the live site (2026-06-13). Scan staged text
    #      files and abort BEFORE committing if markers are present. Only the
    #      start/end markers are checked (======= alone would false-positive
    #      on markdown setext headings).
    $textExt = '\.(md|js|html|css|json|ps1|txt)$'
    $stagedFiles = @(git diff --cached --name-only --diff-filter=ACM 2>$null | Where-Object { $_ -match $textExt })
    $conflicted = @()
    foreach ($rel in $stagedFiles) {
        $blob = git show ":$rel" 2>$null
        if ($LASTEXITCODE -ne 0) { continue }
        if ($blob | Where-Object { $_ -match '^(<<<<<<<|>>>>>>>)' }) {
            $conflicted += $rel
        }
    }
    if ($conflicted.Count -gt 0) {
        Write-Host ""
        Write-Host "  !! ABORT: unresolved conflict markers in staged file(s):" -ForegroundColor Red
        $conflicted | ForEach-Object { Write-Host "       $_" -ForegroundColor Red }
        Write-Host "  Remove the <<<<<<< / ======= / >>>>>>> markers, then re-run deploy." -ForegroundColor Red
        git reset -q 2>&1 | Out-Null
        exit 1
    }

    $timestamp = '{0:yyyy-MM-dd HH:mm}' -f (Get-Date)
    git commit -m "Deploy snapshot $timestamp" 2>&1 | Tee-Object -Variable commitOut | Out-Null
    Write-Host "  Commit: $($commitOut | Select-Object -Last 1)" -ForegroundColor DarkGray

    # Robust publish: reconcile with origin (our fresh snapshot wins file
    # conflicts via --strategy-option=theirs) then push, retrying so a
    # concurrent push from the other PC can't strand this deploy locally.
    # (Was a single `git push`, silently rejected on divergence.)
    Write-Host "  Publishing to origin/main..." -ForegroundColor DarkGray
    $published = $false
    for ($attempt = 1; $attempt -le 3 -and -not $published; $attempt++) {
        & git -C $root pull --rebase --autostash --strategy-option=theirs origin main 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { & git -C $root rebase --abort 2>&1 | Out-Null }
        & git -C $root push origin main 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $published = $true; break }
        Write-Host ("    push attempt $attempt rejected, retrying...") -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }
    if ($published) {
        Write-Host "    pushed -> Cloudflare auto-deploys in ~1-2 min" -ForegroundColor Green
    } else {
        Write-Host "    PUSH FAILED after 3 attempts -- run .\sync-repo.ps1 then retry" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Done. Cloudflare Pages will auto-deploy" -ForegroundColor Green
Write-Host " within 1-2 minutes." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Cyan
