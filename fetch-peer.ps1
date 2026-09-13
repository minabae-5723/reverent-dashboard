# =============================================================
#  Semiconductor Peer table fetcher (Friday close basis)
#
#  For each ticker in peer-config.json (22 semiconductor names):
#    - Yahoo Finance v8/chart  -> historical close prices (1y)
#    - Naver Finance main page -> current market cap, PER, PBR
#  Computes WoW% and YTD% from close prices.
#  Output: peer.json
#
#  NOTE: This script is ASCII-only. Korean names + categories live
#  in peer-config.json (UTF-8) because PS 5.1 reads .ps1 in cp949.
#
#  Usage: powershell -ExecutionPolicy Bypass -File .\fetch-peer.ps1
# =============================================================
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36'

# Load ticker definitions from UTF-8 config (preserves Korean chars).
$cfgPath = Join-Path $root 'peer-config.json'
$cfgRaw = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8)
$cfg = $cfgRaw | ConvertFrom-Json
$tickers = $cfg.tickers

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host (" Semiconductor Peer fetch (" + $tickers.Count + " tickers)") -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# ----------- Helpers -----------

function Get-YahooHistory {
    param([string]$symbol)
    $url = "https://query1.finance.yahoo.com/v8/finance/chart/${symbol}?interval=1d&range=1y"
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent $UA -TimeoutSec 15
        $data = $r.Content | ConvertFrom-Json
        if (-not $data.chart.result) { return @() }
        $res = $data.chart.result[0]
        $ts = $res.timestamp
        $cs = $res.indicators.quote[0].close
        $out = @()
        for ($i = 0; $i -lt $ts.Count; $i++) {
            if ($null -ne $cs[$i]) {
                $out += [PSCustomObject]@{
                    date  = [DateTimeOffset]::FromUnixTimeSeconds([long]$ts[$i]).ToString('yyyy-MM-dd')
                    close = [double]$cs[$i]
                }
            }
        }
        return ,$out
    } catch {
        Write-Host ("    Yahoo error " + $symbol + ": " + $_.Exception.Message) -ForegroundColor DarkYellow
        return @()
    }
}

function Find-ClosestClose {
    param($history, [string]$targetDate)
    if (-not $history -or $history.Count -eq 0) { return $null }
    $best = $null
    foreach ($row in $history) {
        if ($row.date -le $targetDate) {
            if ($null -eq $best -or $row.date -gt $best.date) { $best = $row }
        }
    }
    return $best
}

function Get-NaverSnapshot {
    param([string]$code)
    # 2026-09: finance.naver.com/item/main.naver was rebuilt as a Next.js app and
    # the old scrape anchors (id="_market_sum", id="_per", th_cop_anal20 ...) no
    # longer exist, so every field came back null. We now read the JSON APIs that
    # the new front-end itself calls.
    #   integration     -> marketValue / per / pbr / eps / bps / cnsPer (fwd PER)
    #   finance/annual  -> PER & PBR rows by fiscal year; the highest tableYm
    #                      column is the FY1 estimate (its PER matches cnsPer).
    # ASCII-only source: Korean unit chars are built from code points, never typed.
    $JO = [string][char]0xC870   # trillion marker
    $result = [ordered]@{ mcap=$null; per=$null; pbr=$null; eps=$null; bps=$null; fwdPer=$null; fwdPbr=$null }

    # --- numeric helper: "11.64<BAE>" -> 11.64 , "22,292<WON>" -> 22292
    $ToNum = {
        param([string]$s)
        if ([string]::IsNullOrWhiteSpace($s)) { return $null }
        $t = $s -replace ',', ''
        $m = [regex]::Match($t, '-?\d+(\.\d+)?')
        if ($m.Success) { return [double]$m.Value }
        return $null
    }

    try {
        $api = "https://m.stock.naver.com/api/stock/${code}/integration"
        $j = Invoke-RestMethod -Uri $api -UserAgent $UA -TimeoutSec 15

        $map = @{}
        foreach ($ti in $j.totalInfos) { $map[$ti.code] = [string]$ti.value }

        # Market cap: "1,517<JO> 1,093<EOK>" (two groups) or "8,500<EOK>" (one).
        $mv = $map['marketValue']
        if ($mv) {
            $nums = @([regex]::Matches($mv, '[\d,]+') | ForEach-Object { [double]($_.Value -replace ',', '') })
            if ($nums.Count -ge 2) {
                $result.mcap = ($nums[0] * 10000) + $nums[1]   # 1 trillion = 10,000 eok
            } elseif ($nums.Count -eq 1) {
                # One group only: trillions if the trillion marker is present, else eok.
                if ($mv.Contains($JO)) { $result.mcap = $nums[0] * 10000 } else { $result.mcap = $nums[0] }
            }
        }

        $result.per    = & $ToNum $map['per']
        $result.pbr    = & $ToNum $map['pbr']
        $result.eps    = & $ToNum $map['eps']
        $result.bps    = & $ToNum $map['bps']
        $result.fwdPer = & $ToNum $map['cnsPer']
    } catch {
        Write-Host ("    Naver integration error " + $code + ": " + $_.Exception.Message) -ForegroundColor DarkYellow
    }

    # --- Forward PBR: highest fiscal-year column of the annual PER/PBR rows.
    try {
        $fapi = "https://m.stock.naver.com/api/stock/${code}/finance/annual"
        $f = Invoke-RestMethod -Uri $fapi -UserAgent $UA -TimeoutSec 15
        foreach ($pair in @(@('PBR','fwdPbr'), @('PER','fwdPerAlt'))) {
            $rowTitle = $pair[0]; $target = $pair[1]
            $row = $f.financeInfo.rowList | Where-Object { $_.title -eq $rowTitle } | Select-Object -First 1
            if (-not $row) { continue }
            $props = @($row.columns.PSObject.Properties | Sort-Object Name)
            if ($props.Count -eq 0) { continue }
            $last = $props[$props.Count - 1]          # largest tableYm = FY1 estimate
            $v = & $ToNum ([string]$last.Value.value)
            if ($null -ne $v) {
                if ($target -eq 'fwdPbr') { $result.fwdPbr = $v }
                elseif ($null -eq $result.fwdPer) { $result.fwdPer = $v }
            }
        }
    } catch {
        Write-Host ("    Naver annual error " + $code + ": " + $_.Exception.Message) -ForegroundColor DarkYellow
    }

    return $result
}

