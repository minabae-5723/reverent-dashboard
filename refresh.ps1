# =============================================================
#  Reverent Partners - Live Dashboard Data Fetcher
#  Yahoo Finance v8 API -> data.json
#
#  Usage:
#    powershell -ExecutionPolicy Bypass -File .\refresh.ps1
#    powershell -ExecutionPolicy Bypass -File .\refresh.ps1 -Loop
# =============================================================
param([switch]$Loop)

$ErrorActionPreference = 'Continue'
$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
$DataFile  = Join-Path $PSScriptRoot 'data.json'

# Ticker definitions (ASCII-only; UI labels mapped in app.js)
$INSTRUMENTS = @{
    index = @(
        @{ key='KOSPI';    symbol='^KS11'     }
        @{ key='KOSDAQ';   symbol='^KQ11'     }
        @{ key='DOW';      symbol='^DJI'      }
        @{ key='SPX';      symbol='^GSPC'     }
        @{ key='NASDAQ';   symbol='^IXIC'     }
        @{ key='SHANGHAI'; symbol='000001.SS' }
    )
    rate = @(
        # US2Y (real 2-year) is sourced from Investing instead — Yahoo has no 2Y symbol.
        # ^FVX is a 5-year Treasury yield, kept here only as a historical reference if needed.
        @{ key='US10Y'; symbol='^TNX'; type='bp' }
        @{ key='US30Y'; symbol='^TYX'; type='bp' }
    )
    commodity = @(
        @{ key='WTI';    symbol='CL=F' }
        @{ key='GOLD';   symbol='GC=F' }
        @{ key='COPPER'; symbol='HG=F' }
        @{ key='WHEAT';  symbol='ZW=F' }
    )
    fx = @(
        @{ key='USDKRW'; symbol='KRW=X'    }
        @{ key='USDEUR'; symbol='EURUSD=X'; invert=$true }
        @{ key='USDJPY'; symbol='JPY=X'    }
        @{ key='USDCNY'; symbol='CNY=X'    }
        @{ key='DXY';    symbol='DX-Y.NYB' }
    )
    # Sector indices: S&P 500 GICS sector indices (not SPDR ETFs).
    # ^SP500-NN uses the 2-digit GICS sector code; ENERGY needs ^GSPE.
    # Cleaner benchmark than ETFs (no expense-ratio drag, matches headline prints).
    sector = @(
        @{ key='IT';          symbol='^SP500-45' }
        @{ key='HEALTHCARE';  symbol='^SP500-35' }
        @{ key='DISCRET';     symbol='^SP500-25' }
        @{ key='INDUSTRIALS'; symbol='^SP500-20' }
        @{ key='STAPLES';     symbol='^SP500-30' }
        @{ key='ENERGY';      symbol='^GSPE'     }
        @{ key='FINANCIALS';  symbol='^SP500-40' }
        @{ key='MATERIALS';   symbol='^SP500-15' }
        @{ key='UTILITIES';   symbol='^SP500-55' }
        @{ key='REALESTATE';  symbol='^SP500-60' }
        @{ key='COMM';        symbol='^SP500-50' }
    )
}

# Static data (Korean rates / CDS - fallback only; auto-fetched in main path)
$STATIC_DATA = @{
    cds = @(
        # Fallback values reflect 2026-05-22 Friday NY close (Investing.com)
        @{ key='CDS_US'; current=37.75; wow=0;  mom=3;  ytd=11; type='bp_abs'; ok=$true }
        @{ key='CDS_CN'; current=40.58; wow=-1; mom=-7; ytd=-3; type='bp_abs'; ok=$true }
    )
    rate_kr = @(
        # KR3Y / KR10Y are now auto-fetched from Investing (Get-InvestingYield).
        # These static fallbacks are only used when the scrape fails.
        @{ key='KR3Y';  current=3.56; wow=-3; mom=21; ytd=63; type='bp'; ok=$true; static=$true }
        @{ key='KR10Y'; current=3.91; wow=7;  mom=23; ytd=53; type='bp'; ok=$true; static=$true }
        # CD91 stays static — Investing doesn't have a clean page for Korean CD rate.
        @{ key='CD91';  current=2.81; wow=0;  mom=-1; ytd=4;  type='bp'; ok=$true; static=$true }
    )
}

