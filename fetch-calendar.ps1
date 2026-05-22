# =============================================================
#  Reverent Partners - Economic Calendar Fetcher
#  Source: Investing.com /Service/getCalendarFilteredData
#  Output: calendar.json (ASCII keys; UI labels mapped in app.js)
# =============================================================
param([switch]$Loop, [int]$IntervalSec = 1800)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Web

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
$TodayFile    = Join-Path $PSScriptRoot 'calendar.json'
$WeekFile     = Join-Path $PSScriptRoot 'calendar-week.json'
$NextWeekFile = Join-Path $PSScriptRoot 'calendar-next-week.json'
$FrozenFile   = Join-Path $PSScriptRoot 'market-update-frozen.json'

# Investing.com country IDs to fetch (US, Japan, South Korea)
# Verified against investing.com page source: {id:5=US, id:35=Japan, id:11=South Korea}
$COUNTRY_IDS = @('5','35','11')

function Get-InvestingCalendar {
    param([string]$Tab = 'today')

    $url = 'https://www.investing.com/economic-calendar/Service/getCalendarFilteredData'
    $cParts = $COUNTRY_IDS | Sort-Object -Unique | ForEach-Object { "country%5B%5D=$_" }
    $body = ($cParts -join '&') + "&timeZone=88&timeFilter=timeOnly&currentTab=$Tab&submitFilters=1&limit_from=0"

    $headers = @{
        'User-Agent'       = $UA
        'X-Requested-With' = 'XMLHttpRequest'
        'Referer'          = 'https://www.investing.com/economic-calendar/'
        'Origin'           = 'https://www.investing.com'
        'Accept'           = 'application/json, text/javascript, */*; q=0.01'
        'Accept-Language'  = 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7'
        'Accept-Encoding'  = 'gzip, deflate, br'
        'Sec-Fetch-Site'   = 'same-origin'
        'Sec-Fetch-Mode'   = 'cors'
        'Sec-Fetch-Dest'   = 'empty'
        'Cache-Control'    = 'no-cache'
    }

    # Simpler approach: direct POST without session pre-priming.
    # The pre-prime (GET /economic-calendar/ before POST) was hitting Cloudflare
    # interstitial redirects (308) and breaking the cookie state. curl works
    # fine with just the direct POST, so do the same.
    try {
        $r = Invoke-RestMethod -Uri $url -Method POST -Body $body -Headers $headers `
            -ContentType 'application/x-www-form-urlencoded' -TimeoutSec 25 `
            -UserAgent $UA
        return $r.data
    } catch {
        Write-Warning ("Calendar fetch failed: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Clean-Value {
    param([string]$v)
    if (-not $v) { return '' }
    $v = $v -replace '&nbsp;', ''
    $v = $v -replace '<[^>]+>', ''
    return $v.Trim()
}

function Parse-Events {
    param([string]$Html)
    if (-not $Html) { return @() }

    $rowPattern = '<tr id="eventRowId_(\d+)"[^>]*data-event-datetime="([^"]+)"[^>]*>(.*?)</tr>'
    $rows = [regex]::Matches($Html, $rowPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

    $events = @()
    foreach ($row in $rows) {
        $eventId  = $row.Groups[1].Value
        $datetime = $row.Groups[2].Value          # "2026/05/11 23:00:00"
        $content  = $row.Groups[3].Value

        # Time
        $time = ''
        $tm = [regex]::Match($content, 'class="first left time js-time"[^>]*>([^<]+)<')
        if ($tm.Success) { $time = $tm.Groups[1].Value.Trim() }

        # Flag key (e.g., "United_States")
        $flagKey = ''
        $fm = [regex]::Match($content, 'class="ceFlags ([A-Za-z_]+)"')
        if ($fm.Success) { $flagKey = $fm.Groups[1].Value }

        # Currency code (e.g., "USD")
        $currency = ''
        $cm = [regex]::Match($content, 'class="left flagCur noWrap">.*?</span>\s*([A-Z]{3})')
        if ($cm.Success) { $currency = $cm.Groups[1].Value }

        # Importance (count of grayFullBullishIcon)
        $importance = ([regex]::Matches($content, 'grayFullBullishIcon')).Count

        # Event name
        $eventName = ''
        $em = [regex]::Match($content, 'class="left event"[^>]*>(.*?)</td>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($em.Success) {
            $rawName = $em.Groups[1].Value
            $rawName = $rawName -replace '<a[^>]*>', ''
            $rawName = $rawName -replace '</a>', ''
            $rawName = $rawName -replace '<[^>]+>', ''
            $eventName = [System.Web.HttpUtility]::HtmlDecode($rawName).Trim()
            $eventName = $eventName -replace '\s+', ' '
        }

        # Period (e.g., "(Apr)")
        $period = ''
        $pm = [regex]::Match($eventName, '\(([^)]+)\)\s*$')
        if ($pm.Success) {
            $period = $pm.Groups[1].Value
            $eventName = ($eventName -replace '\s*\([^)]+\)\s*$', '').Trim()
        }

        # Actual / Forecast / Previous
        $actual = ''; $forecast = ''; $previous = ''
        $am = [regex]::Match($content, "event-${eventId}-actual[^`"]*`"[^>]*>(.*?)</td>", [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($am.Success) { $actual = Clean-Value $am.Groups[1].Value }
        $fm2 = [regex]::Match($content, "event-${eventId}-forecast[^`"]*`"[^>]*>(.*?)</td>", [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($fm2.Success) { $forecast = Clean-Value $fm2.Groups[1].Value }
        $prm = [regex]::Match($content, "event-${eventId}-previous[^`"]*`"[^>]*>(.*?)</td>", [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($prm.Success) { $previous = Clean-Value $prm.Groups[1].Value }

        # MM/DD short date
        $shortDate = ''
        if ($datetime -match '^\d{4}/(\d{2})/(\d{2})') {
            $shortDate = "{0}/{1}" -f ([int]$matches[1]), ([int]$matches[2])
        }

        $events += [PSCustomObject]@{
            id         = $eventId
            datetime   = $datetime
            date       = $shortDate
            time       = $time
            flagKey    = $flagKey
            currency   = $currency
            importance = $importance
            indicator  = $eventName
            period     = $period
            actual     = $actual
            forecast   = $forecast
            previous   = $previous
            type       = if ($actual) { 'review' } else { 'preview' }
        }
    }

    # Sort: review first, then preview by time
    $review  = $events | Where-Object { $_.type -eq 'review'  } | Sort-Object datetime
    $preview = $events | Where-Object { $_.type -eq 'preview' } | Sort-Object datetime
    return @($review) + @($preview)
}

function Save-Calendar {
    param([string]$Tab, [string]$OutPath)

    $html = Get-InvestingCalendar -Tab $Tab
    $events = Parse-Events -Html $html

    $output = [ordered]@{
        updated   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        updatedKr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        countries = $COUNTRY_IDS
        tab       = $Tab
        events    = @($events)
    }

    $json = $output | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($OutPath, $json, (New-Object System.Text.UTF8Encoding($false)))

    $highImp = ($events | Where-Object { $_.importance -ge 2 }).Count
    return [PSCustomObject]@{ count = $events.Count; highImp = $highImp; path = $OutPath }
}

do {
    $start = Get-Date
    Write-Host ("[{0}] Calendar fetch (US/JP/KR)..." -f $start.ToString('HH:mm:ss')) -ForegroundColor Cyan

    $today    = Save-Calendar -Tab 'today'     -OutPath $TodayFile
    $week     = Save-Calendar -Tab 'thisWeek'  -OutPath $WeekFile
    $nextWeek = Save-Calendar -Tab 'nextWeek'  -OutPath $NextWeekFile

    $elapsed = [int](New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds
    Write-Host ("  today:    {0} events ({1} medium+) -> calendar.json"           -f $today.count,    $today.highImp)    -ForegroundColor Green
    Write-Host ("  week:     {0} events ({1} medium+) -> calendar-week.json"      -f $week.count,     $week.highImp)     -ForegroundColor Green
    Write-Host ("  nextWeek: {0} events ({1} medium+) -> calendar-next-week.json" -f $nextWeek.count, $nextWeek.highImp) -ForegroundColor Green

    # ─── Frozen weekly snapshot for Market Update dashboard section ───
    # Refreshes only on Fri/Sat/Sun (or if missing), so the displayed top-5
    # macro events Mon-Thu stay locked to last weekend's snapshot.
    $dow = (Get-Date).DayOfWeek
    $isWeekend = ($dow -eq [System.DayOfWeek]::Friday) -or ($dow -eq [System.DayOfWeek]::Saturday) -or ($dow -eq [System.DayOfWeek]::Sunday)
    $shouldFreeze = $isWeekend -or (-not (Test-Path $FrozenFile))
    if ($shouldFreeze) {
        $weekData = $null; $nextData = $null
        try { $weekData = Get-Content $WeekFile     -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
        try { $nextData = Get-Content $NextWeekFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}

        # Top 5 by importance DESC, then datetime ASC. Importance >= 2 only.
        $pickTop5 = {
            param($events)
            if (-not $events) { return @() }
            return @($events |
                Where-Object { ($_.importance -as [int]) -ge 2 } |
                Sort-Object @{Expression={ [int]$_.importance }; Descending=$true}, @{Expression='datetime'; Descending=$false} |
                Select-Object -First 5)
        }
        $thisTop5 = & $pickTop5 $weekData.events
        $nextTop5 = & $pickTop5 $nextData.events

        $frozen = [ordered]@{
            updated      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            updatedKr    = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            frozenDow    = $dow.ToString()
            thisWeek     = @($thisTop5)
            nextWeek     = @($nextTop5)
        }
        $json = $frozen | ConvertTo-Json -Depth 8
        [System.IO.File]::WriteAllText($FrozenFile, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host ("  frozen:   thisWeek={0} nextWeek={1} -> market-update-frozen.json" -f $thisTop5.Count, $nextTop5.Count) -ForegroundColor Yellow
    } else {
        Write-Host ("  frozen:   skipped (weekday $dow — last freeze stays)") -ForegroundColor DarkGray
    }

    Write-Host ("  done in {0}s" -f $elapsed) -ForegroundColor DarkGray

    if ($Loop) { Start-Sleep -Seconds $IntervalSec }
} while ($Loop)
