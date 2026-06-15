# =============================================================
#  Reverent Partners Dashboard - All-in-one launcher
#  - Serves files on http://localhost:8000
#  - Runs refresh.ps1 every 60 sec in background
#  - Opens browser
# =============================================================
param([int]$Port = 8000)

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
$refreshScript  = Join-Path $root 'refresh.ps1'
$calendarScript = Join-Path $root 'fetch-calendar.ps1'
$configPath     = Join-Path $root 'config.json'
$promptPath     = Join-Path $root 'system-prompt.txt'
$dataPath       = Join-Path $root 'data.json'
$calendarPath   = Join-Path $root 'calendar.json'

# Read a UTF-8 file (with or without BOM) into a string
function Read-Utf8File {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
}

# Read JSON config; returns $null if missing or unparseable
function Read-Config {
    $raw = Read-Utf8File $configPath
    if (-not $raw) { return $null }
    try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

function Get-JsonError {
    param([string]$Message)
    $obj = @{ error = $Message } | ConvertTo-Json -Compress
    return $obj
}

# Build the Anthropic /v1/messages request and call it. Returns hashtable
# with: ok (bool), response (string), usage (object), error (string).
function Invoke-AnthropicChat {
    param([array]$Messages)

    $cfg = Read-Config
    if (-not $cfg -or -not $cfg.ANTHROPIC_API_KEY -or $cfg.ANTHROPIC_API_KEY -like '*PASTE-YOUR-KEY-HERE*') {
        return @{
            ok    = $false
            error = "config.json missing or API key not set. Copy config.json.example to config.json and paste your Anthropic API key from https://console.anthropic.com/"
        }
    }

    $apiKey    = $cfg.ANTHROPIC_API_KEY
    $model     = if ($cfg.MODEL)      { $cfg.MODEL }      else { 'claude-opus-4-7' }
    $maxTokens = if ($cfg.MAX_TOKENS) { [int]$cfg.MAX_TOKENS } else { 2048 }

    $promptBase = Read-Utf8File $promptPath
    if (-not $promptBase) { $promptBase = 'You are a market analysis assistant.' }

    # Bundle current dashboard data into the system prompt for grounded answers
    $marketJson   = Read-Utf8File $dataPath
    $calendarJson = Read-Utf8File $calendarPath

    $contextBlocks = @()
    $contextBlocks += $promptBase.TrimEnd()
    if ($marketJson) {
        $contextBlocks += "`n## [현재 시장 데이터 — data.json]`n``````json`n$marketJson`n``````"
    }
    if ($calendarJson) {
        $contextBlocks += "`n## [오늘의 경제 캘린더 — calendar.json]`n``````json`n$calendarJson`n``````"
    }
    $systemText = ($contextBlocks -join "`n")

    # System as array with cache_control on the last block → prompt caching
    # (stable across requests; saves ~90% on input tokens for subsequent messages)
    $systemArray = @(
        @{
            type          = 'text'
            text          = $systemText
            cache_control = @{ type = 'ephemeral' }
        }
    )

    # Build messages payload (user/assistant alternating)
    $apiMessages = @()
    foreach ($m in $Messages) {
        $role = [string]$m.role
        $content = [string]$m.content
        if ($role -eq 'user' -or $role -eq 'assistant') {
            $apiMessages += @{ role = $role; content = $content }
        }
    }

    $body = @{
        model      = $model
        max_tokens = $maxTokens
        system     = $systemArray
        messages   = $apiMessages
    } | ConvertTo-Json -Depth 20 -Compress

    $headers = @{
        'x-api-key'         = $apiKey
        'anthropic-version' = '2023-06-01'
        'Content-Type'      = 'application/json'
    }

    try {
        $resp = Invoke-RestMethod -Uri 'https://api.anthropic.com/v1/messages' `
            -Method POST -Headers $headers -Body $body -TimeoutSec 90

        # Extract text from response content blocks
        $textOut = ''
        if ($resp.content) {
            foreach ($block in $resp.content) {
                if ($block.type -eq 'text') { $textOut += $block.text }
            }
        }

        return @{
            ok       = $true
            response = $textOut
            usage    = $resp.usage
            model    = $resp.model
            stop     = $resp.stop_reason
        }
    } catch {
        $msg = $_.Exception.Message
        # Try to extract Anthropic error body
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            if ($stream) {
                $reader = New-Object System.IO.StreamReader($stream)
                $errBody = $reader.ReadToEnd()
                if ($errBody) { $msg = "$msg | $errBody" }
            }
        } catch {}
        return @{ ok = $false; error = $msg }
    }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Reverent Partners - Live Market Dashboard" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# ── 0. Robust sync with origin/main (resilient to cross-day / cross-PC drift) ──
#     The old `pull --ff-only` silently FAILED whenever this PC's branch had
#     drifted (yesterday's local commit, or a stale uncommitted data.json that
#     "would be overwritten by merge") — so launching on a different PC the
#     next day quietly served day-old LOCAL state. Now: self-heal any stuck
#     rebase, discard local edits to DISPOSABLE generated snapshots (they are
#     regenerated in step 1 below, so losing them is safe and unblocks the
#     pull), then a rebase-pull that can't get stuck. user-state.json, code,
#     and .md content are NEVER discarded.
Write-Host "[0/3] Sync from origin/main..." -ForegroundColor Yellow
try {
    $gitDir = Join-Path $root '.git'
    if (Test-Path -LiteralPath $gitDir) {
        foreach ($d in '.git\rebase-merge', '.git\rebase-apply') {
            if (Test-Path (Join-Path $root $d)) { & git -C $root rebase --abort 2>&1 | Out-Null }
        }
        if (Test-Path (Join-Path $root '.git\MERGE_HEAD')) { & git -C $root merge --abort 2>&1 | Out-Null }
        & git -C $root fetch origin main 2>&1 | Out-Null
        $disposable = @('data.json','calendar.json','calendar-week.json','calendar-next-week.json',
                        'market-update-frozen.json','trade.json','shiller.json','fedwatch.json',
                        'fx-naver-snapshot.json','capmkt-freeze.json')
        foreach ($f in $disposable) {
            if (Test-Path (Join-Path $root $f)) { & git -C $root checkout -- $f 2>&1 | Out-Null }
        }
        & git -C $root pull --rebase --autostash origin main 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            & git -C $root rebase --abort 2>&1 | Out-Null
            & git -C $root pull --rebase --autostash --strategy-option=ours origin main 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                & git -C $root rebase --abort 2>&1 | Out-Null
                Write-Host "  sync conflict -- serving local; run .\sync-repo.ps1 to reconcile" -ForegroundColor Yellow
            } else {
                Write-Host "  synced with origin/main (conflicts auto-resolved to origin)" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "  synced with origin/main" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  (not a git repo -- skipping pull)" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  pull error (continuing): $($_.Exception.Message)" -ForegroundColor DarkGray
}
Write-Host ""

# ── 1. Initial data fetch (synchronous, so page has data on first load) ──
Write-Host "[1/3] Initial data fetch (Yahoo + Investing)..." -ForegroundColor Yellow
if (Test-Path -LiteralPath $refreshScript) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $refreshScript
} else {
    Write-Host "  refresh.ps1 missing on this PC (likely AV-quarantined) — skipping market fetch" -ForegroundColor Yellow
    Write-Host "  Using data.json from last commit on origin/main" -ForegroundColor DarkGray
}
if (Test-Path -LiteralPath $calendarScript) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $calendarScript
} else {
    Write-Host "  fetch-calendar.ps1 missing — skipping calendar fetch" -ForegroundColor Yellow
}
Write-Host ""

# ── 2. (Manual mode) Background refresh loops disabled ──
# External API fetches (Yahoo Finance + Investing.com) now happen ONLY on:
#   - Initial server start (step 1 above)
#   - User clicking the ↻ refresh button (triggers /refresh endpoint)
# This avoids hitting rate limits / Cloudflare anti-bot protection.
Write-Host "[2/3] Manual refresh mode (no background loops)" -ForegroundColor Yellow
Write-Host "  Use the ↻ button in the dashboard to fetch fresh data on demand" -ForegroundColor DarkGray
Write-Host ""
$marketProc = $null
$calendarProc = $null

# ── 3. HTTP server ──
$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
}

$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
} catch {
    Write-Host "ERROR: Failed to bind port $Port - $($_.Exception.Message)" -ForegroundColor Red
    if ($refreshProc -and -not $refreshProc.HasExited) {
        Stop-Process -Id $refreshProc.Id -Force -ErrorAction SilentlyContinue
    }
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "[3/3] HTTP server: $prefix" -ForegroundColor Green
Write-Host ""
Write-Host "  --> Opening browser..." -ForegroundColor Cyan
Write-Host "  --> Press Ctrl+C in this window to stop everything" -ForegroundColor Yellow
Write-Host ""

Start-Sleep -Milliseconds 500
Start-Process $prefix

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $req = $context.Request
        $res = $context.Response

        try {
            $relPath = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath)
            if ($relPath -eq '/' -or [string]::IsNullOrEmpty($relPath)) {
                $relPath = '/index.html'
            }

            $stamp = (Get-Date).ToString('HH:mm:ss')

            # /news/list — returns available news clipping dates
            if ($relPath -eq '/news/list') {
                $newsDir = Join-Path $root 'news'
                $dates = @()
                if (Test-Path $newsDir) {
                    $dates = Get-ChildItem -LiteralPath $newsDir -Filter '*.md' -ErrorAction SilentlyContinue |
                        ForEach-Object { $_.BaseName } |
                        Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}$' } |
                        Sort-Object -Descending
                }
                $msg = @{ dates = @($dates) } | ConvertTo-Json -Compress
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
                $res.ContentType = 'application/json; charset=utf-8'
                $res.Headers.Add('Cache-Control', 'no-store')
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                Write-Host "[$stamp] GET /news/list -> $($dates.Count) dates" -ForegroundColor DarkGray
                $res.Close()
                continue
            }

            # /market/list — returns available market brief dates
            if ($relPath -eq '/market/list') {
                $marketDir = Join-Path $root 'market'
                $dates = @()
                if (Test-Path $marketDir) {
                    $dates = Get-ChildItem -LiteralPath $marketDir -Filter '*.md' -ErrorAction SilentlyContinue |
                        ForEach-Object { $_.BaseName } |
                        Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}$' } |
                        Sort-Object -Descending
                }
                $msg = @{ dates = @($dates) } | ConvertTo-Json -Compress
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
                $res.ContentType = 'application/json; charset=utf-8'
                $res.Headers.Add('Cache-Control', 'no-store')
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                Write-Host "[$stamp] GET /market/list -> $($dates.Count) dates" -ForegroundColor DarkGray
                $res.Close()
                continue
            }

            # /deals/list — returns available weekly deal flow dates (Friday end-of-week)
            if ($relPath -eq '/deals/list') {
                $dealsDir = Join-Path $root 'deals'
                $dates = @()
                if (Test-Path $dealsDir) {
                    $dates = Get-ChildItem -LiteralPath $dealsDir -Filter '*.md' -ErrorAction SilentlyContinue |
                        ForEach-Object { $_.BaseName } |
                        Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}$' } |
                        Sort-Object -Descending
                }
                $msg = @{ dates = @($dates) } | ConvertTo-Json -Compress
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
                $res.ContentType = 'application/json; charset=utf-8'
                $res.Headers.Add('Cache-Control', 'no-store')
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                Write-Host "[$stamp] GET /deals/list -> $($dates.Count) weeks" -ForegroundColor DarkGray
                $res.Close()
                continue
            }

            # /chat — POST { messages: [...] } → Anthropic API
            if ($relPath -eq '/chat') {
                if ($req.HttpMethod -ne 'POST') {
                    $res.StatusCode = 405
                    $errMsg = Get-JsonError 'POST required'
                    $errBytes = [System.Text.Encoding]::UTF8.GetBytes($errMsg)
                    $res.ContentType = 'application/json; charset=utf-8'
                    $res.OutputStream.Write($errBytes, 0, $errBytes.Length)
                    $res.Close()
                    continue
                }

                # Read POST body as UTF-8
                $reader = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
                $bodyStr = $reader.ReadToEnd()
                $reader.Close()

                $msgs = @()
                try {
                    $parsed = $bodyStr | ConvertFrom-Json
                    if ($parsed.messages) { $msgs = $parsed.messages }
                } catch {
                    $res.StatusCode = 400
                    $errMsg = Get-JsonError 'Invalid JSON body'
                    $errBytes = [System.Text.Encoding]::UTF8.GetBytes($errMsg)
                    $res.ContentType = 'application/json; charset=utf-8'
                    $res.OutputStream.Write($errBytes, 0, $errBytes.Length)
                    $res.Close()
                    continue
                }

                if (-not $msgs -or $msgs.Count -eq 0) {
                    $res.StatusCode = 400
                    $errMsg = Get-JsonError 'messages array is empty'
                    $errBytes = [System.Text.Encoding]::UTF8.GetBytes($errMsg)
                    $res.ContentType = 'application/json; charset=utf-8'
                    $res.OutputStream.Write($errBytes, 0, $errBytes.Length)
                    $res.Close()
                    continue
                }

                Write-Host "[$stamp] >>> /chat (msgs=$($msgs.Count))..." -ForegroundColor Magenta
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $result = Invoke-AnthropicChat -Messages $msgs
                $sw.Stop()

                if ($result.ok) {
                    $out = @{
                        response = $result.response
                        usage    = $result.usage
                        model    = $result.model
                        stop     = $result.stop
                        ms       = $sw.ElapsedMilliseconds
                    } | ConvertTo-Json -Depth 10 -Compress
                    $outBytes = [System.Text.Encoding]::UTF8.GetBytes($out)
                    $res.ContentType = 'application/json; charset=utf-8'
                    $res.Headers.Add('Cache-Control', 'no-store')
                    $res.ContentLength64 = $outBytes.Length
                    $res.OutputStream.Write($outBytes, 0, $outBytes.Length)
                    $cacheRead = if ($result.usage.cache_read_input_tokens) { $result.usage.cache_read_input_tokens } else { 0 }
                    $cacheWrite = if ($result.usage.cache_creation_input_tokens) { $result.usage.cache_creation_input_tokens } else { 0 }
                    Write-Host ("[$stamp] <<< /chat OK in {0}ms (in={1} out={2} cache_r={3} cache_w={4})" -f `
                        $sw.ElapsedMilliseconds, $result.usage.input_tokens, $result.usage.output_tokens, $cacheRead, $cacheWrite) -ForegroundColor Magenta
                } else {
                    $res.StatusCode = 500
                    $errMsg = Get-JsonError $result.error
                    $errBytes = [System.Text.Encoding]::UTF8.GetBytes($errMsg)
                    $res.ContentType = 'application/json; charset=utf-8'
                    $res.OutputStream.Write($errBytes, 0, $errBytes.Length)
                    Write-Host "[$stamp] !!! /chat FAILED: $($result.error)" -ForegroundColor Red
                }
                $res.Close()
                continue
            }

            # Save valuation entry to valuations.json (POST)
            #   Body: { key: "...", payload: {...} }
            # The whole valuations.json is then deployable, persisting Fix
            # values across browsers / Cloudflare reloads.
            if ($relPath -eq '/save-state') {
                if ($req.HttpMethod -ne 'POST') {
                    $res.StatusCode = 405
                    $errMsg = Get-JsonError 'POST required'
                    $errBytes = [System.Text.Encoding]::UTF8.GetBytes($errMsg)
                    $res.ContentType = 'application/json; charset=utf-8'
                    $res.OutputStream.Write($errBytes, 0, $errBytes.Length)
                    $res.Close()
                    continue
                }

                $reader = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
                $bodyStr = $reader.ReadToEnd()
                $reader.Close()

                $valPath = Join-Path $root 'user-state.json'
                try {
                    $body = $bodyStr | ConvertFrom-Json
                    if (-not $body.key) { throw 'missing key' }
                    # Accept either {key, value} (new) or {key, payload} (legacy)
                    $newValue = if ($body.PSObject.Properties.Name -contains 'value') { $body.value } else { $body.payload }

                    # Load existing valuations.json (or create skeleton)
                    if (Test-Path -LiteralPath $valPath) {
                        $existing = ([System.IO.File]::ReadAllText($valPath, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
                    } else {
                        $existing = [PSCustomObject]@{ version = 1; updated = ''; entries = [PSCustomObject]@{} }
                    }
                    if (-not $existing.entries) { $existing | Add-Member -NotePropertyName entries -NotePropertyValue ([PSCustomObject]@{}) -Force }

                    # Convert entries to hashtable for easy mutation (PSCustomObject is immutable-ish)
                    $entriesHash = @{}
                    if ($existing.entries.PSObject.Properties) {
                        foreach ($p in $existing.entries.PSObject.Properties) { $entriesHash[$p.Name] = $p.Value }
                    }

                    if ($null -ne $newValue) {
                        $entriesHash[$body.key] = $newValue
                    } else {
                        # null = delete entry (matches Reset semantics)
                        $entriesHash.Remove($body.key) | Out-Null
                    }

                    $existing.entries = [PSCustomObject]$entriesHash
                    $existing.updated = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

                    $json = $existing | ConvertTo-Json -Depth 10
                    [System.IO.File]::WriteAllText($valPath, $json, (New-Object System.Text.UTF8Encoding($false)))

                    $msg = "{`"ok`":true,`"key`":`"$($body.key)`",`"entries`":$($entriesHash.Count)}"
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
                    $res.ContentType = 'application/json; charset=utf-8'
                    $res.Headers.Add('Cache-Control', 'no-store')
                    $res.ContentLength64 = $bytes.Length
                    $res.OutputStream.Write($bytes, 0, $bytes.Length)
                    Write-Host "[$stamp] >>> /save-state key=$($body.key) (total entries=$($entriesHash.Count))" -ForegroundColor Magenta
                } catch {
                    $res.StatusCode = 400
                    $errMsg = Get-JsonError "save failed: $($_.Exception.Message)"
                    $errBytes = [System.Text.Encoding]::UTF8.GetBytes($errMsg)
                    $res.ContentType = 'application/json; charset=utf-8'
                    $res.OutputStream.Write($errBytes, 0, $errBytes.Length)
                    Write-Host "[$stamp] !!! /save-state FAILED: $($_.Exception.Message)" -ForegroundColor Red
                }
                $res.Close()
                continue
            }

            # DART OpenAPI valuation lookup (GET)
            #   /api/dart-valuation?corp_code=01310241[&ltm=1]
            # Runs fetch-dart-valuation.ps1 with the given corp_code and
            # streams the resulting JSON back to the browser. Used by the
            # "DART 자동 채우기" button on valuation cards.
            if ($relPath -eq '/api/dart-valuation') {
                $qsCode = $req.QueryString['corp_code']
                $qsName = $req.QueryString['name']
                $qsLtm  = $req.QueryString['ltm']
                if (-not $qsCode) {
                    $res.StatusCode = 400
                    $errMsg = Get-JsonError 'corp_code required'
                    $errBytes = [System.Text.Encoding]::UTF8.GetBytes($errMsg)
                    $res.ContentType = 'application/json; charset=utf-8'
                    $res.OutputStream.Write($errBytes, 0, $errBytes.Length)
                    $res.Close()
                    continue
                }
                # Validate: 8-digit numeric only
                if ($qsCode -notmatch '^\d{8}$') {
                    $res.StatusCode = 400
                    $errMsg = Get-JsonError 'corp_code must be 8 digits'
                    $errBytes = [System.Text.Encoding]::UTF8.GetBytes($errMsg)
                    $res.ContentType = 'application/json; charset=utf-8'
                    $res.OutputStream.Write($errBytes, 0, $errBytes.Length)
                    $res.Close()
                    continue
                }
                $dartScript = Join-Path $root 'fetch-dart-valuation.ps1'
                # $args is a PowerShell automatic variable — use a different name.
                $dartArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $dartScript, '-CorpCode', $qsCode)
                if ($qsName) { $dartArgs += @('-CorpName', $qsName) }
                if ($qsLtm -eq '1' -or $qsLtm -eq 'true') { $dartArgs += @('-LTM') }

                Write-Host "[$stamp] >>> /api/dart-valuation corp_code=$qsCode ltm=$qsLtm" -ForegroundColor Magenta
                $dartOutput = & powershell $dartArgs 2>&1
                $oneLine = ($dartOutput -join ' | ')
                if ($oneLine.Length -gt 300) { $oneLine = $oneLine.Substring(0, 300) + '...' }
                Write-Host ("[$stamp]     fetch-dart: " + $oneLine) -ForegroundColor DarkGray
                $valJsonPath = Join-Path $root ("valuation-" + $qsCode + ".json")
                if (-not (Test-Path -LiteralPath $valJsonPath)) {
                    $res.StatusCode = 500
                    $errMsg = Get-JsonError "DART fetch failed (no output file)"
                    $errBytes = [System.Text.Encoding]::UTF8.GetBytes($errMsg)
                    $res.ContentType = 'application/json; charset=utf-8'
                    $res.OutputStream.Write($errBytes, 0, $errBytes.Length)
                    $res.Close()
                    continue
                }
                $valBytes = [System.IO.File]::ReadAllBytes($valJsonPath)
                $res.ContentType = 'application/json; charset=utf-8'
                $res.Headers.Add('Cache-Control', 'no-store')
                $res.ContentLength64 = $valBytes.Length
                $res.OutputStream.Write($valBytes, 0, $valBytes.Length)
                $res.Close()
                continue
            }

            # On-demand refresh endpoint: market data + calendar
            if ($relPath -eq '/refresh') {
                Write-Host "[$stamp] >>> /refresh (market + calendar)..." -ForegroundColor Magenta
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                if (Test-Path -LiteralPath $refreshScript) {
                    & powershell -NoProfile -ExecutionPolicy Bypass -File $refreshScript  | Out-Null
                } else {
                    Write-Host "[$stamp] !!! refresh.ps1 missing (AV-quarantined) — skipping market fetch" -ForegroundColor Red
                }
                $marketMs = $sw.ElapsedMilliseconds
                if (Test-Path -LiteralPath $calendarScript) {
                    & powershell -NoProfile -ExecutionPolicy Bypass -File $calendarScript | Out-Null
                }
                # FedWatch refreshes on every ↻ click (user spec: "refresh할 때마다")
                $fedwatchScript = Join-Path $root 'fetch-fedwatch.ps1'
                if (Test-Path -LiteralPath $fedwatchScript) {
                    & powershell -NoProfile -ExecutionPolicy Bypass -File $fedwatchScript | Out-Null
                }
                $sw.Stop()
                $msg = "{`"ok`":true,`"totalMs`":$($sw.ElapsedMilliseconds),`"marketMs`":$marketMs,`"calendarMs`":$($sw.ElapsedMilliseconds - $marketMs)}"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
                $res.ContentType = 'application/json; charset=utf-8'
                $res.Headers.Add('Cache-Control', 'no-store')
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                Write-Host "[$stamp] <<< /refresh done in $($sw.ElapsedMilliseconds)ms (market=${marketMs}ms, cal=$($sw.ElapsedMilliseconds - $marketMs)ms)" -ForegroundColor Magenta
                $res.Close()
                continue
            }

            $cleanPath = $relPath.TrimStart('/').Replace('/', '\')
            $fullPath = Join-Path $root $cleanPath

            if (Test-Path $fullPath -PathType Leaf) {
                $ext = [System.IO.Path]::GetExtension($fullPath).ToLower()
                $contentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
                $bytes = [System.IO.File]::ReadAllBytes($fullPath)
                $res.ContentType = $contentType
                $res.ContentLength64 = $bytes.Length
                $res.Headers.Add('Cache-Control', 'no-store, no-cache, must-revalidate')
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                Write-Host "[$stamp] 200 $relPath ($($bytes.Length) bytes)" -ForegroundColor DarkGray
            } else {
                $res.StatusCode = 404
                $msg = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $relPath")
                $res.OutputStream.Write($msg, 0, $msg.Length)
                Write-Host "[$stamp] 404 $relPath" -ForegroundColor Red
            }
        } catch {
            Write-Host "Request error: $($_.Exception.Message)" -ForegroundColor Red
        } finally {
            try { $res.Close() } catch {}
        }
    }
} finally {
    Write-Host ""
    Write-Host "Stopping..." -ForegroundColor Yellow
    $listener.Stop()
    $listener.Close()
    foreach ($p in @($marketProc, $calendarProc)) {
        if ($p -and -not $p.HasExited) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "  Background loops stopped." -ForegroundColor Green
    Write-Host "Done." -ForegroundColor Cyan
}
