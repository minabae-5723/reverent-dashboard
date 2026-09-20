# =============================================================
#  Fed Rate Monitor (FOMC probability) fetcher -> fedwatch.json
#
#  WHY NOT SCRAPE INVESTING.COM ANY MORE
#  The previous version scraped investing.com/central-banks/fed-rate-monitor.
#  That endpoint now returns HTTP 403 to every raw HTTP client from this
#  machine - verified with a plain UA, a full browser header set, the .kr
#  domain, and CME's own page. It only loads through a real browser, which an
#  unattended run does not have, so the file went stale.
#
#  WHAT THIS DOES INSTEAD
#  Investing is not an independent source: it renders CME 30-Day Fed Funds
#  futures. Yahoo publishes the same contracts (ZQ) and the prices match
#  Investing tick for tick (verified 2026-08-10: Sep 96.315 vs 96.315,
#  Oct 96.250 vs 96.250). So this computes the probabilities straight from the
#  futures using CME's own methodology, which means:
#    - it runs unattended (no 403),
#    - it tracks near-live (fed funds futures trade ~23h/day),
#    - it uses the identical underlying data Investing displays.
#
#  METHOD (standard CME FedWatch)
#    implied average EFFR for a month = 100 - futures price
#    A month containing a meeting splits into pre- and post-decision periods:
#      implied = (dOld/N)*rPrev + (dNew/N)*rNew,  dOld = meetingDay - 1
#    Solve for rNew, chain meeting to meeting, and turn each step into a
#    per-meeting hike probability p = (rNew - rPrev)/0.25. The distribution
#    across rate buckets is the running binomial convolution of those p's.
#
#  Base rate comes from the NY Fed EFFR API (not the target midpoint) because
#  the probabilities are very sensitive to it - 1bp of base error moves a
#  probability ~4pp. Cross-check: the meeting-free spot month contract implies
#  the same rate (2026-08-10: EFFR 3.63 vs Aug contract 3.630).
#
#  Validated against Investing's published table on 2026-08-10:
#    Sep  hike 44.0% (Investing 43.4%)
#    Oct  38.6/47.7/13.6% (Investing 41.0/47.1/12.0%)
#
#  ASCII-only comments (PS 5.1 reads .ps1 as cp949).
#  Usage: powershell -File .\fetch-fedwatch.ps1
# =============================================================
param([switch]$Quiet)

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

# ---------------------------------------------------------------
# FOMC decision dates. Rates take effect the day of the decision.
# UPDATE ONCE A YEAR when the Fed publishes the next calendar.
# ---------------------------------------------------------------
$FOMC = @(
    @{ date = '2026-09-16'; time = '02:00PM ET' }
    @{ date = '2026-10-28'; time = '02:00PM ET' }
    @{ date = '2026-12-09'; time = '02:00PM ET' }
    @{ date = '2027-01-27'; time = '01:00PM ET' }
    @{ date = '2027-03-17'; time = '02:00PM ET' }
    @{ date = '2027-04-28'; time = '02:00PM ET' }
)

# Drop meetings that have already happened. A past meeting still in the chain
# poisons every step after it: its implied "hike" clamps to 0/1 and the carried
# $rPrev is then wrong, collapsing all later buckets to a bogus 100%.
$FOMC = @($FOMC | Where-Object { [DateTime]::Parse($_.date) -ge (Get-Date).Date })

# CME month codes for futures symbols
$MCODE = @{ 1='F'; 2='G'; 3='H'; 4='J'; 5='K'; 6='M'; 7='N'; 8='Q'; 9='U'; 10='V'; 11='X'; 12='Z' }

function Say { param([string]$m, [string]$c = 'Gray') if (-not $Quiet) { Write-Host $m -ForegroundColor $c } }

# ---------------------------------------------------------------
# 1. Effective fed funds rate + current target band (NY Fed)
# ---------------------------------------------------------------
function Get-EFFR {
    try {
        $r = Invoke-RestMethod -Uri 'https://markets.newyorkfed.org/api/rates/unsecured/effr/last/1.json' -UserAgent $UA -TimeoutSec 25
        $row = $r.refRates | Select-Object -First 1
        return [PSCustomObject]@{
            rate = [double]$row.percentRate
            from = [double]$row.targetRateFrom
            to   = [double]$row.targetRateTo
            date = $row.effectiveDate
        }
    } catch {
        Say ("  EFFR fetch failed: " + $_.Exception.Message) 'Red'
        return $null
    }
}

