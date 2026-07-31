# =============================================================
#  DART audit-report (external-audit) financial extractor
#
#  For companies NOT covered by fnlttSinglAcntAll (unlisted
#  external-audit entities file an audit report, not a periodic
#  report), pull the raw disclosure document and parse the
#  BS / IS / CF tables for valuation inputs.
#
#  Also useful for LISTED companies when D and A is only shown
#  in the raw cash-flow statement (the open API lumps it into
#  "adjustments to reconcile profit").
#
#  ASCII-only source. PS 5.1 reads .ps1 as cp949, so every
#  Korean account label lives in dart-audit-labels.json (UTF-8).
#  Units: 100M KRW (eok-won). DART documents state raw KRW.
#
#  Usage:
#    powershell -ExecutionPolicy Bypass -File .\fetch-dart-audit.ps1 `
#        -CorpCode 00406107 -CorpName Futronic -Year 2025
# =============================================================
param(
    [string]$CorpCode = '',
    [string]$CorpName = '',
    [int]$Year        = 2025,
    [string]$WorkDir  = ''
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

$cfg = Get-Content (Join-Path $root 'config.json') -Raw | ConvertFrom-Json
$key = $cfg.DART_API_KEY
if (-not $key)      { Write-Host 'FATAL: DART_API_KEY missing'; exit 1 }
if (-not $CorpCode) { Write-Host 'FATAL: -CorpCode required';   exit 1 }
if (-not $CorpName) { $CorpName = "corp_$CorpCode" }
if (-not $WorkDir)  { $WorkDir = Join-Path $env:TEMP 'dart-audit' }
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir | Out-Null }

