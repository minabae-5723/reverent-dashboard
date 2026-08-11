# =============================================================
#  Rebuild market-update-frozen.json with a wider scope: US + KR + JP.
#
#  Source: Trading Economics country calendars (Investing is 403). TE renders
#  times in UTC -- confirmed by matching the US CPI slot (Aug 12 12:30 UTC)
#  against the existing frozen entry of 8/12 21:30 KST, and Japan's 11:50 PM UTC
#  slots against the 08:50 JST release convention. So KST = UTC + 9.
#
#  For events that have not happened yet, TE's leading numeric column is the
#  LAST RELEASED value, not an actual -- it is written to `previous` here and
#  `actual` is deliberately left empty.
#
#  ASCII-only comments (PS 5.1 reads .ps1 as cp949).
# =============================================================
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

function E {
    param([string]$Kst, [string]$Flag, [string]$Cur, [int]$Imp,
          [string]$Ind, [string]$Period, [string]$Fc = '', [string]$Pv = '',
          [string]$Ac = '', [string]$Type)
    $dt = [DateTime]::ParseExact($Kst, 'yyyy-MM-dd HH:mm', $null)
    [PSCustomObject]@{
        id         = ($dt.ToString('yyyyMMddHHmm') + '-' + ($Ind -replace '[^A-Za-z0-9]', '')).ToLower()
        datetime   = $dt.ToString('yyyy/MM/dd HH:mm:ss')
        date       = $dt.ToString('M/d')
        time       = $dt.ToString('HH:mm')
        flagKey    = $Flag
        currency   = $Cur
        importance = $Imp
        indicator  = $Ind
        period     = $Period
        actual     = $Ac
        forecast   = $Fc
        previous   = $Pv
        type       = $Type
    }
}

$US = 'United_States'; $KR = 'South_Korea'; $JP = 'Japan'

# --- This week: 2026-08-10 ~ 08-14 (KST) -----------------------------------
$thisWeek = @(
    E '2026-08-12 08:00' $KR 'KRW' 3 'Unemployment Rate'            'Jul' ''      '2.8%'   '' 'review'
    E '2026-08-12 21:30' $US 'USD' 3 'CPI (YoY)'                    'Jul' '3.4%'  '3.5%'   '' 'review'
    E '2026-08-12 21:30' $US 'USD' 3 'Core CPI (YoY)'               'Jul' '2.5%'  '2.6%'   '' 'review'
    E '2026-08-13 08:50' $JP 'JPY' 2 'PPI (YoY)'                    'Jul' '7.2%'  '7.4%'   '' 'review'
    E '2026-08-13 21:30' $US 'USD' 3 'PPI (YoY)'                    'Jul' '5.0%'  '5.5%'   '' 'review'
    E '2026-08-13 21:30' $US 'USD' 3 'Core PPI (YoY)'               'Jul' '4.7%'  '4.7%'   '' 'review'
    E '2026-08-13 21:30' $US 'USD' 2 'Initial Jobless Claims'       ''    '202K'  '199K'   '' 'review'
    E '2026-08-14 06:00' $KR 'KRW' 2 'Export Prices (YoY)'          'Jul' ''      '55.0%'  '' 'review'
    E '2026-08-14 06:00' $KR 'KRW' 2 'Import Prices (YoY)'          'Jul' ''      '31.0%'  '' 'review'
    E '2026-08-14 21:30' $US 'USD' 3 'Retail Sales (MoM)'           'Jul' '0.1%'  '0.2%'   '' 'review'
    E '2026-08-14 23:00' $US 'USD' 2 'Michigan Consumer Sentiment'  'Aug' '54.4'  '55.2'   '' 'review'
)

# --- Next week: 2026-08-17 ~ 08-21 (KST) -----------------------------------
$nextWeek = @(
    E '2026-08-17 08:50' $JP 'JPY' 3 'GDP Growth Rate (QoQ) Prel'   'Q2'  '0.4%'  '0.5%'   '' 'preview'
    E '2026-08-17 08:50' $JP 'JPY' 3 'GDP Annualized Prel'          'Q2'  '1.7%'  '2.0%'   '' 'preview'
    E '2026-08-17 23:00' $US 'USD' 2 'NAHB Housing Market Index'    'Aug' '34'    '34'     '' 'preview'
    E '2026-08-18 21:30' $US 'USD' 2 'Housing Starts'               'Jul' ''      '1.427M' '' 'preview'
    E '2026-08-18 22:15' $US 'USD' 2 'Industrial Production (MoM)'  'Jul' ''      '0.1%'   '' 'preview'
    E '2026-08-20 03:00' $US 'USD' 3 'FOMC Meeting Minutes'         ''    ''      ''       '' 'preview'
    E '2026-08-20 08:50' $JP 'JPY' 2 'Balance of Trade'             'Jul' ''      'JPY -406.9B' '' 'preview'
    E '2026-08-20 08:50' $JP 'JPY' 2 'Exports (YoY)'                'Jul' ''      '19.3%'  '' 'preview'
    E '2026-08-20 21:30' $US 'USD' 2 'Initial Jobless Claims'       ''    ''      ''       '' 'preview'
    E '2026-08-20 21:30' $US 'USD' 2 'Philadelphia Fed Manufacturing Index' 'Aug' '' '41.4' '' 'preview'
    E '2026-08-21 06:00' $KR 'KRW' 2 'PPI (YoY)'                    'Jul' '8.5%'  '8.6%'   '' 'preview'
    E '2026-08-21 08:30' $JP 'JPY' 3 'CPI (YoY)'                    'Jul' ''      '1.7%'   '' 'preview'
    E '2026-08-21 08:30' $JP 'JPY' 3 'Core CPI (YoY)'               'Jul' ''      '1.6%'   '' 'preview'
    E '2026-08-21 09:30' $JP 'JPY' 2 'S&P Global Manufacturing PMI Flash' 'Aug' '' '54.5' '' 'preview'
    E '2026-08-21 22:45' $US 'USD' 3 'S&P Global Manufacturing PMI' 'Aug' ''      '53.8'   '' 'preview'
    E '2026-08-21 22:45' $US 'USD' 3 'S&P Global Services PMI'      'Aug' ''      '54.6'   '' 'preview'
)

$thisWeek = @($thisWeek | Sort-Object datetime)
$nextWeek = @($nextWeek | Sort-Object datetime)

$now = Get-Date
$out = [ordered]@{
    updated      = $now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    updatedKr    = $now.ToString('yyyy-MM-dd HH:mm:ss')
    frozenDow    = $now.DayOfWeek.ToString()
    reviewRange  = '2026-08-10~2026-08-14'
    previewRange = '2026-08-17~2026-08-21'
    thisWeek     = @($thisWeek)
    nextWeek     = @($nextWeek)
}
$json = $out | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText((Join-Path $root 'market-update-frozen.json'), $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ("thisWeek {0} items / nextWeek {1} items" -f $thisWeek.Count, $nextWeek.Count)
foreach ($g in @(@('REVIEW', $thisWeek), @('PREVIEW', $nextWeek))) {
    Write-Host ("`n== " + $g[0])
    foreach ($e in $g[1]) {
        Write-Host ("  {0} {1}  {2,-14} {3,-38} f={4,-8} p={5}" -f $e.date, $e.time, $e.flagKey, $e.indicator, $e.forecast, $e.previous)
    }
}
$byC = ($thisWeek + $nextWeek) | Group-Object flagKey | ForEach-Object { $_.Name + '=' + $_.Count }
Write-Host ("`ncountry mix: " + ($byC -join '  '))