# ----------------------------------------------------------------
# Investing.com bond-yield fetch (auto-replacement for STATIC values).
# Extracts current yield + WoW/MoM/YTD bp change from priceChanges JSON
# embedded in __NEXT_DATA__.
# ----------------------------------------------------------------
function Get-InvestingYield {
    param([string]$BondUrl, [string]$Key)
    try {
        $r = Invoke-WebRequest -Uri $BondUrl -UseBasicParsing -UserAgent $UserAgent -TimeoutSec 15
        $html = $r.Content

        # Current yield (e.g. "data-test=\"instrument-price-last\">3.973")
        $priceM = [regex]::Match($html, 'data-test="instrument-price-last">\s*([\d\.,]+)')
        if (-not $priceM.Success) { return $null }
        $current = [double]($priceM.Groups[1].Value -replace ',', '')

        # priceChanges JSON object embedded in Next.js data
        $pcM = [regex]::Match($html, '"priceChanges"\s*:\s*\{([^\}]+)\}', 'Singleline')
        if (-not $pcM.Success) { return $null }
        # Parse inner object as JSON
        $pcObj = ('{' + $pcM.Groups[1].Value + '}') | ConvertFrom-Json

        # Convert pct-change in yield -> bp delta.
        # prior_yield = current / (1 + pct/100)
        # bp_change   = (current - prior_yield) * 100
        $bp = {
            param($pct)
            if ($null -eq $pct) { return $null }
            $p = [double]$pct
            $prior = $current / (1 + $p / 100)
            return [Math]::Round(($current - $prior) * 100, 0)
        }

        return [PSCustomObject]@{
            key     = $Key
            current = [Math]::Round($current, 3)
            wow     = & $bp $pcObj.pct_1w
            mom     = & $bp $pcObj.pct_1m
            ytd     = & $bp $pcObj.pct_ytd
            type    = 'bp'
            asOf    = $pcObj.updated_at
            ok      = $true
            source  = 'investing'
        }
    } catch {
        Write-Warning ("Investing yield fail [{0}]: {1}" -f $Key, $_.Exception.Message)
        return $null
    }
}

# ----------------------------------------------------------------
# Investing.com CDS spread fetch (5Y USD CDS).
# CDS is already quoted in bp, so the bp-delta conversion uses
# (current - prior) directly (no ×100 like for bond yields).
# ----------------------------------------------------------------
function Get-InvestingCDS {
    param([string]$Url, [string]$Key)
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -UserAgent $UserAgent -TimeoutSec 20
        $html = $r.Content

        $priceM = [regex]::Match($html, 'data-test="instrument-price-last">\s*([\d\.,]+)')
        if (-not $priceM.Success) { return $null }
        $current = [double]($priceM.Groups[1].Value -replace ',', '')

        $pcM = [regex]::Match($html, '"priceChanges"\s*:\s*\{([^\}]+)\}', 'Singleline')
        if (-not $pcM.Success) { return $null }
        $pcObj = ('{' + $pcM.Groups[1].Value + '}') | ConvertFrom-Json

        $bpDelta = {
            param($pct)
            if ($null -eq $pct) { return $null }
            $p = [double]$pct
            $prior = $current / (1 + $p / 100)
            return [Math]::Round($current - $prior, 1)
        }

        return [PSCustomObject]@{
            key     = $Key
            current = [Math]::Round($current, 1)
            wow     = & $bpDelta $pcObj.pct_1w
            mom     = & $bpDelta $pcObj.pct_1m
            ytd     = & $bpDelta $pcObj.pct_ytd
            type    = 'bp_abs'
            asOf    = $pcObj.updated_at
            ok      = $true
            source  = 'investing'
        }
    } catch {
        Write-Warning ("Investing CDS fail [{0}]: {1}" -f $Key, $_.Exception.Message)
        return $null
    }
}