# Korean labels come from UTF-8 JSON (see header note).
$LBL = [IO.File]::ReadAllText((Join-Path $root 'dart-audit-labels.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$reportPat = ($LBL.report_filter -join '|')

Write-Host ("Company: " + $CorpName + "  corp_code=" + $CorpCode + "  FY" + $Year) -ForegroundColor Green

# -- 1) locate the filing -------------------------------------
# pblntf_ty=F -> external audit related ; A -> periodic report
$bgn = "$Year" + "0101"
$end = ($Year + 1).ToString() + "1231"
$rcept = $null
foreach ($ty in @('F', 'A')) {
    $lurl = "https://opendart.fss.or.kr/api/list.json?crtfc_key=$key&corp_code=$CorpCode&bgn_de=$bgn&end_de=$end&pblntf_ty=$ty&page_count=50"
    try { $lr = Invoke-RestMethod -Uri $lurl -TimeoutSec 30 } catch { continue }
    if ($lr.status -ne '000') { continue }
    $cand = $lr.list | Where-Object { $_.report_nm -match $reportPat -and $_.report_nm -match "$Year" }
    if (-not $cand) { $cand = $lr.list | Where-Object { $_.report_nm -match $reportPat } }
    if ($cand) { $rcept = ($cand | Select-Object -First 1); break }
}
if (-not $rcept) { Write-Host 'ERROR: no audit/annual report found' -ForegroundColor Red; exit 1 }
Write-Host ("  Filing: " + $rcept.rcept_dt + " " + $rcept.report_nm + " (" + $rcept.rcept_no + ")")

# -- 2) download + unzip the raw document ---------------------
$zip = Join-Path $WorkDir ($CorpCode + '.zip')
$out = Join-Path $WorkDir $CorpCode
Invoke-WebRequest -Uri ("https://opendart.fss.or.kr/api/document.xml?crtfc_key=$key&rcept_no=" + $rcept.rcept_no) -OutFile $zip -TimeoutSec 120
Expand-Archive $zip -DestinationPath $out -Force
$xml = Get-ChildItem $out -Filter *.xml | Sort-Object Length -Descending | Select-Object -First 1
if (-not $xml) { Write-Host 'ERROR: no xml inside archive' -ForegroundColor Red; exit 1 }
$txt = [IO.File]::ReadAllText($xml.FullName, [Text.Encoding]::UTF8)
Write-Host ("  Document: " + $xml.Name + " (" + [math]::Round($xml.Length/1KB) + " KB)")

# -- 3) split into table rows ---------------------------------
$rows = New-Object System.Collections.ArrayList
foreach ($m in [regex]::Matches($txt, '(?s)<TR[^>]*>(.*?)</TR>')) {
    $cells = @()
    foreach ($c in [regex]::Matches($m.Groups[1].Value, '(?s)<TD[^>]*>(.*?)</TD>')) {
        $v = $c.Groups[1].Value -replace '<[^>]+>', ''
        $v = $v -replace '&nbsp;', ' '
        $v = ($v -replace '\s', '')
        $v = $v -replace [char]0x3000, ''
        $cells += $v.Trim()
    }
    if ($cells.Count -ge 2) { [void]$rows.Add($cells) }
}
Write-Host ("  Parsed rows: " + $rows.Count)

# -- helpers --------------------------------------------------
# A cell is an AMOUNT only if it is a properly grouped number
# (1,234,567) or a long bare digit run.
#
# The comma test alone is NOT enough: DART puts note references in
# the column right after the label, and they look like "5,6,7,20,36"
# or "4,28". Those parse as numbers and silently became the answer
# (revenue read as 4.28 -> rounded to 0). Requiring exact 3-digit
# groups after the first rejects them.
function Is-Amount {
    param([string]$s)
    if (-not $s) { return $false }
    $t = $s.Trim()
    if ($t -match '^\(.*\)$') { $t = $t.Substring(1, $t.Length - 2) }
    if ($t -match '^-')       { $t = $t.Substring(1) }
    if ($t -match '^\d{1,3}(,\d{3})+$') { return $true }
    if ($t -match '^\d+$')              { return ($t.Length -ge 7) }
    return $false
}
function To-Eok {
    param([string]$s)
    $t = $s.Trim(); $sign = 1
    if ($t -match '^\(.*\)$') { $t = $t.Substring(1, $t.Length - 2); $sign = -1 }
    if ($t -match '^-')       { $t = $t.Substring(1); $sign = -1 }
    $t = $t -replace ',', ''
    if ($t -eq '') { return $null }
    return [math]::Round(([double]$t) * $sign / 1e8, 0)
}
# Collect the current-period amount from EVERY row whose leading
# label matches, then pick a representative value.
#
# A label can appear many times: once in the primary statement and
# again in note tables (often broken down, sometimes zero). Taking
# the first hit blindly yields 0 whenever a note table happens to
# come first, so we skip zeros and, for line items that notes split
# by category, fall back to the largest magnitude.
function Find-Candidates {
    param([string[]]$Labels)
    $vals = @()
    foreach ($r in $rows) {
        $label = $r[0] -replace '[^\p{IsHangulSyllables}]', ''
        if ($label -eq '') { continue }
        foreach ($L in $Labels) {
            if ($label -ne $L) { continue }
            for ($i = 1; $i -lt $r.Count; $i++) {
                if (Is-Amount $r[$i]) { $vals += (To-Eok $r[$i]); break }
            }
        }
    }
    return $vals
}
function Find-Row {
    param([string[]]$Labels, [switch]$Max)
    $vals = Find-Candidates $Labels
    if ($vals.Count -eq 0) { return $null }
    $nz = @($vals | Where-Object { $_ -ne 0 })
    if ($nz.Count -eq 0) { return 0 }
    if ($Max) { return ($nz | Sort-Object { [math]::Abs($_) } -Descending | Select-Object -First 1) }
    return $nz[0]
}
# Diagnostic: show every candidate so a wrong pick is visible.
function Show-Candidates {
    param([string]$k, [string[]]$Labels)
    $vals = Find-Candidates $Labels
    if ($vals.Count -gt 1) { Write-Host ("    ~ {0}: candidates = {1}" -f $k, ($vals -join ', ')) }
}

# -- 4) extract fields ----------------------------------------
$revenue  = Find-Row $LBL.revenue
$op       = Find-Row $LBL.op
$ni       = Find-Row $LBL.ni
$equity   = Find-Row $LBL.equity
$liab     = Find-Row $LBL.liabilities
$assets   = Find-Row $LBL.assets
$stBorrow = Find-Row $LBL.st_borrow
$ltBorrow = Find-Row $LBL.lt_borrow
$curLt    = Find-Row $LBL.current_lt
$bond     = Find-Row $LBL.bonds
$curLease = Find-Row $LBL.current_lease
$lease    = Find-Row $LBL.lease
$cash     = Find-Row $LBL.cash
$stFin    = Find-Row $LBL.st_fin
# D and A almost never appears in the primary statements of an audit
# report - only in the notes, which are frequently denominated in
# THOUSANDS of won while the statements use won. Auto-converting a
# note figure as if it were won understates it 1000x, so we extract
# it but refuse to trust a value that is implausibly small relative
# to revenue. Better a blank cell than a wrong EBITDA.
$dep      = Find-Row $LBL.dep   -Max
$amort    = Find-Row $LBL.amort -Max
$daSuspect = $false
if ($revenue -ne $null -and $revenue -gt 0) {
    foreach ($v in @($dep, $amort)) {
        if ($v -ne $null -and $v -ne 0 -and ($v / $revenue) -lt 0.005) { $daSuspect = $true }
    }
}
if ($daSuspect) {
    Write-Host '  ! D and A looks scale-ambiguous (notes likely in KRW thousands) - dropping' -ForegroundColor Yellow
    $dep = $null; $amort = $null
}

Write-Host ''; Write-Host '  [candidate scan]'
Show-Candidates 'revenue' $LBL.revenue
Show-Candidates 'op'      $LBL.op
Show-Candidates 'ni'      $LBL.ni
Show-Candidates 'equity'  $LBL.equity
Show-Candidates 'dep'     $LBL.dep
Show-Candidates 'cash'    $LBL.cash
Show-Candidates 'st_borrow' $LBL.st_borrow

$da = $null
if ($dep -ne $null -or $amort -ne $null) {
    $da = 0
    if ($dep   -ne $null) { $da += $dep }
    if ($amort -ne $null) { $da += $amort }
}
$ebitda = $null
if ($op -ne $null -and $da -ne $null) { $ebitda = $op + $da }

$debtSum = 0; $anyDebt = $false
foreach ($d in @($stBorrow, $curLt, $ltBorrow, $bond, $curLease, $lease)) {
    if ($d -ne $null) { $debtSum += $d; $anyDebt = $true }
}
$cashSum = 0
foreach ($c in @($cash, $stFin)) { if ($c -ne $null) { $cashSum += $c } }
$netDebt = $null
if ($anyDebt) { $netDebt = $debtSum - $cashSum }

# -- 5) report ------------------------------------------------
Write-Host ''
Write-Host '============================================================'
Write-Host (' Audit-report extract: ' + $CorpName + ' (FY' + $Year + ')')
Write-Host '                  Unit: 100M KRW (eok-won)'
Write-Host '============================================================'
function Show { param([string]$k, $v)
    if ($v -eq $null) { Write-Host ("  {0,-24} -- (not found)" -f $k) }
    else              { Write-Host ("  {0,-24} {1,12:N0}" -f $k, $v) }
}
Write-Host ''; Write-Host '[P and L]'
Show 'revenue'          $revenue
Show 'operating_income' $op
Show 'depreciation'     $dep
Show 'amortisation'     $amort
Show 'DA_total'         $da
Show 'ebitda'           $ebitda
Show 'net_income'       $ni
Write-Host ''; Write-Host '[Equity / Assets]'
Show 'equity_total'     $equity
Show 'liabilities'      $liab
Show 'assets'           $assets
Write-Host ''; Write-Host '[Debt]'
Show 'st_borrowings'    $stBorrow
Show 'current_lt'       $curLt
Show 'lt_borrowings'    $ltBorrow
Show 'bonds'            $bond
Show 'current_lease'    $curLease
Show 'lease'            $lease
Write-Host ''; Write-Host '[Cash]'
Show 'cash'             $cash
Show 'st_financial'     $stFin
Write-Host ''
if ($netDebt -ne $null) { Write-Host ('[Net Debt] ' + $debtSum + ' - ' + $cashSum + ' = ' + $netDebt) }

$obj = [ordered]@{
    company       = $CorpName
    corp_code     = $CorpCode
    source        = 'DART raw document'
    report_nm     = $rcept.report_nm
    rcept_no      = $rcept.rcept_no
    rcept_dt      = $rcept.rcept_dt
    fiscal_period = "FY$Year"
    unit          = '100M KRW'
    pnl           = [ordered]@{ revenue = $revenue; operating_income = $op; depreciation = $dep; amortisation = $amort; da_total = $da; ebitda = $ebitda; net_income = $ni }
    equity_total  = $equity
    liabilities   = $liab
    assets        = $assets
    debt          = [ordered]@{ st_borrowings = $stBorrow; current_lt_borrowings = $curLt; lt_borrowings = $ltBorrow; bonds = $bond; current_lease = $curLease; lease = $lease }
    cash          = [ordered]@{ cash_and_equivalents = $cash; st_financial_invest = $stFin }
    derived       = [ordered]@{ total_debt = $(if ($anyDebt) { $debtSum } else { $null }); total_cash = $cashSum; net_debt = $netDebt }
}
$dest = Join-Path $root ('valuation-' + $CorpCode + '-audit.json')
$obj | ConvertTo-Json -Depth 5 | Out-File -FilePath $dest -Encoding utf8
Write-Host ''
Write-Host (' Saved -> ' + $dest) -ForegroundColor Green
