# =============================================================
#  Korean business-day calendar + Monday-Brief freeze window
#
#  Single helper for "weekday excluding public holidays" routines and the
#  Monday-morning freeze (user rule 2026-08-10, holiday shift 2026-10-04):
#    - Freeze day = first non-holiday weekday of the week (Mon, or Tue when
#      Mon is a holiday, ...). Freeze runs from Monday 00:00 through
#      freeze day 12:00 (or a one-off override from kr-holidays.json).
#  Data: kr-holidays.json (UTF-8). ASCII-only source (PS 5.1 reads .ps1 as cp949).
#
#  Dot-source for functions:   . (Join-Path $PSScriptRoot 'kr-calendar.ps1')
#  CLI for routines:            powershell -ExecutionPolicy Bypass -File .\kr-calendar.ps1 -Status
#    -> JSON {date, now, isHoliday, holidayName, isWorkday, freezeDay, freezeEnd, freezeActive}
# =============================================================
param(
    [switch]$Status = $false,
    [string]$At = ''          # optional 'yyyy-MM-dd HH:mm' for testing
)

$script:KrCalFile = Join-Path $PSScriptRoot 'kr-holidays.json'
$script:KrCal = $null

function Get-KrCalData {
    if ($null -eq $script:KrCal) {
        try {
            $script:KrCal = [IO.File]::ReadAllText($script:KrCalFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
        } catch {
            $script:KrCal = [pscustomobject]@{ holidays = [pscustomobject]@{}; freezeEndOverrides = [pscustomobject]@{} }
        }
    }
    return $script:KrCal
}

function Get-KrHolidayName([datetime]$Date) {
    $key = $Date.ToString('yyyy-MM-dd')
    $p = (Get-KrCalData).holidays.PSObject.Properties[$key]
    if ($p) { return [string]$p.Value }
    return $null
}

function Test-KrWorkday([datetime]$Date) {
    $dow = $Date.DayOfWeek
    if ($dow -eq [DayOfWeek]::Saturday -or $dow -eq [DayOfWeek]::Sunday) { return $false }
    return (-not (Get-KrHolidayName $Date))
}

# Returns @{ FreezeDay; FreezeEnd; Active } for the week containing $Now.
function Get-MondayFreeze([datetime]$Now) {
    $offset = ([int]$Now.DayOfWeek + 6) % 7          # Mon=0 .. Sun=6
    $monday = $Now.Date.AddDays(-$offset)
    $freezeDay = $monday
    for ($i = 0; $i -lt 5; $i++) {
        $d = $monday.AddDays($i)
        if (Test-KrWorkday $d) { $freezeDay = $d; break }
        $freezeDay = $d
    }
    $freezeEnd = $freezeDay.AddHours(12)
    $ovr = (Get-KrCalData).freezeEndOverrides.PSObject.Properties[$freezeDay.ToString('yyyy-MM-dd')]
    if ($ovr) { $freezeEnd = $freezeDay.Add([TimeSpan]::Parse([string]$ovr.Value)) }
    $active = ($offset -le 4 -and $Now -lt $freezeEnd)
    return @{ FreezeDay = $freezeDay; FreezeEnd = $freezeEnd; Active = $active }
}

if ($Status) {
    $now = if ($At) { [datetime]::Parse($At) } else { Get-Date }
    $fz = Get-MondayFreeze $now
    $name = Get-KrHolidayName $now
    [ordered]@{
        date         = $now.ToString('yyyy-MM-dd')
        now          = $now.ToString('yyyy-MM-dd HH:mm ddd', [Globalization.CultureInfo]::InvariantCulture)
        isHoliday    = [bool]$name
        holidayName  = $name
        isWorkday    = (Test-KrWorkday $now)
        freezeDay    = $fz.FreezeDay.ToString('yyyy-MM-dd')
        freezeEnd    = $fz.FreezeEnd.ToString('yyyy-MM-dd HH:mm')
        freezeActive = $fz.Active
    } | ConvertTo-Json
}
