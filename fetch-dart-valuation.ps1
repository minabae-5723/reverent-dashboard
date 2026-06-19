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
    [int]$Year       = 2025,
    [switch]$LTM     = $false   # Build LTM = FY + Q1_next - Q1_curr (income); BS = latest quarter
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

# ── Fetch base statements (FY annual = anchor for both modes) ──
$reportName = "FY$Year Annual"
Write-Host ("Fetching " + $reportName + " (CFS)...") -ForegroundColor Yellow
$rowsAnnual = Fetch-DartStatements -Corp $CorpCode -BsnsYear $Year -ReprtCode 11011 -FsDiv 'CFS'
if (-not $rowsAnnual) {
    Write-Host "Falling back to OFS (single-company)..." -ForegroundColor Yellow
    $rowsAnnual = Fetch-DartStatements -Corp $CorpCode -BsnsYear $Year -ReprtCode 11011 -FsDiv 'OFS'
}
if (-not $rowsAnnual) {
    Write-Host "ERROR: no financial data" -ForegroundColor Red
    exit 1
}

# ── LTM: also fetch Q1 of (Year+1) and Q1 of Year ──
# LTM_PnL[i] = annual[i] + q1_next[i] - q1_curr[i]   (for income statement)
# LTM_BS[i]  = q1_next[i] (latest balance)
$rowsQ1Next = $null
$rowsQ1Curr = $null
$useLtm = $false
if ($LTM) {
    Write-Host ("Fetching Q1 " + ($Year + 1) + " (CFS) for LTM...") -ForegroundColor Yellow
    $rowsQ1Next = Fetch-DartStatements -Corp $CorpCode -BsnsYear ($Year + 1) -ReprtCode 11013 -FsDiv 'CFS'
    if (-not $rowsQ1Next) {
        $rowsQ1Next = Fetch-DartStatements -Corp $CorpCode -BsnsYear ($Year + 1) -ReprtCode 11013 -FsDiv 'OFS'
    }
    Write-Host ("Fetching Q1 " + $Year + " (CFS) for LTM baseline...") -ForegroundColor Yellow
    $rowsQ1Curr = Fetch-DartStatements -Corp $CorpCode -BsnsYear $Year -ReprtCode 11013 -FsDiv 'CFS'
    if (-not $rowsQ1Curr) {
        $rowsQ1Curr = Fetch-DartStatements -Corp $CorpCode -BsnsYear $Year -ReprtCode 11013 -FsDiv 'OFS'
    }
    if ($rowsQ1Next -and $rowsQ1Curr) {
        $useLtm = $true
        Write-Host (" -> LTM mode active: FY$Year + Q1$($Year+1) - Q1$Year") -ForegroundColor Green
    } else {
        Write-Host (" -> Q1 data missing — using FY only") -ForegroundColor Yellow
    }
}

# Decide which rows to use for P&L vs BS.
# (Balance-sheet items always read from the most-recent quarter; income from
#  either FY-only or LTM construction.)
$rowsPnL = $rowsAnnual   # may be combined below for LTM
$rowsBS  = if ($useLtm) { $rowsQ1Next } else { $rowsAnnual }

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
    equity       = [string]([char]0xC790 + [char]0xBCF8 + [char]0xCD1D + [char]0xACC4)   # 자본총계
    depreciation = [string]([char]0xAC10 + [char]0xAC00 + [char]0xC0C1 + [char]0xAC01 + [char]0xBE44)   # 감가상각비
}

# ── P&L extraction helper that supports LTM combining ──
# For LTM: ltm = annual + q1_next - q1_curr  (whichever values exist)
function Get-PnL {
    param(
        [string[]]$AccountIds,
        [string]$NameKr1 = '',
        [string]$NameKr2 = ''
    )
    $tryGet = {
        param([array]$rows)
        if (-not $rows) { return $null }
        $v = Get-Value -Rows $rows -AccountIds $AccountIds
        if ($null -eq $v -and $NameKr1) { $v = Get-ValueByName -Rows $rows -NameKr $NameKr1 }
        if ($null -eq $v -and $NameKr2) { $v = Get-ValueByName -Rows $rows -NameKr $NameKr2 }
        return $v
    }
    $annual = & $tryGet $rowsAnnual
    if (-not $useLtm) { return $annual }

    $q1Next = & $tryGet $rowsQ1Next
    $q1Curr = & $tryGet $rowsQ1Curr
    if ($null -eq $annual -or $null -eq $q1Next -or $null -eq $q1Curr) {
        # Insufficient data for LTM — fall back to annual
        return $annual
    }
    return ($annual + $q1Next - $q1Curr)
}