# ----------- Date refs from pivot ticker (Samsung) -----------

$pivot = Get-YahooHistory -symbol '005930.KS'
if (-not $pivot -or $pivot.Count -eq 0) {
    Write-Host "FATAL: pivot 005930.KS returned no history" -ForegroundColor Red
    exit 1
}
$refRow  = $pivot[-1]
$refDate = $refRow.date
$refYear = ([datetime]$refDate).Year
$prevTarget = ([datetime]$refDate).AddDays(-7).ToString('yyyy-MM-dd')
$prevRow = Find-ClosestClose -history $pivot -targetDate $prevTarget
$ytdRow  = $pivot | Where-Object { ([datetime]$_.date).Year -eq $refYear } | Select-Object -First 1

Write-Host (" Ref date (this week):  " + $refDate)
if ($prevRow) { Write-Host (" Prev week (~7d ago):   " + $prevRow.date) }
if ($ytdRow)  { Write-Host (" Year start:            " + $ytdRow.date) }

# ----------- Per-ticker fetch -----------

$companies = @()
$i = 0
foreach ($t in $tickers) {
    $i++
    $sym = $t.code + '.' + $t.market
    Write-Host ("[" + $i + "/" + $tickers.Count + "] " + $t.name + " (" + $sym + ")") -ForegroundColor Yellow

    $hist = Get-YahooHistory -symbol $sym
    $closeRef  = if ($hist.Count -gt 0) { $hist[-1] } else { $null }
    $closePrev = Find-ClosestClose -history $hist -targetDate $prevTarget
    $closeYtd  = $hist | Where-Object { ([datetime]$_.date).Year -eq $refYear } | Select-Object -First 1

    $price   = if ($closeRef)  { $closeRef.close }  else { $null }
    $wowPct  = if ($closeRef -and $closePrev -and $closePrev.close -gt 0) { (($closeRef.close / $closePrev.close) - 1.0) } else { $null }
    $ytdPct  = if ($closeRef -and $closeYtd  -and $closeYtd.close  -gt 0) { (($closeRef.close / $closeYtd.close)  - 1.0) } else { $null }

    Start-Sleep -Milliseconds 300
    $naver = Get-NaverSnapshot -code $t.code

    $companies += [PSCustomObject]@{
        code      = $t.code
        symbol    = $sym
        name      = $t.name
        category  = $t.category
        price     = $price
        mcap      = $naver.mcap
        per       = $naver.per
        pbr       = $naver.pbr
        fwdPer    = $naver.fwdPer
        fwdPbr    = $naver.fwdPbr
        eps       = $naver.eps
        bps       = $naver.bps
        wow       = $wowPct
        ytd       = $ytdPct
        priceRef  = if ($closeRef)  { @{ date=$closeRef.date;  close=$closeRef.close }  } else { $null }
        pricePrev = if ($closePrev) { @{ date=$closePrev.date; close=$closePrev.close } } else { $null }
        priceYtd  = if ($closeYtd)  { @{ date=$closeYtd.date;  close=$closeYtd.close }  } else { $null }
    }

    $perDisp    = if ($null -ne $naver.per)    { "PER=" + $naver.per }       else { "PER=NM" }
    $fwdPerDisp = if ($null -ne $naver.fwdPer) { "fPER=" + $naver.fwdPer }    else { "fPER=-" }
    $wowDisp    = if ($null -ne $wowPct)       { ("{0:P1}" -f $wowPct) }      else { "-" }
    Write-Host ("    price=" + $price + " | mcap=" + $naver.mcap + " | " + $perDisp + " | " + $fwdPerDisp + " | WoW=" + $wowDisp) -ForegroundColor DarkGray
}

# ----------- Save -----------

$result = [ordered]@{
    updated   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    updatedKr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    refDate   = $refDate
    prevDate  = if ($prevRow) { $prevRow.date } else { $null }
    ytdDate   = if ($ytdRow)  { $ytdRow.date }  else { $null }
    source    = 'Yahoo Finance (prices) + Naver Finance (mcap/PER/PBR)'
    companies = @($companies)
}

$out = Join-Path $root 'peer.json'
$json = $result | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($out, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host (" Saved -> " + $out + "  (" + ((Get-Item -LiteralPath $out).Length) + " bytes)") -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Cyan
