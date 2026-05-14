# =============================================================
#  Fed Rate Monitor (FOMC probability) fetcher
#  Source: Investing.com /central-banks/fed-rate-monitor
#          (aggregates CME Fed Funds Futures-implied probabilities,
#           same underlying data as CME FedWatch tool)
#  Output: fedwatch.json
#
#  Usage: powershell -ExecutionPolicy Bypass -File .\fetch-fedwatch.ps1
# =============================================================
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36'
$url = 'https://www.investing.com/central-banks/fed-rate-monitor'

Write-Host ""
Write-Host "Fetching Fed Rate Monitor..." -ForegroundColor Yellow
try {
    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent $UA -TimeoutSec 25
    $html = $resp.Content
} catch {
    Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

# Split by cardName_<N> sections — each is one FOMC meeting card.
# Use a forward-looking regex to capture one card's content up to the next.
$cardPattern = 'cardName_(\d+)">\s*([A-Za-z]+ \d{1,2}, \d{4})\s*</div>(.*?)(?=cardName_\d+">|</body>)'
$cardMatches = [regex]::Matches($html, $cardPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

if ($cardMatches.Count -eq 0) {
    Write-Host "ERROR: no FOMC cards found (page structure may have changed)" -ForegroundColor Red
    exit 1
}

$meetings = @()
foreach ($cm in $cardMatches) {
    $cardIdx = [int]$cm.Groups[1].Value
    $dateStr = $cm.Groups[2].Value.Trim()
    $body    = $cm.Groups[3].Value

    # Parse meeting date to ISO
    $iso = $null
    try {
        $dt = [datetime]::ParseExact($dateStr, 'MMM d, yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
        $iso = $dt.ToString('yyyy-MM-dd')
    } catch {
        try {
            $dt = [datetime]::ParseExact($dateStr, 'MMM dd, yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
            $iso = $dt.ToString('yyyy-MM-dd')
        } catch {}
    }

    # Meeting time
    $meetingTime = $null
    $mt = [regex]::Match($body, '<span>\s*Meeting Time:\s*</span>\s*<i>([^<]+)</i>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($mt.Success) { $meetingTime = $mt.Groups[1].Value.Trim() }

    # Future price (Fed funds futures contract price → implied rate = 100 - price)
    $futurePrice = $null
    $fp = [regex]::Match($body, '<span>\s*Future Price:\s*</span>\s*<i>([^<]+)</i>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($fp.Success) {
        $fpText = ($fp.Groups[1].Value -replace '[,\s]', '')
        if ($fpText -match '^-?\d+(\.\d+)?$') { $futurePrice = [double]$fpText }
    }

    # Last updated timestamp
    $lastUpdate = $null
    $lu = [regex]::Match($body, 'class="fedUpdate">\s*Updated:\s*([^<]+)<', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($lu.Success) { $lastUpdate = $lu.Groups[1].Value.Trim() }

    # Probability rows from fedRateTbl
    $probs = @()
    $rowPattern = '<tr>\s*<td class="left">([^<]+?)<span[^>]*>.*?</td>\s*<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*</tr>'
    $rowMatches = [regex]::Matches($body, $rowPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    foreach ($rm in $rowMatches) {
        $rangeText = $rm.Groups[1].Value.Trim()
        $cur  = ($rm.Groups[2].Value -replace '[%\s,]', '')
        $prev = ($rm.Groups[3].Value -replace '[%\s,]', '')
        $week = ($rm.Groups[4].Value -replace '[%\s,]', '')
        # Investing.com uses "&mdash;" (HTML entity for em-dash) or a hyphen
        # for cells with no data — semantically 0% (the rate band has zero
        # probability or did not exist in the previous snapshot). Treat as 0
        # so the matrix renders correctly. Em-dash code points (U+2014, U+2013)
        # are checked via [char] to keep the .ps1 ASCII-safe under PS5.1.
        $mdash1 = [string][char]0x2014  # em dash
        $mdash2 = [string][char]0x2013  # en dash
        $parse = {
            param($s)
            if ($s -match '^-?\d+(\.\d+)?$') { return [double]$s }
            if ($s -eq '&mdash;' -or $s -eq '-' -or $s -eq '' -or
                $s -eq $mdash1 -or $s -eq $mdash2) { return 0.0 }
            return $null
        }.GetNewClosure()
        $probs += [PSCustomObject]@{
            range    = $rangeText
            current  = & $parse $cur
            prevDay  = & $parse $prev
            prevWeek = & $parse $week
        }
    }

    if ($probs.Count -gt 0) {
        $meetings += [PSCustomObject]@{
            idx          = $cardIdx
            date         = $dateStr
            iso          = $iso
            meetingTime  = $meetingTime
            futurePrice  = $futurePrice
            lastUpdate   = $lastUpdate
            probabilities = @($probs)
        }
    }
}

# Sort meetings by ISO date (chronological, soonest first)
$sorted = $meetings | Sort-Object iso

$result = [ordered]@{
    updated   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    updatedKr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    source    = 'investing.com/central-banks/fed-rate-monitor (CME Fed Funds Futures)'
    meetings  = @($sorted)
}

$out = Join-Path $root 'fedwatch.json'
$json = $result | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($out, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host (" Meetings parsed: " + $sorted.Count) -ForegroundColor Green
if ($sorted.Count -gt 0) {
    foreach ($m in $sorted | Select-Object -First 3) {
        $topRange = $m.probabilities | Sort-Object -Property current -Descending | Select-Object -First 1
        Write-Host ("   " + $m.date + "  →  most likely " + $topRange.range + " (" + $topRange.current + "%)") -ForegroundColor DarkGray
    }
}
Write-Host (" Saved -> " + $out + "  (" + ((Get-Item -LiteralPath $out).Length) + " bytes)") -ForegroundColor Green