# Fetch US + CN 5Y CDS. Falls back to STATIC_DATA on failure.
function Fetch-InvestingCDS {
    $urls = [ordered]@{
        CDS_US = 'https://www.investing.com/rates-bonds/united-states-cds-5-years-usd'
        CDS_CN = 'https://www.investing.com/rates-bonds/china-cds-5-years-usd'
    }
    $rows = @()
    foreach ($key in $urls.Keys) {
        $r = Get-InvestingCDS -Url $urls[$key] -Key $key
        if ($r) {
            $rows += $r
        } else {
            $fallback = $STATIC_DATA.cds | Where-Object { $_.key -eq $key }
            if ($fallback) { $rows += $fallback }
        }
        Start-Sleep -Milliseconds 200
    }
    return $rows
}

# ----------------------------------------------------------------
# Investing.com commodity fetch — reflects after-hours Globex prices
# (Yahoo's regularMarketPrice only shows the Friday floor-close, which
# undershoots when Sunday-evening crude has already moved).
# Used for WTI; other commodities still use Yahoo.
# ----------------------------------------------------------------
function Get-InvestingCommodity {
    param([string]$Url, [string]$Key)
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -UserAgent $UserAgent -TimeoutSec 20
        $html = $r.Content

        $priceM = [regex]::Match($html, 'data-test="instrument-price-last">\s*([\d\.,]+)')
        if (-not $priceM.Success) { return $null }
        $current = [double]($priceM.Groups[1].Value -replace ',', '')

        $pcM = [regex]::Match($html, '"priceChanges"\s*:\s*\{([^\}]+)\}', 'Singleline')
        if (-not $pcM.Success) { return $null }
        $pcObj = ('{' + $pcM.Groups[1].Value + '}') | ConvertFrom-Json

        return [PSCustomObject]@{
            key     = $Key
            current = [Math]::Round($current, 2)
            wow     = if ($null -ne $pcObj.pct_1w)  { [Math]::Round([double]$pcObj.pct_1w, 2) }  else { $null }
            mom     = if ($null -ne $pcObj.pct_1m)  { [Math]::Round([double]$pcObj.pct_1m, 2) }  else { $null }
            ytd     = if ($null -ne $pcObj.pct_ytd) { [Math]::Round([double]$pcObj.pct_ytd, 2) } else { $null }
            type    = 'pct'
            asOf    = if ($pcObj.updated_at) { $pcObj.updated_at } else { (Get-Date).ToString('s') }
            ok      = $true
            source  = 'investing'
        }
    } catch {
        Write-Warning ("Investing commodity fail [{0}]: {1}" -f $Key, $_.Exception.Message)
        return $null
    }
}

# CD91 (Korean 91-day CD rate) auto-fetch from Naver mobile market index API.
# Maintains cd91-history.json (daily snapshots) so WoW/MoM/YTD can be computed
# once enough history accumulates. Falls back to STATIC_DATA for deltas if
# history is too short.
function Get-NaverCD91 {
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', $UserAgent)
        $raw = $wc.DownloadData('https://api.stock.naver.com/marketindex/domesticInterest/KFIA114000')
        $wc.Dispose()
        $obj = [System.Text.Encoding]::UTF8.GetString($raw) | ConvertFrom-Json
        $cur = [double]$obj.closePrice
        $tradedDate = ([DateTime]::Parse($obj.localTradedAt)).ToString('yyyy-MM-dd')

        # Load or initialize history
        $histFile = Join-Path $PSScriptRoot 'cd91-history.json'
        $hist = @()
        if (Test-Path $histFile) {
            try {
                $loaded = (Get-Content $histFile -Raw -Encoding UTF8 | ConvertFrom-Json).history
                if ($loaded) { $hist = @($loaded) }
            } catch {}
        }
        # Upsert today's value (or update if rate changed)
        $existing = $hist | Where-Object { $_.date -eq $tradedDate }
        if ($existing) {
            $existing.close = $cur
        } else {
            $hist += [PSCustomObject]@{ date = $tradedDate; close = $cur }
        }
        $hist = @($hist | Sort-Object date) | Select-Object -Last 400
        $out = @{ history = $hist }
        [System.IO.File]::WriteAllText($histFile, ($out | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))

        # Compute deltas from history
        $today = [DateTime]::Parse($tradedDate)
        $wowTarget = $today.AddDays(-7).ToString('yyyy-MM-dd')
        $momTarget = $today.AddMonths(-1).ToString('yyyy-MM-dd')
        $year      = $today.Year

        $findClosest = {
            param($targetStr)
            $best = $null
            foreach ($h in $hist) {
                if ($h.date -le $targetStr) {
                    if (-not $best -or $h.date -gt $best.date) { $best = $h }
                }
            }
            return $best
        }
        $wowBase = & $findClosest $wowTarget
        $momBase = & $findClosest $momTarget
        $ytdBase = $hist | Where-Object { $_.date.StartsWith("$year-") } | Select-Object -First 1

        # When history is brand new, the "first entry of year" lookups can
        # equal today's entry — treat that as no baseline so the static
        # fallback fills in deltas instead of returning a spurious 0.
        if ($wowBase -and $wowBase.date -eq $tradedDate) { $wowBase = $null }
        if ($momBase -and $momBase.date -eq $tradedDate) { $momBase = $null }
        if ($ytdBase -and $ytdBase.date -eq $tradedDate) { $ytdBase = $null }

        $bp = { param($prev) if ($prev) { [Math]::Round(($cur - [double]$prev.close) * 100, 0) } else { $null } }

        return [PSCustomObject]@{
            key     = 'CD91'
            current = [Math]::Round($cur, 3)
            wow     = & $bp $wowBase
            mom     = & $bp $momBase
            ytd     = & $bp $ytdBase
            type    = 'bp'
            asOf    = $tradedDate
            ok      = $true
            source  = 'naver-mobile'
        }
    } catch {
        Write-Warning ("CD91 fetch fail: " + $_.Exception.Message)
        return $null
    }
}

