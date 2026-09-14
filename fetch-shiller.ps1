# =============================================================
#  Shiller P/E (CAPE) fetcher
#  Source: https://www.multpl.com/shiller-pe/table/by-month
#  Output: shiller.json
#
#  Usage: powershell -ExecutionPolicy Bypass -File .\fetch-shiller.ps1
#         powershell -ExecutionPolicy Bypass -File .\fetch-shiller.ps1 -Quiet
#
#  -Quiet suppresses console output for the 5-min auto-refresh timer
#  (refresh-push-market.ps1), matching fetch-fedwatch.ps1's convention.
# =============================================================
param([switch]$Quiet)
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root
function Say { param([string]$m, [string]$c = 'Gray') if (-not $Quiet) { Write-Host $m -ForegroundColor $c } }

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36'
$url = 'https://www.multpl.com/shiller-pe/table/by-month'

Say ""
Say "Fetching Shiller P/E table..." Yellow
try {
    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent $UA -TimeoutSec 20
    $html = $resp.Content
} catch {
    Say ("ERROR: " + $_.Exception.Message) Red
    exit 1
}

# Extract <tr>...<td>Date</td><td>Value</td></tr> rows from #datatable
# Use multiline regex
$rows = @()
$rowPattern = '<tr class="(?:odd|even)">\s*<td>([^<]+)</td>\s*<td>\s*(?:&#x2002;)?\s*([\d.]+)\s*</td>\s*</tr>'
$matches = [regex]::Matches($html, $rowPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
foreach ($m in $matches) {
    $dateStr = $m.Groups[1].Value.Trim()
    $value = [double]$m.Groups[2].Value.Trim()
    # Parse date "Mon DD, YYYY"
    try {
        $dt = [datetime]::ParseExact($dateStr, 'MMM d, yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        try { $dt = [datetime]::ParseExact($dateStr, 'MMM dd, yyyy', [System.Globalization.CultureInfo]::InvariantCulture) }
        catch { Say ("  skip unparseable date: " + $dateStr) DarkGray; continue }
    }
    $rows += [PSCustomObject]@{
        date  = $dt.ToString('yyyy-MM-dd')
        month = $dt.ToString('yyyy-MM')
        value = $value
        raw   = $dateStr
    }
}

if ($rows.Count -eq 0) {
    Say "ERROR: no rows parsed (page structure may have changed)" Red
    exit 1
}

# First row from page = latest spot (could be mid-month).
# Use it as "current" and dedupe by month — for the current month we
# replace the month-start snapshot with this fresher spot value.
$latest = $rows[0]

# Build monthly series in ASC order, latest month uses spot value
$byMonth = @{}
foreach ($r in $rows) {
    # Newer rows overwrite older for the same month (but rows are already
    # newest-first → first occurrence wins via ContainsKey check)
    if (-not $byMonth.ContainsKey($r.month)) {
        $byMonth[$r.month] = $r
    }
}

$monthly = $byMonth.Values | Sort-Object month | ForEach-Object {
    [PSCustomObject]@{ month = $_.month; value = $_.value }
}

$result = [ordered]@{
    updated   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    updatedKr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    source    = 'multpl.com/shiller-pe/table/by-month'
    latest    = [ordered]@{
        date  = $latest.date
        raw   = $latest.raw
        value = $latest.value
    }
    monthly   = @($monthly)
}

$out = Join-Path $root 'shiller.json'
$json = $result | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($out, $json, (New-Object System.Text.UTF8Encoding($false)))

Say ""
Say (" Latest: " + $latest.raw + "  =>  " + $latest.value) Green
Say (" Monthly rows: " + $monthly.Count + "  [" + $monthly[0].month + " .. " + $monthly[-1].month + "]") Green
Say (" Saved -> " + $out + "  (" + ((Get-Item -LiteralPath $out).Length) + " bytes)") Green
