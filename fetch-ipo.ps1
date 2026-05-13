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

$companies = @()
$skippedSpac = 0
foreach ($rm in $rowMatches) {
    $rowHtml = $rm.Groups[1].Value

    # 8 explicit <td> cells + 1 chart cell. Capture cells in order.
    $tdMatches = [regex]::Matches($rowHtml, '<td[^>]*>(.*?)</td>', [System.Text.RegularExpressions.RegexOptions]'Singleline,IgnoreCase')
    if ($tdMatches.Count -lt 9) { continue }

    $name      = Clean-Cell $tdMatches[0].Groups[1].Value
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
        mcap        = $null   # filled below from Naver
    }
}

Write-Host (" Parsed " + $companies.Count + " IPO rows from 38.co.kr (skipped " + $skippedSpac + " SPACs)") -ForegroundColor Green

# ---------- 2. Augment with Naver Finance 시가총액 ----------

function Get-NaverMcap {
    param([string]$code)
    # Only numeric 6-digit codes are supported by Naver's main.naver?code= path.
    if ($code -notmatch '^\d{6}$') { return $null }
    $url = "https://finance.naver.com/item/main.naver?code=${code}"
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', $UA)
        $raw = $wc.DownloadData($url)
        $wc.Dispose()
        $html = [System.Text.Encoding]::GetEncoding('EUC-KR').GetString($raw)
        $mcapM = [regex]::Match($html, 'id="_market_sum"[^>]*>(.*?)</em>', 'Singleline')
        if ($mcapM.Success) {
            $inner = $mcapM.Groups[1].Value -replace '<[^>]+>', '' -replace '&nbsp;', ' '
            $nums = @([regex]::Matches($inner, '[\d,]+') | ForEach-Object { [double]($_.Value -replace ',', '') })
            if ($nums.Count -ge 2) { return ($nums[0] * 10000) + $nums[1] }
            elseif ($nums.Count -eq 1) { return $nums[0] }
        }
    } catch {}
    return $null
}

Write-Host " Augmenting market caps via Naver..."
$augCount = 0
foreach ($c in $companies) {
    if ($c.code -and $c.code -match '^\d{6}$') {
        $mcap = Get-NaverMcap -code $c.code
        if ($null -ne $mcap) {
            $c.mcap = $mcap
            $augCount++
        }
        Start-Sleep -Milliseconds 200
    }
}
Write-Host (" Augmented " + $augCount + " / " + $companies.Count) -ForegroundColor Green

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