# ---------------------------------------------------------------
# 2. ZQ futures closes (daily history so prev-day / prev-week work)
#    Returns an ordered list of @{date; close} oldest-first.
# ---------------------------------------------------------------
function Get-ZQ {
    param([int]$Year, [int]$Month)
    $sym = 'ZQ' + $MCODE[$Month] + ($Year % 100).ToString('00') + '.CBT'
    foreach ($h in @('query1.finance.yahoo.com', 'query2.finance.yahoo.com')) {
        try {
            $r = Invoke-RestMethod -Uri "https://$h/v8/finance/chart/${sym}?interval=1d&range=1mo" -UserAgent $UA -TimeoutSec 25
            $res = $r.chart.result[0]
            $ts = $res.timestamp; $cl = $res.indicators.quote[0].close
            $bars = @()
            for ($i = 0; $i -lt $ts.Count; $i++) {
                if ($null -ne $cl[$i] -and $cl[$i] -gt 0) {
                    $bars += [PSCustomObject]@{
                        date  = [DateTimeOffset]::FromUnixTimeSeconds($ts[$i]).UtcDateTime.ToString('yyyy-MM-dd')
                        close = [double]$cl[$i]
                    }
                }
            }
            if ($bars.Count -gt 0) { return [PSCustomObject]@{ symbol = $sym; bars = @($bars) } }
        } catch { Start-Sleep -Milliseconds 300 }
    }
    Say ("  no data for " + $sym) 'Yellow'
    return $null
}

# ---------------------------------------------------------------
# 3. Chain the meetings and build the bucket distribution.
#    $priceAt = scriptblock (year, month) -> futures price, or $null.
# ---------------------------------------------------------------
function Build-Probabilities {
    param([double]$Effr, [double]$BandFrom, $PriceAt)

    $rPrev = $Effr
    $dist  = @(1.0)          # dist[k] = P(k hikes so far)
    $out   = @()

    foreach ($m in $FOMC) {
        $d = [DateTime]::Parse($m.date)
        $price = & $PriceAt $d.Year $d.Month
        if ($null -eq $price) { continue }

        $implied = 100.0 - $price
        $n       = [DateTime]::DaysInMonth($d.Year, $d.Month)
        $dOld    = $d.Day - 1
        $dNew    = $n - $dOld
        if ($dNew -le 0) { continue }

        $rNew = (($implied * $n) - ($dOld * $rPrev)) / $dNew
        $p    = ($rNew - $rPrev) / 0.25
        if ($p -lt 0) { $p = 0.0 }        # this build tracks hikes only
        if ($p -gt 1) { $p = 1.0 }

        # convolve one more binomial step onto the running distribution
        $next = New-Object 'double[]' ($dist.Count + 1)
        for ($k = 0; $k -lt $dist.Count; $k++) {
            $next[$k]     += $dist[$k] * (1 - $p)
            $next[$k + 1] += $dist[$k] * $p
        }
        $dist = $next

        # map buckets to 25bp target ranges off the current band floor
        $probs = @()
        for ($k = 0; $k -lt $dist.Count; $k++) {
            $pct = [Math]::Round($dist[$k] * 100, 1)
            if ($pct -lt 0.05) { continue }
            $lo = $BandFrom + (0.25 * $k)
            $probs += [PSCustomObject]@{
                range   = ('{0:N2} - {1:N2}' -f $lo, ($lo + 0.25))
                current = $pct
            }
        }

        $out += [PSCustomObject]@{
            date        = $d.ToString('MMM dd, yyyy', [Globalization.CultureInfo]::InvariantCulture)
            iso         = $m.date
            meetingTime = ($d.ToString('MMM dd, yyyy', [Globalization.CultureInfo]::InvariantCulture) + ' ' + $m.time)
            futurePrice = [Math]::Round($price, 4)
            impliedRate = [Math]::Round($implied, 4)
            hikeProb    = [Math]::Round($p * 100, 1)
            probabilities = @($probs)
        }
        $rPrev = $rNew
    }
    return @($out)
}