# Fetch KR3Y, KR10Y, US2Y from Investing. Falls back to STATIC_DATA on failure.
function Fetch-InvestingYields {
    $urls = [ordered]@{
        KR3Y  = 'https://www.investing.com/rates-bonds/south-korea-3-year-bond-yield'
        KR10Y = 'https://www.investing.com/rates-bonds/south-korea-10-year-bond-yield'
        US2Y  = 'https://www.investing.com/rates-bonds/u.s.-2-year-bond-yield'
    }
    $rows = @()
    foreach ($key in $urls.Keys) {
        $y = Get-InvestingYield -BondUrl $urls[$key] -Key $key
        if ($y) {
            $rows += $y
        } else {
            # fallback to static row with same key (preserves dashboard layout)
            $fallback = $STATIC_DATA.rate_kr | Where-Object { $_.key -eq $key }
            if (-not $fallback -and $key -eq 'US2Y') {
                # No static fallback for US2Y — emit placeholder
                $fallback = @{ key=$key; ok=$false; error='Investing fetch failed' }
            }
            if ($fallback) { $rows += $fallback }
        }
        Start-Sleep -Milliseconds 200
    }
    return $rows
}

# Yahoo Finance v8 fetch
function Get-YahooChart {
    param([string]$Symbol)

    $encoded = [System.Web.HttpUtility]::UrlEncode($Symbol)
    $url = "https://query1.finance.yahoo.com/v8/finance/chart/${encoded}?interval=1d&range=1y"

    try {
        $r = Invoke-RestMethod -Uri $url -UserAgent $UserAgent -TimeoutSec 15
        if (-not $r.chart -or -not $r.chart.result) { return $null }

        $result = $r.chart.result[0]
        $meta = $result.meta
        $timestamps = $result.timestamp
        $closes = $result.indicators.quote[0].close

        if (-not $closes -or $closes.Count -eq 0) { return $null }

        $history = @()
        for ($i = 0; $i -lt $closes.Count; $i++) {
            if ($null -ne $closes[$i]) {
                $dt = (Get-Date '1970-01-01Z').AddSeconds($timestamps[$i])
                $history += [PSCustomObject]@{
                    date  = $dt.ToString('yyyy-MM-dd')
                    close = [double]$closes[$i]
                }
            }
        }

        if ($history.Count -lt 2) { return $null }

        return [PSCustomObject]@{
            symbol  = $Symbol
            current = [double]$meta.regularMarketPrice
            asOf    = (Get-Date '1970-01-01Z').AddSeconds($meta.regularMarketTime).ToString('s')
            history = $history
        }
    } catch {
        Write-Warning ("YF fail [{0}]: {1}" -f $Symbol, $_.Exception.Message)
        return $null
    }
}

