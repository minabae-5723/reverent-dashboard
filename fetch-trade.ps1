# =============================================================
#  Korea Customs OpenAPI fetcher (관세청 품목별 수출입실적 GW)
#  - API: data.go.kr #15101609
#  - Endpoint: http://apis.data.go.kr/1220000/Itemtrade/getItemtradeList
#  - Limit: max 1-year range per call → loop yearly
#  - Output: trade.json (월별 수출액·중량·단가)
#
#  Usage:
#    powershell -ExecutionPolicy Bypass -File .\fetch-trade.ps1
#    # optional: -StartYear 2020 -EndYear 2026
# =============================================================
param(
    [int]$StartYear = 2007,
    [int]$EndYear   = (Get-Date).Year
)

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

# Load API key from config.json
$configPath = Join-Path $root 'config.json'
if (-not (Test-Path $configPath)) {
    Write-Host "ERROR: config.json not found" -ForegroundColor Red
    exit 1
}
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$apiKey = $config.DATA_GO_KR_API_KEY
if (-not $apiKey -or $apiKey -like '*PASTE*') {
    Write-Host "ERROR: DATA_GO_KR_API_KEY not set in config.json" -ForegroundColor Red
    exit 1
}

# HS codes we care about
$HS_CODES = @(
    @{ key = 'ssd';  hs = '8523511000'; name = 'SSD'  }   # 기록이 안 된 매체 (solid-state non-volatile storage)
    @{ key = 'nand'; hs = '8542321030'; name = 'NAND' }   # 메모리(낸드플래시)
    @{ key = 'dram'; hs = '8542321010'; name = 'DRAM' }   # 메모리(디램, 칩만)
)

$baseUrl = 'http://apis.data.go.kr/1220000/Itemtrade/getItemtradeList'

function Fetch-YearForHs {
    param([string]$Hs, [int]$Year)
    $start = "${Year}01"
    $end   = "${Year}12"
    $url = "${baseUrl}?serviceKey=${apiKey}&strtYymm=${start}&endYymm=${end}&hsSgn=${Hs}&numOfRows=1000"
    try {
        $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
        [xml]$xml = $resp.Content
        if ($xml.response.header.resultCode -ne '00') {
            Write-Host ("    WARN [" + $Year + "] " + $xml.response.header.resultMsg) -ForegroundColor Yellow
            return @()
        }
        $items = @()
        foreach ($it in $xml.response.body.items.item) {
            if ($it.year -eq '총계') { continue }
            # year format from API: "YYYY.MM"
            if ($it.year -match '^(\d{4})\.(\d{2})$') {
                $yyyy = $matches[1]; $mm = $matches[2]
                $expDlr = [double]$it.expDlr
                $expWgt = [double]$it.expWgt
                $impDlr = [double]$it.impDlr
                $impWgt = [double]$it.impWgt
                $valueMn  = if ($expDlr -gt 0) { [Math]::Round($expDlr / 1000000.0, 0) } else { 0 }
                $unitUsdKg = if ($expWgt -gt 0) { [Math]::Round($expDlr / $expWgt, 2) } else { $null }
                $items += [PSCustomObject]@{
                    month      = "${yyyy}-${mm}"
                    value      = $valueMn       # $mn (수출액)
                    weight     = $expWgt        # kg (수출중량)
                    unitPrice  = $unitUsdKg     # USD/kg (단가 = expDlr / expWgt)
                    expDlrRaw  = $expDlr        # raw USD (수출액)
                    impDlrRaw  = $impDlr        # raw USD (수입액)
                    impWgtRaw  = $impWgt        # kg (수입중량)
                }
            }
        }
        return ,$items
    } catch {
        Write-Host ("    ERROR [" + $Year + "] " + $_.Exception.Message) -ForegroundColor Red
        return @()
    }
}

$result = [ordered]@{
    updated   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    updatedKr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    source    = 'data.go.kr #15101609 (관세청 품목별 수출입실적 GW)'
    range     = "${StartYear}-${EndYear}"
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host (" Trade data fetch (HS codes x years = {0} calls)" -f ($HS_CODES.Count * ($EndYear - $StartYear + 1))) -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

foreach ($spec in $HS_CODES) {
    Write-Host ""
    Write-Host (" [" + $spec.name + "]  HS " + $spec.hs) -ForegroundColor Yellow
    $allMonths = @()
    for ($yr = $StartYear; $yr -le $EndYear; $yr++) {
        $batch = Fetch-YearForHs -Hs $spec.hs -Year $yr
        $allMonths += $batch
        Start-Sleep -Milliseconds 150  # gentle rate
    }
    # Sort by month ascending
    $sorted = $allMonths | Sort-Object month
    $result[$spec.key] = @($sorted)
    $first = if ($sorted.Count -gt 0) { $sorted[0].month } else { '(empty)' }
    $last  = if ($sorted.Count -gt 0) { $sorted[-1].month } else { '(empty)' }
    Write-Host ("    -> " + $sorted.Count + " months  [" + $first + " .. " + $last + "]") -ForegroundColor Green
}

$outPath = Join-Path $root 'trade.json'

# Merge with existing trade.json if present:
# - Fetched months replace whatever was there (for revisions/잠정치→확정치)
# - Months outside fetched range are preserved as-is
$merged = $result
if (Test-Path -LiteralPath $outPath) {
    try {
        $existing = Get-Content -LiteralPath $outPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($spec in $HS_CODES) {
            $k = $spec.key
            $newRows = @($result[$k])
            $newMonths = @{}
            foreach ($r in $newRows) { $newMonths[$r.month] = $true }
            # Keep existing months not in new range
            $kept = @()
            if ($existing.PSObject.Properties.Name -contains $k) {
                foreach ($r in $existing.$k) {
                    if (-not $newMonths.ContainsKey($r.month)) { $kept += $r }
                }
            }
            # Combine and sort
            $combined = ($kept + $newRows) | Sort-Object month
            $merged[$k] = @($combined)
        }
        Write-Host ""
        Write-Host " (Merged with existing trade.json — historical months preserved)" -ForegroundColor DarkGray
    } catch {
        Write-Host (" WARN: existing trade.json parse failed, writing fresh: " + $_.Exception.Message) -ForegroundColor Yellow
    }
}

$json = $merged | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($outPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ""
Write-Host (" Saved -> " + $outPath + "  (" + ((Get-Item -LiteralPath $outPath).Length) + " bytes)") -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Cyan
