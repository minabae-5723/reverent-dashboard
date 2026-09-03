# =============================================================
#  trade.json 잠정치(provisional) 주입기
#
#  왜 필요한가:
#    관세청은 매월 1일 09:00에 전월 "잠정치"를, 15일에 "확정치"를 낸다.
#    그런데 품목별 수출입실적 OpenAPI(#15101609)는 15일 갱신분부터 전월이
#    올라온다. 즉 매월 1일 실행되는 monthly-trade-update는 구조적으로 전월
#    데이터를 API에서 받을 수 없다. 그 2주 공백을 이 스크립트로 메운다.
#
#  주입한 행은 prov=true 로 표시되고, 대시보드는 "잠정" 배지 + 차트 마지막
#  구간 점선으로 렌더한다. fetch-trade.ps1 의 merge 는 API가 반환한 월을
#  무조건 덮어쓰므로, 다음 달 실행 때 확정치로 자동 교체된다(수동 삭제 불필요).
#
#  Usage:
#    # 인라인 JSON
#    .\apply-provisional.ps1 -Month 2026-08 -Data '{"ssd":{"value":5979,"unitPrice":25164}}'
#
#    # 파일에서 (한글 깨짐 걱정 없이 여러 품목을 한 번에)
#    .\apply-provisional.ps1 -Month 2026-08 -InputJson .\prov-2026-08.json
#
#    # 미리보기만
#    .\apply-provisional.ps1 -Month 2026-08 -InputJson .\prov.json -DryRun
#
#  입력 JSON 형식 (품목 키는 trade.json 의 시리즈 키와 동일):
#    {
#      "ssd":  { "value": 5979,  "unitPrice": 25164  },
#      "nand": { "value": 2862,  "unitPrice": 100855 },
#      "dram": { "value": 15733, "unitPrice": 88523  },
#      "mcp":  { "value": 12225, "unitPrice": 98862  }
#    }
#    - value     : 수출액 $mn (필수)
#    - unitPrice : 단가 $/kg (선택) -> 있으면 weight = value*1e6/unitPrice 로 역산
#    - weight    : kg (선택) -> 직접 주면 unitPrice 를 역산
#    잠정치 1일 발표분은 금액만 있는 경우가 많다. 그때는 value 만 넣으면 되고,
#    weight/unitPrice 는 null 로 들어가 중량·단가 탭은 직전 확정월에 앵커링된다.
# =============================================================
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d{4}-\d{2}$')]
    [string]$Month,

    [string]$InputJson,
    [string]$Data,
    [switch]$DryRun,
    # 이미 확정치(prov 아님)가 들어있는 월을 잠정치로 덮어쓸 때만 필요.
    # 확정치를 잠정치로 되돌리는 건 거의 항상 실수이므로 기본 차단한다.
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

if (-not $InputJson -and -not $Data) {
    Write-Host "ERROR: -InputJson 또는 -Data 중 하나는 필요합니다." -ForegroundColor Red
    exit 1
}

# ── 입력 파싱 ────────────────────────────────────────────────
$raw = if ($InputJson) {
    if (-not (Test-Path -LiteralPath $InputJson)) {
        Write-Host "ERROR: 입력 파일 없음: $InputJson" -ForegroundColor Red
        exit 1
    }
    [IO.File]::ReadAllText((Resolve-Path -LiteralPath $InputJson))
} else { $Data }

