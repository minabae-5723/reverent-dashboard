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
    sector = @(
        @{ key='IT';          symbol='XLK'  }
        @{ key='HEALTHCARE';  symbol='XLV'  }
        @{ key='DISCRET';     symbol='XLY'  }
        @{ key='INDUSTRIALS'; symbol='XLI'  }
        @{ key='STAPLES';     symbol='XLP'  }
        @{ key='ENERGY';      symbol='XLE'  }
        @{ key='FINANCIALS';  symbol='XLF'  }
        @{ key='MATERIALS';   symbol='XLB'  }
        @{ key='UTILITIES';   symbol='XLU'  }
        @{ key='REALESTATE';  symbol='XLRE' }
        @{ key='COMM';        symbol='XLC'  }
    )
}

# Static data (Korean rates / BDI / CDS - update from PDF weekly)
$STATIC_DATA = @{
    cds = @(
        @{ key='CDS_US'; current=35.1; wow=0.0;  mom=-0.5; ytd=8.5;  type='bp_abs'; ok=$true }
        @{ key='CDS_CN'; current=41.9; wow=-2.3; mom=-6.7; ytd=-1.9; type='bp_abs'; ok=$true }
    )
    rate_kr = @(
        # KR3Y / KR10Y are now auto-fetched from Investing (Get-InvestingYield).
        # These static fallbacks are only used when the scrape fails.
        @{ key='KR3Y';  current=3.56; wow=-3; mom=21; ytd=63; type='bp'; ok=$true; static=$true }
        @{ key='KR10Y'; current=3.91; wow=7;  mom=23; ytd=53; type='bp'; ok=$true; static=$true }
        # CD91 stays static — Investing doesn't have a clean page for Korean CD rate.
        @{ key='CD91';  current=2.81; wow=0;  mom=-1; ytd=4;  type='bp'; ok=$true; static=$true }
    )
    commodity_extra = @(
        @{ key='BDI'; current=2978; wow=13.1; mom=35.3; ytd=58.2; type='pct'; ok=$true; static=$true }
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

# Find the latest history entry whose date <= target (i.e., most recent trading
# day on or before target). Falls back to history[0] if target precedes all data.
# Assumes $History is sorted ascending by date.
function Get-EntryOnOrBefore {
    param([array]$History, [DateTime]$Target)
    $best = $null
    foreach ($bar in $History) {
        $d = [DateTime]::Parse($bar.date)
        if ($d -le $Target) { $best = $bar } else { break }
    }
    if (-not $best) { $best = $History[0] }
    return $best
}

# Calculate WoW / MoM / YTD changes.
# WoW = 7 calendar days back (Fri vs Fri); MoM = 1 calendar month back.
# Uses date-based lookup so KR/JP holidays don't shift the baseline
# (trading-day indexing misaligns the baseline for markets whose holiday
# calendars differ from US).
function Get-Changes {
    param([PSCustomObject]$Data, [string]$Type = 'pct', [bool]$Invert = $false)

    if (-not $Data -or $Data.history.Count -lt 2) { return $null }

    $hist = $Data.history
    $current = $Data.current

    if ($Invert) { $current = 1 / $current }

    $lastDate = [DateTime]::Parse($hist[-1].date)

    $wowEntry = Get-EntryOnOrBefore -History $hist -Target $lastDate.AddDays(-7)
    $wowBase  = if ($Invert) { 1 / $wowEntry.close } else { $wowEntry.close }

    $momEntry = Get-EntryOnOrBefore -History $hist -Target $lastDate.AddMonths(-1)
    $momBase  = if ($Invert) { 1 / $momEntry.close } else { $momEntry.close }

    $year = (Get-Date).Year
    $ytdEntry = $hist | Where-Object { $_.date.StartsWith("$year-") } | Select-Object -First 1
    $ytdBase = $null
    if ($ytdEntry) {
        $ytdBase = if ($Invert) { 1 / $ytdEntry.close } else { $ytdEntry.close }
    }

    if ($Type -eq 'bp') {
        return [PSCustomObject]@{
            current = [Math]::Round($current, 3)
            wow     = [Math]::Round(($current - $wowBase) * 100, 0)
            mom     = [Math]::Round(($current - $momBase) * 100, 0)
            ytd     = if ($null -ne $ytdBase) { [Math]::Round(($current - $ytdBase) * 100, 0) } else { $null }
            type    = 'bp'
            asOf    = $Data.asOf
        }
    }

    return [PSCustomObject]@{
        current = [Math]::Round($current, 4)
        wow     = [Math]::Round((($current - $wowBase) / $wowBase) * 100, 2)
        mom     = [Math]::Round((($current - $momBase) / $momBase) * 100, 2)
        ytd     = if ($null -ne $ytdBase) { [Math]::Round((($current - $ytdBase) / $ytdBase) * 100, 2) } else { $null }
        type    = 'pct'
        asOf    = $Data.asOf
    }
}

function Fetch-Group {
    param([array]$Items)

    $rows = @()
    foreach ($item in $Items) {
        $data = Get-YahooChart -Symbol $item.symbol
        $invert = [bool]$item.invert
        $type = if ($item.type) { $item.type } else { 'pct' }
        $changes = Get-Changes -Data $data -Type $type -Invert $invert

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

# Main loop
Add-Type -AssemblyName System.Web

do {
    $start = Get-Date
    Write-Host ("[{0}] Fetching..." -f $start.ToString('HH:mm:ss')) -ForegroundColor Cyan

    $output = [ordered]@{
        updated   = $start.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        updatedKr = $start.ToString('yyyy-MM-dd HH:mm:ss')
        index     = @(Fetch-Group $INSTRUMENTS.index)
        # KR3Y / KR10Y / US2Y auto-fetched from Investing; CD91 stays static.
        rate      = @(Fetch-InvestingYields) +
                    @($STATIC_DATA.rate_kr | Where-Object { $_.key -eq 'CD91' }) +
                    @(Fetch-Group $INSTRUMENTS.rate)
        commodity = @(Fetch-Group $INSTRUMENTS.commodity) + @($STATIC_DATA.commodity_extra)
        fx        = @(Fetch-Group $INSTRUMENTS.fx)
        cds       = @($STATIC_DATA.cds)
        sector    = @(Fetch-Group $INSTRUMENTS.sector)
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