# ── BS extraction (always from most-recent quarter; rowsBS) ──
function Get-BS {
    param([string[]]$AccountIds, [string]$NameKr = '')
    $v = Get-Value -Rows $rowsBS -AccountIds $AccountIds
    if ($null -eq $v -and $NameKr) { $v = Get-ValueByName -Rows $rowsBS -NameKr $NameKr }
    return $v
}

# ── P&L ──
$revenue   = Get-PnL -AccountIds @('ifrs-full_GrossProfit','ifrs-full_Revenue') -NameKr1 $kn.revenue -NameKr2 $kn.revenue2
$opInc     = Get-PnL -AccountIds @('dart_OperatingIncomeLoss','ifrs-full_ProfitLossFromOperatingActivities') -NameKr1 $kn.opIncome
# Net income: prefer profit attributable to owners of parent (controlling interest)
$netIncome = Get-PnL -AccountIds @('ifrs-full_ProfitLossAttributableToOwnersOfParent','ifrs-full_ProfitLoss')
# Depreciation & amortization (flow; often only in CF statement rows)
$depr      = Get-PnL -AccountIds @('dart_DepreciationExpense','ifrs-full_DepreciationAndAmortisationExpense','ifrs-full_DepreciationExpense') -NameKr1 $kn.depreciation

# ── Debt-like ──
$curBorrow   = Get-BS -AccountIds @('ifrs-full_ShorttermBorrowings') -NameKr $kn.stBorrowing
$curLTBorrow = Get-BS -AccountIds @() -NameKr $kn.curLtBorrow
$curLease    = Get-BS -AccountIds @('ifrs-full_CurrentLeaseLiabilities')
$ltBorrow    = Get-BS -AccountIds @('ifrs-full_LongtermBorrowings','ifrs-full_NoncurrentFinancialLiabilitiesAtAmortisedCost') -NameKr $kn.ltBorrowing
$ncLease     = Get-BS -AccountIds @('ifrs-full_NoncurrentLeaseLiabilities')

# ── Cash / ST Financial Instruments ──
# Try Korean name first ("단기금융상품" — most common), then a broad list of IFRS IDs
# that different filers use for short-term financial instruments / investments.
$cash = Get-BS -AccountIds @('ifrs-full_CashAndCashEquivalents')

$stFI = Get-BS -AccountIds @('ifrs-full_ShorttermDepositsNotClassifiedAsCashEquivalents') -NameKr $kn.stFinanceInst
if ($null -eq $stFI) {
    # Broad fallback: sum of all "current financial assets" line items present
    $stCandidates = @(
        'ifrs-full_CurrentFinancialAssetsAtAmortisedCost'
        'ifrs-full_CurrentFinancialAssetsAtFairValueThroughProfitOrLossMandatorilyMeasuredAtFairValue'
        'ifrs-full_CurrentFinancialAssetsAtFairValueThroughOtherComprehensiveIncome'
        'dart_CurrentFinancialAssetDesignationAsAtFairValueThroughProfitOrLoss'
        'dart_CurrentFinancialAssetAtFairValueThroughProfitOrLoss'
    )
    $sum = 0.0
    $any = $false
    foreach ($id in $stCandidates) {
        $v = Get-Value -Rows $rowsBS -AccountIds @($id)
        if ($null -ne $v) { $sum += $v; $any = $true }
    }
    if ($any) { $stFI = $sum }
}

# Equity (자본총계) — PBR denominator. BS item from most-recent quarter.
$equity = Get-BS -AccountIds @('ifrs-full_Equity') -NameKr $kn.equity

# Convert raw won -> 100M won (eok). Round to whole number.
$toEok = { param($v) if ($null -eq $v) { $null } else { [Math]::Round($v / 100000000.0, 0) } }

# EBITDA = operating income + D&A (only when both present)
$ebitda = if (($null -ne $opInc) -and ($null -ne $depr)) { $opInc + $depr } else { $null }

$out = [ordered]@{
    company         = $CorpName
    corp_code       = $CorpCode
    fiscal_period   = if ($useLtm) { ("LTM Q1 " + ($Year + 1) + " (FY$Year + Q1$($Year+1) - Q1$Year)") } else { "FY$Year Annual (Consolidated)" }
    unit            = "100M KRW"
    fetched_at      = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    pnl             = [ordered]@{
        revenue           = & $toEok $revenue
        operating_income  = & $toEok $opInc
        depreciation      = & $toEok $depr
        ebitda            = & $toEok $ebitda
        net_income        = & $toEok $netIncome
    }
    equity_total    = & $toEok $equity
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