try { $provInput = $raw | ConvertFrom-Json }
catch {
    Write-Host ("ERROR: 입력 JSON 파싱 실패 - " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

# ── trade.json 로드 ──────────────────────────────────────────
$outPath = Join-Path $root 'trade.json'
if (-not (Test-Path -LiteralPath $outPath)) {
    Write-Host "ERROR: trade.json 없음" -ForegroundColor Red
    exit 1
}
$j = [IO.File]::ReadAllText($outPath) | ConvertFrom-Json

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host (" 잠정치 주입 -> " + $Month + $(if ($DryRun) { "   [DRY RUN]" } else { "" })) -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

$applied = 0
$skipped = 0

foreach ($prop in $provInput.PSObject.Properties) {
    $key = $prop.Name
    $spec = $prop.Value

    if ($j.PSObject.Properties.Name -notcontains $key) {
        Write-Host ("  [SKIP] " + $key + " : trade.json 에 없는 시리즈") -ForegroundColor Yellow
        $skipped++
        continue
    }
    if ($null -eq $spec.value) {
        Write-Host ("  [SKIP] " + $key + " : value(수출액 `$mn) 누락") -ForegroundColor Yellow
        $skipped++
        continue
    }

    $series = @($j.$key)
    $existing = $series | Where-Object { $_.month -eq $Month }

    # 확정치 보호: API가 이미 실제 데이터를 넣어둔 월을 잠정치로 되돌리지 않는다.
    if ($existing -and $existing.prov -ne $true -and -not $Force) {
        Write-Host ("  [SKIP] " + $key + " : " + $Month + " 은 이미 확정치. 덮어쓰려면 -Force") -ForegroundColor Yellow
        $skipped++
        continue
    }

    $value = [double]$spec.value
    $unitPrice = $null
    $weight = $null

    if ($null -ne $spec.unitPrice -and [double]$spec.unitPrice -gt 0) {
        $unitPrice = [double]$spec.unitPrice
        $weight = [Math]::Round($value * 1e6 / $unitPrice, 0)
    } elseif ($null -ne $spec.weight -and [double]$spec.weight -gt 0) {
        $weight = [double]$spec.weight
        $unitPrice = [Math]::Round($value * 1e6 / $weight, 2)
    }

    $row = [PSCustomObject]@{
        month     = $Month
        value     = $value
        weight    = $weight
        unitPrice = $unitPrice
        expDlrRaw = $value * 1e6
        impDlrRaw = $null
        impWgtRaw = $null
        prov      = $true
    }

    $kept = @($series | Where-Object { $_.month -ne $Month })
    $j.$key = @(($kept + $row) | Sort-Object month)

    # 직전 월 대비 변화를 같이 찍어 입력 오타를 바로 잡을 수 있게 한다.
    $prevMonth = ([datetime]::ParseExact($Month, 'yyyy-MM', $null)).AddMonths(-1).ToString('yyyy-MM')
    $prev = $kept | Where-Object { $_.month -eq $prevMonth }
    $momV = if ($prev -and $prev.value) { "{0,7:N1}%" -f (($value / $prev.value - 1) * 100) } else { "      -" }
    $momP = if ($prev -and $prev.unitPrice -and $unitPrice) { "{0,7:N1}%" -f (($unitPrice / $prev.unitPrice - 1) * 100) } else { "      -" }

    $wTxt = if ($null -eq $weight) { "(공백)" } else { "{0,10:N0}" -f $weight }
    $pTxt = if ($null -eq $unitPrice) { "(공백)" } else { "{0,10:N0}" -f $unitPrice }
    Write-Host ("  [OK]   {0,-6} 금액 {1,8:N0} `$mn ({2} MoM)   단가 {3} `$/kg ({4} MoM)   물량 {5} kg" -f `
        $key.ToUpper(), $value, $momV, $pTxt, $momP, $wTxt) -ForegroundColor Green
    $applied++
}

Write-Host ""
if ($applied -eq 0) {
    Write-Host " 적용된 시리즈 없음. 파일을 건드리지 않습니다." -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan
    exit 1
}

if ($DryRun) {
    Write-Host (" DRY RUN - 저장하지 않음 (적용 예정 {0}건, 건너뜀 {1}건)" -f $applied, $skipped) -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Cyan
    exit 0
}

$j.updated   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$j.updatedKr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$j | Add-Member -NotePropertyName provisionalMonth -NotePropertyValue $Month -Force

$json = $j | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($outPath, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host (" 저장 완료 -> trade.json  (적용 {0}건, 건너뜀 {1}건)" -f $applied, $skipped) -ForegroundColor Green
Write-Host (" 다음 달 fetch-trade.ps1 실행 시 확정치로 자동 교체됩니다.") -ForegroundColor DarkGray
Write-Host "========================================================" -ForegroundColor Cyan