# Find the most recent Friday entry in a daily-history array.
# Used by Friday-freeze mode: regardless of what day refresh runs, the dashboard
# always displays the most recent completed Friday close (Yahoo only appends
# today's close to history AFTER that exchange's session ends, so this naturally
# becomes "last Friday's close" Mon-Thu and "today's close" on Fri post-close).
function Get-LastFridayEntry {
    param([array]$History)
    for ($i = $History.Count - 1; $i -ge 0; $i--) {
        $dt = [DateTime]::Parse($History[$i].date)
        if ($dt.DayOfWeek -eq [System.DayOfWeek]::Friday) {
            return [PSCustomObject]@{ idx = $i; entry = $History[$i] }
        }
    }
    return $null
}

# Find the N-th previous Friday in history (going backward from a given index).
function Get-PrevFridayEntry {
    param([array]$History, [int]$FromIdx, [int]$WeeksBack = 1)
    $count = 0
    for ($i = $FromIdx - 1; $i -ge 0; $i--) {
        $dt = [DateTime]::Parse($History[$i].date)
        if ($dt.DayOfWeek -eq [System.DayOfWeek]::Friday) {
            $count++
            if ($count -eq $WeeksBack) { return $History[$i] }
        }
    }
    return $null
}

# Global anchor Friday: the most recent Friday whose US session has FULLY
# closed. US Fri 16:00 ET lands at ~Sat 05:00-06:00 KST, so we use Sat 07:00
# KST as the safe cutoff. Before that, "this week's" US Friday close isn't in
# Yahoo history yet, so we anchor to the PREVIOUS Friday — guaranteeing every
# market (KR closes Fri 15:30 KST, US closes Sat ~05:00 KST) reports the SAME
# Friday-close date, regardless of whether the snapshot runs Fri eve / Sat /
# Sun / mid-week. (Fixes the bug where a Fri-evening run showed KR=Fri close
# but US=Thu close.)
function Get-AnchorFridayDate {
    $now = Get-Date
    $delta = ([int]$now.DayOfWeek - 5 + 7) % 7      # days since most recent Friday (Fri=5)
    $thisFriday = $now.Date.AddDays(-$delta)         # most recent Friday (may be today)
    $usCloseAvail = $thisFriday.AddDays(1).AddHours(7)   # Sat 07:00 KST
    if ($now -lt $usCloseAvail) { return $thisFriday.AddDays(-7) }
    return $thisFriday
}

# Find the latest history entry whose date satisfies the comparison vs Target.
# Mode 'le' = on-or-before (date <= target). Mode 'lt' = strictly before (date < target).
# Falls back to history[0] if target precedes all data.
# Assumes $History is sorted ascending by date.
function Get-EntryBefore {
    param([array]$History, [DateTime]$Target, [string]$Mode = 'le')
    $best = $null
    foreach ($bar in $History) {
        $d = [DateTime]::Parse($bar.date)
        $match = if ($Mode -eq 'lt') { $d -lt $Target } else { $d -le $Target }
        if ($match) { $best = $bar } else { break }
    }
    if (-not $best) { $best = $History[0] }
    return $best
}

