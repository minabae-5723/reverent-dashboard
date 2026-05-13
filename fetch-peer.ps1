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
    $url = "https://finance.naver.com/item/main.naver?code=${code}"
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent $UA -TimeoutSec 15
        $rawBytes = [System.Text.Encoding]::GetEncoding('iso-8859-1').GetBytes($r.Content)
        $html = [System.Text.Encoding]::GetEncoding('EUC-KR').GetString($rawBytes)

        $result = [ordered]@{ mcap=$null; per=$null; pbr=$null; eps=$null; bps=$null; fwdPer=$null; fwdPbr=$null }

        # Market cap: Naver renders inside <em id="_market_sum"> ... </em>
        #   Large caps (>= 1 trillion KRW): "1,655<JO> 9,584" (two numbers, first=jo, second=eok)
        #   Small caps (< 1 trillion KRW):  "3,069"           (one number = eok)
        # The Korean unit chars ("조", "억") sit between/after the numbers.
        # We avoid matching Korean directly (PS 5.1 source-encoding pitfalls) and
        # just pull all numeric groups in the captured block.
        $mcapM = [regex]::Match($html, 'id="_market_sum"[^>]*>(.*?)</em>', 'Singleline')
        if ($mcapM.Success) {
            $raw = $mcapM.Groups[1].Value -replace '<[^>]+>', '' -replace '&nbsp;', ' '
            $nums = @([regex]::Matches($raw, '[\d,]+') | ForEach-Object { [double]($_.Value -replace ',', '') })
            if ($nums.Count -ge 2) {
                # First number = 조 (trillions), second = 억 (hundred-millions).
                # Convert to 억원: 1조 = 10,000억.
                $result.mcap = ($nums[0] * 10000) + $nums[1]
            } elseif ($nums.Count -eq 1) {
                # Single number — already in 억원 unit.
                $result.mcap = $nums[0]
            }
        }

        foreach ($key in @('per','pbr','eps','bps')) {
            $m = [regex]::Match($html, ('id="_' + $key + '"[^>]*>(.*?)</em>'), 'Singleline')
            if ($m.Success) {
                $v = ($m.Groups[1].Value -replace '<[^>]+>', '' -replace ',', '').Trim()
                if ($v -match '^-?\d+(\.\d+)?$') {
                    $result[$key] = [double]$v
                }
            }
        }

        # Forward (FY1) PER & PBR from 기업실적분석 table.
        # Layout: 3 actual annual columns + 1 FY1 estimate annual + 6 quarterly columns.
        # PER row anchored on class th_cop_anal20, PBR row on th_cop_anal21.
        # The 4th <td> in document order = FY1 (next fiscal year) estimate.
        $fwdMap = @{ fwdPer = 'th_cop_anal20'; fwdPbr = 'th_cop_anal21' }
        foreach ($key in $fwdMap.Keys) {
            $cls = $fwdMap[$key]
            $rowM = [regex]::Match($html, ('<tr[^>]*>\s*<th[^>]*' + $cls + '[^>]*>.*?</tr>'), 'Singleline')
            if ($rowM.Success) {
                $tdMatches = [regex]::Matches($rowM.Value, '<td[^>]*>(.*?)</td>', 'Singleline')
                if ($tdMatches.Count -ge 4) {
                    $cell = $tdMatches[3].Groups[1].Value
                    $val = ($cell -replace '<[^>]+>', '' -replace '&nbsp;', '' -replace '[,\s]', '').Trim()
                    if ($val -match '^-?\d+(\.\d+)?$') {
                        $result[$key] = [double]$val
                    }
                }
            }
        }

        return $result
    } catch {
        Write-Host ("    Naver error " + $code + ": " + $_.Exception.Message) -ForegroundColor DarkYellow
        return @{ mcap=$null; per=$null; pbr=$null; eps=$null; bps=$null }
    }
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
