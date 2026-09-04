# =============================================================
#  Korea Customs OpenAPI fetcher (관세청 품목별 수출입실적 GW)
#  - API: data.go.kr #15101609
#  - Endpoint: https://apis.data.go.kr/1220000/Itemtrade/getItemtradeList  (http/:80 times out)
#  - Limit: max 1-year range per call → loop yearly
#  - Output: trade.json (월별 수출액·중량·단가)
#
#  Usage:
#    powershell -ExecutionPolicy Bypass -File .\fetch-trade.ps1
#    # optional: -StartYear 2020 -EndYear 2026
# =============================================================
param(
    [int]$StartYear = 2007,
    [int]$EndYear   = (Get-Date).Year,
    # 기본은 잠정치 유지. 이 스위치를 주면 잠정치 행을 API 확정치로 갈아끼운다.
    [switch]$RefreshProvisional
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
    @{ key = 'mcp';  hs = '8542323000'; name = 'MCP'  }   # MCP (multi-chip package / HBM, 8542.32-3000)
)

$baseUrl = 'https://apis.data.go.kr/1220000/Itemtrade/getItemtradeList'

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
# - 잠정치(prov=true) 월은 그대로 지킨다. 확정치가 나와도 덮지 않는다 (-RefreshProvisional 로만 교체)
# - 그 외 fetched months 는 API 값으로 갱신
# - Months outside fetched range are preserved as-is
$merged = $result
if (Test-Path -LiteralPath $outPath) {
    try {
        $existing = Get-Content -LiteralPath $outPath -Raw -Encoding UTF8 | ConvertFrom-Json
        # 🔴 잠정치 기준 유지 (2026-09-03 사용자 지시)
        #   한 번 잠정치로 들어온 월은 확정치가 나와도 덮어쓰지 않는다. 보드 전체가
        #   같은 기준(잠정)으로 유지돼야 MoM/YoY 비교에 기준 혼재가 안 생기기
        #   때문이다. 확정치를 일부러 당겨오려면 -RefreshProvisional 을 준다.
        #   대신 확정치와 얼마나 벌어졌는지는 매번 찍어서 눈으로 볼 수 있게 한다.
        $divergence = @()
        $stillProv  = @()
        foreach ($spec in $HS_CODES) {
            $k = $spec.key
            $newRows = @($result[$k])
            $newMonths = @{}
            foreach ($r in $newRows) { $newMonths[$r.month] = $true }
            # Keep existing months not in new range, plus every provisional month
            $kept = @()
            $keptMonths = @{}
            if ($existing.PSObject.Properties.Name -contains $k) {
                foreach ($r in $existing.$k) {
                    if (-not $newMonths.ContainsKey($r.month)) {
                        $kept += $r
                        $keptMonths[$r.month] = $true
                        if ($r.prov -eq $true) { $stillProv += ("{0} {1}" -f $spec.name, $r.month) }
                    } elseif ($r.prov -eq $true -and -not $RefreshProvisional) {
                        # API가 확정치를 내놨지만 잠정치 기준을 유지한다
                        $kept += $r
                        $keptMonths[$r.month] = $true
                        $final = $newRows | Where-Object { $_.month -eq $r.month }
                        $diff = if ($r.value) { (($final.value - $r.value) / $r.value) * 100 } else { $null }
                        $divergence += [PSCustomObject]@{
                            name = $spec.name; month = $r.month
                            prov = $r.value; final = $final.value; diffPct = $diff
                        }
                    }
                }
            }
            # 잠정치로 지킨 월은 API 행을 버린다
            $incoming = @($newRows | Where-Object { -not $keptMonths.ContainsKey($_.month) })
            $combined = ($kept + $incoming) | Sort-Object month
            $merged[$k] = @($combined)
        }
        Write-Host ""
        Write-Host " (Merged with existing trade.json — historical months preserved)" -ForegroundColor DarkGray

        if ($divergence.Count -gt 0) {
            Write-Host ""
            Write-Host " 잠정치 유지 (확정치로 덮어쓰지 않음 — 참고용 괴리):" -ForegroundColor Cyan
            foreach ($s in $divergence) {
                $d = if ($null -eq $s.diffPct) { "-" } else { "{0,6:N1}%" -f $s.diffPct }
                Write-Host ("   {0,-6} {1}  잠정 {2,8:N0} (확정 {3,8:N0}) `$mn  괴리 {4}" -f `
                    $s.name, $s.month, $s.prov, $s.final, $d) -ForegroundColor Green
            }
            Write-Host ("   * 확정치로 갈아끼우려면: .\fetch-trade.ps1 -RefreshProvisional") -ForegroundColor DarkGray
        }
        if ($stillProv.Count -gt 0) {
            Write-Host ""
            Write-Host (" 아직 잠정치로 남은 월 (API 미반영): " + ($stillProv -join ', ')) -ForegroundColor Yellow
        }

        # 최신 확정월이 전월보다 뒤처져 있으면 잠정치 주입이 필요하다는 신호.
        $prevMonth = (Get-Date).AddMonths(-1).ToString('yyyy-MM')
        $latestFinal = @($merged[$HS_CODES[0].key] | Where-Object { $_.prov -ne $true } | Sort-Object month)[-1].month
        if ($latestFinal -lt $prevMonth) {
            Write-Host ""
            Write-Host (" 주의: API 최신 확정월은 {0}, 전월은 {1}." -f $latestFinal, $prevMonth) -ForegroundColor Yellow
            Write-Host ("       품목별 OpenAPI는 매월 15일 갱신이라 1일 실행분에는 전월이 없다.") -ForegroundColor DarkGray
            Write-Host ("       잠정치를 받으면: .\apply-provisional.ps1 -Month {0} -InputJson prov.json" -f $prevMonth) -ForegroundColor DarkGray
        }
    } catch {
        Write-Host (" WARN: existing trade.json parse failed, writing fresh: " + $_.Exception.Message) -ForegroundColor Yellow
    }
}

# provisionalMonth = 가장 최근 잠정 월. $result 를 매번 새로 짜기 때문에 다시
# 계산해주지 않으면 fetch 마다 사라진다.
$provMonths = @()
foreach ($spec in $HS_CODES) {
    foreach ($r in @($merged[$spec.key])) {
        if ($r.prov -eq $true -and $provMonths -notcontains $r.month) { $provMonths += $r.month }
    }
}
# @() 필수: 원소가 1개면 Sort-Object 가 스칼라 문자열을 돌려주고, 거기에 [-1] 을
# 걸면 마지막 "문자"('8')가 잡힌다.
$merged['provisionalMonth'] = if ($provMonths.Count -gt 0) { @($provMonths | Sort-Object)[-1] } else { $null }

$json = $merged | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($outPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ""
Write-Host (" Saved -> " + $outPath + "  (" + ((Get-Item -LiteralPath $outPath).Length) + " bytes)") -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Cyan