# Calculate WoW / MoM / YTD changes.
# WoW: last close vs (lastDate - 7 calendar days, on-or-before trading day).
#      e.g. 5/15 Fri vs 5/8 Fri.
# MoM: last close vs (today - 1 calendar month, on-or-before trading day).
#      Matches Google Finance's "past month" convention. e.g. on 5/17 Sun the
#      target is 4/17 Fri, which is a trading day in both US & KR markets, so
#      we use that as baseline. SPX: 4/17 close 7,126 → +3.96% (matches Google).
# Date-based (not trading-day-index based) so KR/JP holidays don't shift the
# baseline relative to US markets.
function Get-Changes {
    param(
        [PSCustomObject]$Data,
        [string]$Type = 'pct',
        [bool]$Invert = $false,
        [bool]$FreezeFriday = $false
    )

    if (-not $Data -or $Data.history.Count -lt 2) { return $null }

    $hist = $Data.history

    # ── Friday-freeze mode (anchored to a single global Friday) ──
    # All markets freeze to $script:AnchorFriday — the most recent Friday whose
    # US session has fully closed (see Get-AnchorFridayDate). This guarantees KR
    # and US report the SAME Friday-close date. current = bar on/before anchor;
    # WoW = on/before anchor-7d; MoM = on/before anchor-28d; YTD = year start.
    if ($FreezeFriday) {
        $anchor = if ($script:AnchorFriday) { $script:AnchorFriday } else { Get-AnchorFridayDate }
        $curEntry = Get-EntryBefore -History $hist -Target $anchor -Mode 'le'
        if (-not $curEntry) { return $null }
        $current = if ($Invert) { 1 / $curEntry.close } else { $curEntry.close }
        $asOf    = $curEntry.date

        $wowEntry = Get-EntryBefore -History $hist -Target $anchor.AddDays(-7)  -Mode 'le'
        $momEntry = Get-EntryBefore -History $hist -Target $anchor.AddDays(-28) -Mode 'le'
        $wowBase = if ($wowEntry) { if ($Invert) { 1 / $wowEntry.close } else { $wowEntry.close } } else { $null }
        $momBase = if ($momEntry) { if ($Invert) { 1 / $momEntry.close } else { $momEntry.close } } else { $null }

        $year = ([DateTime]::Parse($curEntry.date)).Year
    } else {
        $current = $Data.current
        if ($Invert) { $current = 1 / $current }
        $asOf = $Data.asOf

        $lastDate = [DateTime]::Parse($hist[-1].date)
        $today    = (Get-Date).Date

        $wowEntry = Get-EntryBefore -History $hist -Target $lastDate.AddDays(-7) -Mode 'le'
        $wowBase  = if ($Invert) { 1 / $wowEntry.close } else { $wowEntry.close }

        $momEntry = Get-EntryBefore -History $hist -Target $today.AddMonths(-1) -Mode 'le'
        $momBase  = if ($Invert) { 1 / $momEntry.close } else { $momEntry.close }

        $year = (Get-Date).Year
    }

    $ytdEntry = $hist | Where-Object { $_.date.StartsWith("$year-") } | Select-Object -First 1
    $ytdBase = $null
    if ($ytdEntry) {
        $ytdBase = if ($Invert) { 1 / $ytdEntry.close } else { $ytdEntry.close }
    }

    if ($Type -eq 'bp') {
        return [PSCustomObject]@{
            current = [Math]::Round($current, 3)
            wow     = if ($null -ne $wowBase) { [Math]::Round(($current - $wowBase) * 100, 0) } else { $null }
            mom     = if ($null -ne $momBase) { [Math]::Round(($current - $momBase) * 100, 0) } else { $null }
            ytd     = if ($null -ne $ytdBase) { [Math]::Round(($current - $ytdBase) * 100, 0) } else { $null }
            type    = 'bp'
            asOf    = $asOf
        }
    }

    return [PSCustomObject]@{
        current = [Math]::Round($current, 4)
        wow     = if ($null -ne $wowBase) { [Math]::Round((($current - $wowBase) / $wowBase) * 100, 2) } else { $null }
        mom     = if ($null -ne $momBase) { [Math]::Round((($current - $momBase) / $momBase) * 100, 2) } else { $null }
        ytd     = if ($null -ne $ytdBase) { [Math]::Round((($current - $ytdBase) / $ytdBase) * 100, 2) } else { $null }
        type    = 'pct'
        asOf    = $asOf
    }
}

function Fetch-Group {
    param([array]$Items, [bool]$FreezeFriday = $false)

    $rows = @()
    foreach ($item in $Items) {
        $data = Get-YahooChart -Symbol $item.symbol
        $invert = [bool]$item.invert
        $type = if ($item.type) { $item.type } else { 'pct' }
        $changes = Get-Changes -Data $data -Type $type -Invert $invert -FreezeFriday $FreezeFriday

        if ($changes) {
            $rows += [PSCustomObject]@{
                key     = $item.key
                symbol  = $item.symbol
                current = $changes.current
                wow     = $changes.wow
                mom     = $changes.mom
                ytd     = $changes.ytd
                type    = $changes.type
                asOf    = $changes.asOf
                ok      = $true
            }
        } else {
            $rows += [PSCustomObject]@{
                key    = $item.key
                symbol = $item.symbol
                ok     = $false
                error  = 'fetch failed'
            }
        }
        Start-Sleep -Milliseconds 80
    }
    return $rows
}