# ---------------------------------------------------------------
Say ""
Say "Fed Rate Monitor - computing from CME fed funds futures" 'Cyan'

$effr = Get-EFFR
if (-not $effr) { Say "FATAL: no EFFR, leaving fedwatch.json untouched" 'Red'; exit 1 }
Say ("  EFFR " + $effr.rate + "%  target " + $effr.from + "-" + $effr.to + "  (" + $effr.date + ")")

# Pull every contract month a meeting falls in
$series = @{}
foreach ($m in $FOMC) {
    $d = [DateTime]::Parse($m.date)
    $key = "{0}-{1:00}" -f $d.Year, $d.Month
    if (-not $series.ContainsKey($key)) {
        $z = Get-ZQ -Year $d.Year -Month $d.Month
        if ($z) { $series[$key] = $z }
        Start-Sleep -Milliseconds 200
    }
}
if ($series.Count -eq 0) { Say "FATAL: no futures data, leaving fedwatch.json untouched" 'Red'; exit 1 }

# Price accessor at an offset from the latest bar (0 = latest, 1 = prev day, 5 = ~prev week)
function New-PriceAt { param([int]$Back)
    return {
        param($y, $mo)
        $k = "{0}-{1:00}" -f $y, $mo
        if (-not $series.ContainsKey($k)) { return $null }
        $b = $series[$k].bars
        $i = $b.Count - 1 - $Back
        if ($i -lt 0) { return $null }
        return $b[$i].close
    }.GetNewClosure()
}

$cur  = Build-Probabilities -Effr $effr.rate -BandFrom $effr.from -PriceAt (New-PriceAt 0)
$prevD = Build-Probabilities -Effr $effr.rate -BandFrom $effr.from -PriceAt (New-PriceAt 1)
$prevW = Build-Probabilities -Effr $effr.rate -BandFrom $effr.from -PriceAt (New-PriceAt 5)

if ($cur.Count -eq 0) { Say "FATAL: nothing computed, leaving fedwatch.json untouched" 'Red'; exit 1 }

# Merge prev-day / prev-week onto the current rows, matched by range label
$meetings = @()
for ($i = 0; $i -lt $cur.Count; $i++) {
    $c = $cur[$i]
    $pd = if ($i -lt $prevD.Count) { $prevD[$i] } else { $null }
    $pw = if ($i -lt $prevW.Count) { $prevW[$i] } else { $null }
    $probs = foreach ($pr in $c.probabilities) {
        $dv = if ($pd) { ($pd.probabilities | Where-Object { $_.range -eq $pr.range } | Select-Object -First 1).current } else { $null }
        $wv = if ($pw) { ($pw.probabilities | Where-Object { $_.range -eq $pr.range } | Select-Object -First 1).current } else { $null }
        [PSCustomObject]@{
            range    = $pr.range
            current  = $pr.current
            prevDay  = if ($null -ne $dv) { $dv } else { 0 }
            prevWeek = if ($null -ne $wv) { $wv } else { 0 }
        }
    }
    $meetings += [PSCustomObject]@{
        idx           = $i
        date          = $c.date
        iso           = $c.iso
        meetingTime   = $c.meetingTime
        futurePrice   = $c.futurePrice
        impliedRate   = $c.impliedRate
        hikeProb      = $c.hikeProb
        probabilities = @($probs)
    }
    Say ("  {0}  px={1,8:N3}  implied={2,6:N3}%  hike={3,5:N1}%  buckets={4}" -f `
        $c.date, $c.futurePrice, $c.impliedRate, $c.hikeProb, $c.probabilities.Count)
}

$now = Get-Date
$out = [ordered]@{
    updated   = $now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    updatedKr = $now.ToString('yyyy-MM-dd HH:mm:ss')
    source    = 'CME 30-Day Fed Funds Futures (Yahoo ZQ) + NY Fed EFFR - CME FedWatch methodology'
    effr      = $effr.rate
    targetFrom = $effr.from
    targetTo   = $effr.to
    effrDate   = $effr.date
    meetings   = @($meetings)
}
$json = $out | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText((Join-Path $root 'fedwatch.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
Say ("`n Saved -> fedwatch.json  ({0:N0} bytes)" -f (Get-Item (Join-Path $root 'fedwatch.json')).Length) 'Green'
Say ""
