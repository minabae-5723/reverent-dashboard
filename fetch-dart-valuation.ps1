# =============================================================
#  DART OpenAPI valuation fetcher (Korean corporate financials)
#
#  Pulls latest disclosed financial statements (CFS / consolidated) from DART,
#  extracts P&L + balance-sheet items into a Reverent valuation table.
#  This script is ASCII-only — PS 5.1 reads .ps1 as cp949 and breaks Korean
#  string literals. We rely on DART's account_id (IFRS taxonomy, English) for
#  field lookup; account_nm fallbacks are passed as Unicode code-point arrays.
#
#  Output: valuation-{corp_code}.json (one company per file).
#  Units : 100M KRW (eok-won). DART returns raw won, we divide by 1e8.
#
#  Usage:
#    powershell -ExecutionPolicy Bypass -File .\fetch-dart-valuation.ps1 -CorpCode "01310241" -CorpName "Dunamu"
# =============================================================
param(
    [string]$CorpName = '',
    [string]$CorpCode = '',
    [int]$Year       = 2025
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

# Load API key from config.json (gitignored)
$cfg = Get-Content (Join-Path $root 'config.json') -Raw | ConvertFrom-Json
$DART_KEY = $cfg.DART_API_KEY
if (-not $DART_KEY) {
    Write-Host "FATAL: DART_API_KEY missing in config.json" -ForegroundColor Red
    exit 1
}

if (-not $CorpCode) {
    Write-Host "ERROR: -CorpCode required (e.g. 01310241 for Dunamu)" -ForegroundColor Red
    exit 1
}
if (-not $CorpName) { $CorpName = "corp_$CorpCode" }
Write-Host ("Company: " + $CorpName + "  corp_code=" + $CorpCode) -ForegroundColor Green

# ── Fetch financial statements ────────────────────────────
function Fetch-DartStatements {
    param([string]$Corp, [int]$BsnsYear, [string]$ReprtCode, [string]$FsDiv = 'CFS')
    $url = "https://opendart.fss.or.kr/api/fnlttSinglAcntAll.json?crtfc_key=$DART_KEY&corp_code=$Corp&bsns_year=$BsnsYear&reprt_code=$ReprtCode&fs_div=$FsDiv"
    try {
        $resp = Invoke-RestMethod -Uri $url -TimeoutSec 20
        if ($resp.status -ne '000') {
            Write-Warning ("DART API status=" + $resp.status + " message=" + $resp.message)
            return $null
        }
        return $resp.list
    } catch {
        Write-Warning ("DART fetch fail: " + $_.Exception.Message)
        return $null
    }
}

# helper: find value by account_id; tries _AltIds list if primary not found.
function Get-Value {
    param([array]$Rows, [string[]]$AccountIds, [string]$Field = 'thstrm_amount')
    foreach ($id in $AccountIds) {
        $row = $Rows | Where-Object { $_.account_id -eq $id } | Select-Object -First 1
        if ($row) {
            $v = $row.$Field
            if ([string]::IsNullOrWhiteSpace($v) -or $v -eq '-') { continue }
            $clean = ($v -replace ',', '').Trim()
            if ($clean.StartsWith('(') -and $clean.EndsWith(')')) {
                $clean = '-' + ($clean.Substring(1, $clean.Length - 2))
            }
            try { return [double]$clean } catch { continue }
        }
    }
    return $null
}

# helper: find by Korean account_nm (built from code points to avoid encoding issues)
function Get-ValueByName {
    param([array]$Rows, [string]$NameKr, [string]$Field = 'thstrm_amount')
    $row = $Rows | Where-Object { $_.account_nm -eq $NameKr } | Select-Object -First 1
    if (-not $row) { return $null }
    $v = $row.$Field
    if ([string]::IsNullOrWhiteSpace($v) -or $v -eq '-') { return $null }
    $clean = ($v -replace ',', '').Trim()
    if ($clean.StartsWith('(') -and $clean.EndsWith(')')) {
        $clean = '-' + ($clean.Substring(1, $clean.Length - 2))
    }
    try { return [double]$clean } catch { return $null }
}

$reportName = "FY$Year Annual"
Write-Host ("Fetching " + $reportName + " (CFS)...") -ForegroundColor Yellow
$rowsCfs = Fetch-DartStatements -Corp $CorpCode -BsnsYear $Year -ReprtCode 11011 -FsDiv 'CFS'
if (-not $rowsCfs) {
    Write-Host "Falling back to OFS (single-company)..." -ForegroundColor Yellow
    $rowsCfs = Fetch-DartStatements -Corp $CorpCode -BsnsYear $Year -ReprtCode 11011 -FsDiv 'OFS'
}
if (-not $rowsCfs) {
    Write-Host "ERROR: no financial data" -ForegroundColor Red
    exit 1
}

# Korean account_nm strings from code points (PS 5.1 cp949 safe).
# (Useful when the IFRS-tagged account_id isn't present and only the
#  Korean label exists in the filing.)
$kn = @{
    revenue      = [string]([char]0xC601 + [char]0xC5C5 + [char]0xC218 + [char]0xC775)      # 영업수익
    revenue2     = [string]([char]0xB9E4 + [char]0xCD9C + [char]0xC561)                       # 매출액
    opIncome     = [string]([char]0xC601 + [char]0xC5C5 + [char]0xC774 + [char]0xC775)      # 영업이익
    stBorrowing  = [string]([char]0xB2E8 + [char]0xAE30 + [char]0xCC28 + [char]0xC785 + [char]0xAE08)  # 단기차입금
    curLtBorrow  = [string]([char]0xC720 + [char]0xB3D9 + [char]0xC131 + [char]0xC7A5 + [char]0xAE30 + [char]0xCC28 + [char]0xC785 + [char]0xAE08)  # 유동성장기차입금
    ltBorrowing  = [string]([char]0xC7A5 + [char]0xAE30 + [char]0xCC28 + [char]0xC785 + [char]0xAE08)   # 장기차입금
    stFinanceInst= [string]([char]0xB2E8 + [char]0xAE30 + [char]0xAE08 + [char]0xC735 + [char]0xC0C1 + [char]0xD488)   # 단기금융상품
}

# ── Extract values (units: raw won) ──
$revenue   = Get-Value -Rows $rowsCfs -AccountIds @('ifrs-full_GrossProfit','ifrs-full_Revenue')
if ($null -eq $revenue) { $revenue = Get-ValueByName -Rows $rowsCfs -NameKr $kn.revenue }
if ($null -eq $revenue) { $revenue = Get-ValueByName -Rows $rowsCfs -NameKr $kn.revenue2 }

$opInc     = Get-Value -Rows $rowsCfs -AccountIds @('dart_OperatingIncomeLoss','ifrs-full_ProfitLossFromOperatingActivities')
if ($null -eq $opInc) { $opInc = Get-ValueByName -Rows $rowsCfs -NameKr $kn.opIncome }
$netIncome = Get-Value -Rows $rowsCfs -AccountIds @('ifrs-full_ProfitLoss')

# Debt-like
$curBorrow   = Get-ValueByName -Rows $rowsCfs -NameKr $kn.stBorrowing
$curLTBorrow = Get-ValueByName -Rows $rowsCfs -NameKr $kn.curLtBorrow
$curLease    = Get-Value -Rows $rowsCfs -AccountIds @('ifrs-full_CurrentLeaseLiabilities')
$ltBorrow    = Get-ValueByName -Rows $rowsCfs -NameKr $kn.ltBorrowing
if ($null -eq $ltBorrow) { $ltBorrow = Get-Value -Rows $rowsCfs -AccountIds @('ifrs-full_NoncurrentFinancialLiabilitiesAtAmortisedCost') }
$ncLease     = Get-Value -Rows $rowsCfs -AccountIds @('ifrs-full_NoncurrentLeaseLiabilities')

# Cash
$cash        = Get-Value -Rows $rowsCfs -AccountIds @('ifrs-full_CashAndCashEquivalents')
$stFI        = Get-ValueByName -Rows $rowsCfs -NameKr $kn.stFinanceInst
if ($null -eq $stFI) {
    $stAmort = Get-Value -Rows $rowsCfs -AccountIds @('ifrs-full_CurrentFinancialAssetsAtAmortisedCost')
    $stFvtpl = Get-Value -Rows $rowsCfs -AccountIds @('ifrs-full_CurrentFinancialAssetsAtFairValueThroughProfitOrLossMandatorilyMeasuredAtFairValue')
    $sum = 0.0
    $any = $false
    if ($null -ne $stAmort) { $sum += $stAmort; $any = $true }
    if ($null -ne $stFvtpl) { $sum += $stFvtpl; $any = $true }
    if ($any) { $stFI = $sum }
}

# Convert raw won -> 100M won (eok). Round to whole number.
$toEok = { param($v) if ($null -eq $v) { $null } else { [Math]::Round($v / 100000000.0, 0) } }

$out = [ordered]@{
    company         = $CorpName
    corp_code       = $CorpCode
    fiscal_period   = "$Year-FY Annual (Consolidated)"
    unit            = "100M KRW"
    fetched_at      = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    pnl             = [ordered]@{
        revenue           = & $toEok $revenue
        operating_income  = & $toEok $opInc
        depreciation      = $null
        ebitda            = $null
        net_income        = & $toEok $netIncome
    }
    debt            = [ordered]@{
        st_borrowings        = & $toEok $curBorrow
        current_lt_borrowings = & $toEok $curLTBorrow
        current_lease        = & $toEok $curLease
        lt_borrowings        = & $toEok $ltBorrow
        nc_lease             = & $toEok $ncLease
    }
    cash            = [ordered]@{
        cash_and_equivalents = & $toEok $cash
        st_financial_invest  = & $toEok $stFI
    }
}

# Derived totals
$debtVals = @($out.debt.Values | Where-Object { $_ -ne $null })
$cashVals = @($out.cash.Values | Where-Object { $_ -ne $null })
$totalDebt = if ($debtVals.Count) { ($debtVals | Measure-Object -Sum).Sum } else { 0 }
$totalCash = if ($cashVals.Count) { ($cashVals | Measure-Object -Sum).Sum } else { 0 }
$out.derived = [ordered]@{
    total_debt = $totalDebt
    total_cash = $totalCash
    net_debt   = $totalDebt - $totalCash
}

# Print summary (ASCII labels only)
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host (" Valuation table: " + $CorpName + " (" + $out.fiscal_period + ")") -ForegroundColor Cyan
Write-Host ("                  Unit: 100M KRW (eok-won)") -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
function Show-Section {
    param([string]$Title, [hashtable]$Items)
    Write-Host ("[" + $Title + "]")
    foreach ($k in $Items.Keys) {
        $v = $Items[$k]
        $disp = if ($null -eq $v) { '-- (manual input needed)' } else { ('{0:N0}' -f $v) }
        Write-Host ("  {0,-22} {1,16}" -f $k, $disp)
    }
    Write-Host ""
}
Show-Section -Title "P&L"       -Items $out.pnl
Show-Section -Title "Debt"      -Items $out.debt
Show-Section -Title "Cash & FI" -Items $out.cash
Write-Host ("[Net Debt] {0:N0} - {1:N0} = {2:N0}" -f $totalDebt, $totalCash, ($totalDebt - $totalCash))

$outPath = Join-Path $root ("valuation-" + $CorpCode + ".json")
$json = $out | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($outPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ""
Write-Host (" Saved -> " + $outPath) -ForegroundColor Green
