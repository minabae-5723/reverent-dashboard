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
        @{ key='US2Y';  symbol='^FVX'; type='bp' }
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
        @{ key='KR3Y';  current=3.56; wow=-3; mom=21; ytd=63; type='bp'; ok=$true; static=$true }
        @{ key='KR10Y'; current=3.91; wow=7;  mom=23; ytd=53; type='bp'; ok=$true; static=$true }
        @{ key='CD91';  current=2.81; wow=0;  mom=-1; ytd=4;  type='bp'; ok=$true; static=$true }
    )
    commodity_extra = @(
        @{ key='BDI'; current=2978; wow=13.1; mom=35.3; ytd=58.2; type='pct'; ok=$true; static=$true }
    )
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

# Calculate WoW / MoM / YTD changes
function Get-Changes {
    param([PSCustomObject]$Data, [string]$Type = 'pct', [bool]$Invert = $false)

    if (-not $Data -or $Data.history.Count -lt 2) { return $null }

    $hist = $Data.history
    $current = $Data.current

    if ($Invert) { $current = 1 / $current }

    $wowIdx = [Math]::Max(0, $hist.Count - 1 - 5)
    $wowBase = if ($Invert) { 1 / $hist[$wowIdx].close } else { $hist[$wowIdx].close }

    $momIdx = [Math]::Max(0, $hist.Count - 1 - 22)
    $momBase = if ($Invert) { 1 / $hist[$momIdx].close } else { $hist[$momIdx].close }

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
        rate      = @($STATIC_DATA.rate_kr) + @(Fetch-Group $INSTRUMENTS.rate)
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
