# =============================================================
#  Write fedwatch.json from an assisted Investing.com read.
#
#  fetch-fedwatch.ps1 gets HTTP 403 from this machine: Investing.com blocks
#  raw HTTP clients (verified - plain UA, full browser headers and the .kr
#  domain all 403, and CME's own page does too). The page itself is fine when
#  read through a browser-grade fetch, so this script carries those numbers in.
#
#  Futures prices cross-checked against Yahoo (ZQU26.CBT 96.315, ZQ=F 96.25,
#  ZQZ26.CBT 96.115) and the Sep prevWeek column matches the 2026-08-02
#  snapshot's current column, so the series is continuous.
#
#  ASCII-only comments (PS 5.1 reads .ps1 as cp949).
# =============================================================
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

function M {
    param($Idx, $Date, $Iso, $Time, $Price, $Rows)
    $probs = foreach ($r in $Rows) {
        [PSCustomObject]@{ range = $r[0]; current = [double]$r[1]; prevDay = [double]$r[2]; prevWeek = [double]$r[3] }
    }
    [PSCustomObject]@{
        idx = $Idx; date = $Date; iso = $Iso; meetingTime = $Time
        futurePrice = [double]$Price
        probabilities = @($probs)
    }
}

$meetings = @(
    M 0 'Sep 16, 2026' '2026-09-16' 'Sep 16, 2026 02:00PM ET' 96.315 @(
        @('3.50 - 3.75', 56.6, 44.9, 34.1), @('3.75 - 4.00', 43.4, 55.1, 65.9))
    M 1 'Oct 28, 2026' '2026-10-28' 'Oct 28, 2026 02:00PM ET' 96.250 @(
        @('3.50 - 3.75', 41.0, 31.5, 23.2), @('3.75 - 4.00', 47.1, 52.1, 55.7),
        @('4.00 - 4.25', 12.0, 16.5, 21.2))
    M 2 'Dec 09, 2026' '2026-12-09' 'Dec 09, 2026 02:00PM ET' 96.110 @(
        @('3.50 - 3.75', 23.2, 15.9, 12.6), @('3.75 - 4.00', 44.4, 41.9, 40.8),
        @('4.00 - 4.25', 27.2, 34.0, 37.0), @('4.25 - 4.50', 5.2, 8.1, 9.7))
    M 3 'Jan 27, 2027' '2027-01-27' 'Jan 27, 2027 01:00PM ET' 96.075 @(
        @('3.50 - 3.75', 19.4, 13.3, 9.3), @('3.75 - 4.00', 40.9, 37.6, 33.4),
        @('4.00 - 4.25', 30.0, 35.3, 38.0), @('4.25 - 4.50', 8.9, 12.4, 16.8),
        @('4.50 - 4.75', 0.9, 1.4, 2.5))
    M 4 'Mar 17, 2027' '2027-03-17' 'Mar 17, 2027 02:00PM ET' 96.010 @(
        @('3.50 - 3.75', 14.5, 9.7, 6.4), @('3.75 - 4.00', 35.5, 31.0, 26.0),
        @('4.00 - 4.25', 32.8, 35.9, 36.6), @('4.25 - 4.50', 14.2, 18.6, 23.3),
        @('4.50 - 4.75', 2.9, 4.3, 6.9), @('4.75 - 5.00', 0.2, 0.4, 0.8))
    M 5 'Apr 28, 2027' '2027-04-28' 'Apr 28, 2027 02:00PM ET' 95.975 @(
        @('3.50 - 3.75', 13.2, 8.6, 5.6), @('3.75 - 4.00', 33.6, 28.7, 23.4),
        @('4.00 - 4.25', 33.0, 35.4, 35.1), @('4.25 - 4.50', 15.8, 20.5, 25.1),
        @('4.50 - 4.75', 3.9, 5.9, 9.1), @('4.75 - 5.00', 0.5, 0.8, 1.6),
        @('5.00 - 5.25', 0.0, 0.0, 0.1))
)

# Sanity: every meeting's current column must sum to ~100.
foreach ($m in $meetings) {
    $sum = ($m.probabilities | Measure-Object -Property current -Sum).Sum
    if ([Math]::Abs($sum - 100) -gt 0.5) { throw ("probability sum off for " + $m.date + ": " + $sum) }
    Write-Host ("  {0,-14} price={1,7}  ranges={2}  sum={3}" -f $m.date, $m.futurePrice, $m.probabilities.Count, $sum)
}

$now = Get-Date
$out = [ordered]@{
    updated   = $now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    updatedKr = $now.ToString('yyyy-MM-dd HH:mm:ss')
    source    = 'investing.com/central-banks/fed-rate-monitor (CME Fed Funds Futures)'
    note      = 'Manual refresh: fetch-fedwatch.ps1 is 403-blocked from this machine, so these figures were read from the same Investing.com page through a browser-grade fetch. Futures prices verified against Yahoo ZQ contracts. Does NOT auto-refresh on deploy.'
    meetings  = @($meetings)
}
$json = $out | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText((Join-Path $root 'fedwatch.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("`n Saved -> fedwatch.json  ({0:N0} bytes)" -f (Get-Item (Join-Path $root 'fedwatch.json')).Length)
