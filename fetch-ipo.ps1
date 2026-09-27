# =============================================================
#  IPO 신규상장 fetcher (38커뮤니케이션 + Naver Finance for mcap)
#
#  Source: http://www.38.co.kr/html/fund/?o=nw  (신규상장 list)
#  Output: ipo.json
#
#  Per company:
#    - 38 table:   종목명, 상장일, 공모가, 현재가, 등락률 vs 공모가, code
#    - Naver:      시가총액 (억원, listed companies with numeric code only)
#
#  This script is ASCII-only — pattern matches use either tag/attr keys or
#  raw bytes; no Korean characters appear in the source.
#
#  Usage: powershell -ExecutionPolicy Bypass -File .\fetch-ipo.ps1
# =============================================================
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36'

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " IPO new-listings fetch (38.co.kr + Naver)" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# ---------- 1. Fetch 38커뮤니케이션 신규상장 ----------

$url38 = 'http://www.38.co.kr/html/fund/?o=nw'
try {
    # Use WebClient.DownloadData so we get raw bytes (no PS-side decode guessing).
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', $UA)
    $bytes = $wc.DownloadData($url38)
    $html = [System.Text.Encoding]::GetEncoding('EUC-KR').GetString($bytes)
    $wc.Dispose()
} catch {
    Write-Host ("ERROR fetching 38: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

# The 신규상장 table is the one with summary attribute. Each row has:
#   <a href="./?o=v&no=NNNN&l=">company name</a>     <-- col 1
#   <td>YYYY/MM/DD</td>                              <-- col 2 (상장일)
#   <td>현재가</td>                                  <-- col 3
#   <td>등락률 today</td>                            <-- col 4
#   <td>공모가</td>                                  <-- col 5
#   <td>등락률 vs 공모가</td>                        <-- col 6
#   <td>시초가</td>                                  <-- col 7
#   <td>시초/공모 %</td>                             <-- col 8
#   <td>거래대금</td>                                <-- col 9
#   <td>chart icon — code=XXXXXX in onClick</td>     <-- col 10

# Slice out the relevant table by anchoring on `<table ... summary=`.
$tblM = [regex]::Match($html, '<table[^>]*summary=[^>]*>(.*?)</table>', 'Singleline')
if (-not $tblM.Success) {
    Write-Host "ERROR: new-listings table not found" -ForegroundColor Red
    exit 1
}
$tableHtml = $tblM.Groups[1].Value

# Each row of interest starts with bgColor="#FFFFFF" or "#F8F8F8" (alternating bands).
$rowRe = '<tr\s+bgColor="#(?:FFFFFF|F8F8F8)"[^>]*>(.*?)</tr>'
$rowMatches = [regex]::Matches($tableHtml, $rowRe, [System.Text.RegularExpressions.RegexOptions]'Singleline,IgnoreCase')

Write-Host (" Rows found: " + $rowMatches.Count)

# Helper: convert HTML cell content -> trimmed plain text.
function Clean-Cell {
    param([string]$s)
    $t = $s -replace '<[^>]+>', '' -replace '&nbsp;', ' ' -replace '&amp;', '&'
    return ($t -replace '\s+', ' ').Trim()
}

# Parse percent like "+101.0%" / "-7.76%" / "-%" -> double or $null.
function Parse-Pct {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $clean = $s -replace '[%,\s]', ''
    if ($clean -match '^-?\d+(\.\d+)?$') { return [double]$clean / 100.0 }
    return $null
}

function Parse-Num {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $clean = $s -replace '[,\s]', ''
    if ($clean -match '^-?\d+(\.\d+)?$') { return [double]$clean }
    return $null
}

# Korean "스팩" (SPAC) — built from code points so the .ps1 stays ASCII-safe
# under PS 5.1's cp949 source decoding.
$spacKo = [string]([char]0xC2A4 + [char]0xD329)

# 38.co.kr code -> code Naver Finance actually serves. See use site below.
#   952509 -> 950260  INGENIA Therapeutics (Reg.S), listed 2026-08-18
$CodeOverride = @{
    '952509' = '950260'
}

$companies = @()
$skippedSpac = 0
foreach ($rm in $rowMatches) {
    $rowHtml = $rm.Groups[1].Value

    # 8 explicit <td> cells + 1 chart cell. Capture cells in order.
    $tdMatches = [regex]::Matches($rowHtml, '<td[^>]*>(.*?)</td>', [System.Text.RegularExpressions.RegexOptions]'Singleline,IgnoreCase')
    if ($tdMatches.Count -lt 9) { continue }

    $name      = Clean-Cell $tdMatches[0].Groups[1].Value
    # Strip trailing parenthetical (e.g. "코스모로보틱스(구.엑소아틀레트아시아)" → "코스모로보틱스",
    #                                       "케이뱅크(우)" → "케이뱅크",
    #                                       "채비(구.대영채비)" → "채비")
    $name = ($name -replace '\s*\([^)]*\)\s*$', '').Trim()
    $listDate  = Clean-Cell $tdMatches[1].Groups[1].Value
    $curPrice  = Parse-Num   (Clean-Cell $tdMatches[2].Groups[1].Value)
    $todayChg  = Parse-Pct   (Clean-Cell $tdMatches[3].Groups[1].Value)
    $ipoPrice  = Parse-Num   (Clean-Cell $tdMatches[4].Groups[1].Value)
    $curVsIpo  = Parse-Pct   (Clean-Cell $tdMatches[5].Groups[1].Value)
    $openPrice = Parse-Num   (Clean-Cell $tdMatches[6].Groups[1].Value)
    $openVsIpo = Parse-Pct   (Clean-Cell $tdMatches[7].Groups[1].Value)

    # Stock code lives in the chart icon onClick: chart_page_new.php3?code=XXXXXX
    $code = $null
    $codeM = [regex]::Match($rowHtml, "chart_page_new\.php3\?code=([A-Za-z0-9]+)")
    if ($codeM.Success) { $code = $codeM.Groups[1].Value }

    # 38.co.kr occasionally carries a code Naver Finance does not resolve
    # (foreign-domiciled listings, Reg.S tranches). Naver 302s to the front
    # page for those, so the mcap/curPrice scrape silently yields $null.
    # Map the bad code to the one Naver actually serves.
    if ($code -and $CodeOverride.ContainsKey($code)) { $code = $CodeOverride[$code] }

    # 38 detail page id (no=NNNN), for reference.
    $detailNo = $null
    $noM = [regex]::Match($rowHtml, '\?o=v&amp;no=(\d+)')
    if ($noM.Success) { $detailNo = [int]$noM.Groups[1].Value }

    # Normalize 상장일 to ISO (yyyy-MM-dd)
    $listIso = $null
    if ($listDate -match '^(\d{4})/(\d{1,2})/(\d{1,2})$') {
        $listIso = '{0:D4}-{1:D2}-{2:D2}' -f [int]$matches[1], [int]$matches[2], [int]$matches[3]
    }

    if ([string]::IsNullOrWhiteSpace($name)) { continue }

    # Skip SPACs — name contains "스팩" or "SPAC".
    if ($name -match ($spacKo + '|SPAC')) {
        $skippedSpac++
        continue
    }

    $companies += [PSCustomObject]@{
        name        = $name
        listDate    = $listDate
        listIso     = $listIso
        code        = $code
        detailNo    = $detailNo
        ipoPrice    = $ipoPrice
        curPrice    = $curPrice
        openPrice   = $openPrice
        todayChg    = $todayChg
        curVsIpo    = $curVsIpo
        openVsIpo   = $openVsIpo
        mcap        = $null   # filled below from Naver (anchor-close basis)
        mcapDate    = $null
    }
}

Write-Host (" Parsed " + $companies.Count + " IPO rows from 38.co.kr (skipped " + $skippedSpac + " SPACs)") -ForegroundColor Green

# ---------- 2. Augment with Naver Finance 시가총액 ----------

# 시가총액 = 전주 마지막 거래일 종가 기준 (user rule, 2026-09-28). Anchor =
# latest trading day before this week's Monday; on Sat/Sun the week just
# ended counts as "last week", so the anchor is that Friday (or earlier on
# holidays -- the daily chart simply has no row for closed days).
$todayD = (Get-Date).Date
$dowI = [int]$todayD.DayOfWeek                                   # Sun=0 .. Sat=6
if ($dowI -eq 0 -or $dowI -eq 6) { $weekStart = $todayD.AddDays((8 - $dowI) % 7) }
else                             { $weekStart = $todayD.AddDays(-($dowI - 1)) }
$anchorBefore = $weekStart.ToString('yyyyMMdd')

function Get-NaverSnapshot {
    # Returns @{ mcap = <억원, anchor-close basis>; mcapDate; curPrice = <원> }.
    # The old finance.naver.com/item/main.naver scrape (_market_sum) died when
    # Naver reskinned the PC page (Npay 증권), so every mcap came back $null.
    #   polling API -> marketValueFullRaw + closePriceRaw  => shares outstanding
    #   chart API   -> daily closes                         => anchor close
    param([string]$code)
    $empty = @{ mcap = $null; mcapDate = $null; curPrice = $null }
    if ([string]::IsNullOrWhiteSpace($code) -or $code.Length -lt 6) { return $empty }
    $hdr = @{ 'User-Agent' = $UA }
    try {
        $p = Invoke-RestMethod "https://polling.finance.naver.com/api/realtime/domestic/stock/${code}" -Headers $hdr -TimeoutSec 15
        $d = @($p.datas)[0]
        if (-not $d -or -not $d.marketValueFullRaw -or -not $d.closePriceRaw) { return $empty }
        $mvFull = [double]$d.marketValueFullRaw
        $price  = [double]$d.closePriceRaw
        if ($price -le 0) { return $empty }
        $shares = [Math]::Round($mvFull / $price)

        $start = $weekStart.AddDays(-21).ToString('yyyyMMdd')
        # PS 5.1 emits a JSON array as ONE object; assigning without @() and piping
        # the variable unrolls it (@() would nest it and hide all but 1-bar series).
        $bars = Invoke-RestMethod "https://api.stock.naver.com/chart/domestic/item/${code}/day?startDateTime=${start}0000&endDateTime=${anchorBefore}0000" -Headers $hdr -TimeoutSec 15
        $bar = $bars | Where-Object { $_.localDate -lt $anchorBefore } | Sort-Object localDate | Select-Object -Last 1
        if (-not $bar) {
            # Listed this week: no prior-week close yet -> leave mcap for the user input.
            return @{ mcap = $null; mcapDate = $null; curPrice = $price }
        }
        $mcap = [Math]::Round($shares * [double]$bar.closePrice / 1e8)   # 억원
        $ld = [string]$bar.localDate
        return @{ mcap = $mcap; mcapDate = ('{0}-{1}-{2}' -f $ld.Substring(0,4), $ld.Substring(4,2), $ld.Substring(6,2)); curPrice = $price }
    } catch {
        return $empty
    }
}

Write-Host " Augmenting market caps + current prices via Naver..."
$augCount = 0
$preIpoCount = 0
foreach ($c in $companies) {
    if (-not $c.code) { continue }
    $snap = Get-NaverSnapshot -code $c.code
    $touched = $false
    if ($null -ne $snap.mcap)     { $c.mcap     = $snap.mcap; $c.mcapDate = $snap.mcapDate; $touched = $true }
    if ($null -ne $snap.curPrice) { $c.curPrice = $snap.curPrice; $touched = $true }
    # Recompute "(curPrice - ipoPrice) / ipoPrice" with the updated current price.
    if ($null -ne $c.curPrice -and $null -ne $c.ipoPrice -and $c.ipoPrice -gt 0) {
        $c.curVsIpo = [Math]::Round(($c.curPrice - $c.ipoPrice) / $c.ipoPrice, 4)
    }
    if ($touched) { $augCount++ } else { $preIpoCount++ }
    Start-Sleep -Milliseconds 200
}
Write-Host (" Augmented " + $augCount + " / " + $companies.Count + " (pre-IPO without Naver page: " + $preIpoCount + ")") -ForegroundColor Green

# ---------- 2.5. Guard: not-yet-listed IPOs must not show a current price ----------
# 38/Naver sometimes return a pre-listing/grey value for stocks that haven't
# listed yet (listing date in the future), which then renders as a bogus 현재가.
# Clear every current-price-derived field for those; keep 공모가(ipoPrice) + mcap.
$today = (Get-Date).ToString('yyyy-MM-dd')
$nulledFuture = 0
foreach ($c in $companies) {
    if ($c.listIso -and ($c.listIso -gt $today)) {
        $c.curPrice  = $null
        $c.openPrice = $null
        $c.todayChg  = $null
        $c.curVsIpo  = $null
        $c.openVsIpo = $null
        $nulledFuture++
    }
}
Write-Host (" Future-listing rows cleared of current price: " + $nulledFuture + " (today=" + $today + ")") -ForegroundColor Yellow

# ---------- 3. Sort + save ----------

# Sort by listing date descending (most recent first).
$sorted = $companies | Sort-Object -Property listIso -Descending

$result = [ordered]@{
    updated   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    updatedKr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    source    = '38.co.kr new-listings (o=nw) + Naver Finance (market cap)'
    companies = @($sorted)
}

$out = Join-Path $root 'ipo.json'
$json = $result | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($out, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host (" Saved -> " + $out + "  (" + ((Get-Item -LiteralPath $out).Length) + " bytes)") -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Cyan