# All commodities now come from Yahoo with Friday-freeze (so the dashboard
# shows last Friday's settlement and stays put through the week).
# (Investing-WTI was previously used for Globex after-hours — that's the
#  opposite of what we want now: a fixed Friday snapshot.)
function _FetchCommodities {
    return @(Fetch-Group $INSTRUMENTS.commodity -FreezeFriday $true)
}

# Main loop
Add-Type -AssemblyName System.Web

do {
    $start = Get-Date
    Write-Host ("[{0}] Fetching..." -f $start.ToString('HH:mm:ss')) -ForegroundColor Cyan

    # Compute the global Friday anchor ONCE per run so every market (KR/US/CN)
    # freezes to the same fully-closed Friday close.
    $script:AnchorFriday = Get-AnchorFridayDate
    Write-Host ("  Anchor Friday: {0:yyyy-MM-dd}" -f $script:AnchorFriday) -ForegroundColor DarkGray

    # Build rate group in user-requested order:
    #   KR3Y → KR10Y → CD91 → US2Y → US10Y → US30Y
    $kr3y  = (Fetch-InvestingYields | Where-Object { $_.key -eq 'KR3Y' })
    $kr10y = (Fetch-InvestingYields | Where-Object { $_.key -eq 'KR10Y' })
    $us2y  = (Fetch-InvestingYields | Where-Object { $_.key -eq 'US2Y' })
    # Re-fetch is wasteful — store in variable
    $invYields = Fetch-InvestingYields
    $cd91 = Get-NaverCD91
    if (-not $cd91) {
        $cd91 = $STATIC_DATA.rate_kr | Where-Object { $_.key -eq 'CD91' }
    } elseif ($null -eq $cd91.wow -or $null -eq $cd91.mom -or $null -eq $cd91.ytd) {
        # History too short — fill missing deltas from static fallback
        $static = $STATIC_DATA.rate_kr | Where-Object { $_.key -eq 'CD91' }
        if ($static) {
            if ($null -eq $cd91.wow) { $cd91.wow = $static.wow }
            if ($null -eq $cd91.mom) { $cd91.mom = $static.mom }
            if ($null -eq $cd91.ytd) { $cd91.ytd = $static.ytd }
        }
    }
    $rateOrdered = @()
    $rateOrdered += ($invYields | Where-Object { $_.key -eq 'KR3Y' })
    $rateOrdered += ($invYields | Where-Object { $_.key -eq 'KR10Y' })
    $rateOrdered += $cd91
    $rateOrdered += ($invYields | Where-Object { $_.key -eq 'US2Y' })
    $rateOrdered += @(Fetch-Group $INSTRUMENTS.rate)

    # ── FX: prefer Seoul-close snapshot from Naver (fx-naver-snapshot.json) ──
    # Generated by fetch-naver-fx.ps1 (run by deploy-snapshot + deploy-friday).
    # Falls back to Yahoo (NY-close basis) per-key when snapshot is missing.
    $yahooFx = @(Fetch-Group $INSTRUMENTS.fx -FreezeFriday $true)
    $naverFxFile = Join-Path $PSScriptRoot 'fx-naver-snapshot.json'
    $naverFxMap = @{}
    if (Test-Path $naverFxFile) {
        try {
            $naverObj = Get-Content $naverFxFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($naverObj.fx) {
                foreach ($p in $naverObj.fx.PSObject.Properties) {
                    $v = $p.Value
                    $naverFxMap[$p.Name] = [PSCustomObject]@{
                        key     = $p.Name
                        symbol  = "naver:$($p.Name)"
                        current = $v.current
                        wow     = $v.wow
                        mom     = $v.mom
                        ytd     = $v.ytd
                        type    = 'pct'
                        asOf    = $v.asOf
                        ok      = $true
                        source  = 'naver-seoul'
                    }
                }
            }
        } catch { Write-Warning ("fx-naver-snapshot.json parse fail: " + $_.Exception.Message) }
    }
    $fxRows = @()
    foreach ($row in $yahooFx) {
        if ($naverFxMap.ContainsKey($row.key)) {
            $fxRows += $naverFxMap[$row.key]   # Naver Seoul close wins
        } else {
            $fxRows += $row                     # DXY (no Naver equivalent) etc.
        }
    }

    $cdsRows = @(Fetch-InvestingCDS)

    # ── Friday-freeze for Investing-sourced Rate + CDS ──
    # These come from live priceChanges (no historical close in the API), so we
    # snapshot them on the weekend (Fri/Sat/Sun) and hold Mon-Thu. By Saturday
    # both KR (Fri 15:30 KST) and US (Fri 16:00 ET) closes are reflected in the
    # live values, so the last weekend capture == Friday closes.
    $freezeFile = Join-Path $PSScriptRoot 'capmkt-freeze.json'
    $dow = (Get-Date).DayOfWeek
    $isWeekend = ($dow -eq [System.DayOfWeek]::Friday) -or ($dow -eq [System.DayOfWeek]::Saturday) -or ($dow -eq [System.DayOfWeek]::Sunday)
    if ($isWeekend) {
        # Weekend (Fri/Sat/Sun): capture fresh. By Saturday both KR (Fri 15:30 KST)
        # and US (Fri 16:00 ET) closes are reflected in the live Investing values.
        $freezeObj = [ordered]@{
            capturedAt  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            capturedDow = $dow.ToString()
            rate        = $rateOrdered
            cds         = $cdsRows
        }
        [System.IO.File]::WriteAllText($freezeFile, ($freezeObj | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
        Write-Host ("  Rate/CDS frozen ($dow capture)") -ForegroundColor Yellow
    } elseif (Test-Path $freezeFile) {
        # Weekday (Mon-Thu): use last weekend's frozen Friday-close snapshot.
        try {
            $frozen = Get-Content $freezeFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($frozen.rate) { $rateOrdered = @($frozen.rate) }
            if ($frozen.cds)  { $cdsRows     = @($frozen.cds) }
            Write-Host ("  Rate/CDS using frozen snapshot from " + $frozen.capturedAt + " (" + $frozen.capturedDow + ")") -ForegroundColor DarkGray
        } catch {
            Write-Warning ("capmkt-freeze.json parse fail (using live): " + $_.Exception.Message)
        }
    } else {
        # Bootstrap weekday with no freeze file yet — use live values until the
        # first weekend capture locks in a proper Friday close.
        Write-Host ("  Rate/CDS live (no freeze yet — will lock next Fri/Sat/Sun)") -ForegroundColor DarkGray
    }

    $output = [ordered]@{
        updated   = $start.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        updatedKr = $start.ToString('yyyy-MM-dd HH:mm:ss')
        # Index: Friday-frozen to the global anchor Friday (same as sector/fx/
        # commodity). Guarantees KR + US + CN all report the same Friday close,
        # regardless of when the snapshot runs. Holds last Friday Mon-Fri, then
        # advances Saturday 07:00 KST once the new US Friday close is in.
        index     = @(Fetch-Group $INSTRUMENTS.index -FreezeFriday $true)
        rate      = $rateOrdered
        commodity = @(_FetchCommodities)
        fx        = $fxRows
        cds       = $cdsRows
        sector    = @(Fetch-Group $INSTRUMENTS.sector -FreezeFriday $true)
    }

    $json = $output | ConvertTo-Json -Depth 8
    # Write UTF-8 without BOM so fetch() in browser parses cleanly
    [System.IO.File]::WriteAllText($DataFile, $json, (New-Object System.Text.UTF8Encoding($false)))

    $elapsed = (New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds
    $okCount = 0
    foreach ($g in 'index','rate','commodity','fx','sector') {
        foreach ($r in $output[$g]) { if ($r.ok) { $okCount++ } }
    }
    Write-Host ("  Done in {0:N1}s -- {1} live tickers -> {2}" -f $elapsed, $okCount, $DataFile) -ForegroundColor Green

    if ($Loop) { Start-Sleep -Seconds 60 }
} while ($Loop)
