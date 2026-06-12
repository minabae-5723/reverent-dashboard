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

# Investing.com country IDs to fetch (US, Japan, South Korea, Eurozone)
# Verified against investing.com page source: {id:5=US, id:35=Japan, id:11=South Korea, id:72=Eurozone}
# Eurozone(72) 추가: ECB 기준금리 결정 등 유럽 매크로를 캘린더·Macro Economy에 포함 (flagKey="Europe")
$COUNTRY_IDS = @('5','35','11','72')

function Get-InvestingCalendar {
    param([string]$Tab = 'today', [string]$DateFrom = '', [string]$DateTo = '')

    $url = 'https://www.investing.com/economic-calendar/Service/getCalendarFilteredData'
    $cParts = $COUNTRY_IDS | Sort-Object -Unique | ForEach-Object { "country%5B%5D=$_" }
    if ($Tab -eq 'custom' -and $DateFrom -and $DateTo) {
        $body = ($cParts -join '&') + "&timeZone=88&timeFilter=timeOnly&currentTab=custom&dateFrom=$DateFrom&dateTo=$DateTo&submitFilters=1&limit_from=0"
    } else {
        $body = ($cParts -join '&') + "&timeZone=88&timeFilter=timeOnly&currentTab=$Tab&submitFilters=1&limit_from=0"
    }

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
    param([string]$Tab, [string]$OutPath, [string]$DateFrom = '', [string]$DateTo = '')

    $html = Get-InvestingCalendar -Tab $Tab -DateFrom $DateFrom -DateTo $DateTo
    $events = Parse-Events -Html $html

    $tabLabel = if ($Tab -eq 'custom') { "custom $DateFrom~$DateTo" } else { $Tab }
    $output = [ordered]@{
        updated   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        updatedKr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        countries = $COUNTRY_IDS
        tab       = $tabLabel
        events    = @($events)
    }

    $json = $output | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($OutPath, $json, (New-Object System.Text.UTF8Encoding($false)))

    $highImp = ($events | Where-Object { $_.importance -ge 2 }).Count
    return [PSCustomObject]@{ count = $events.Count; highImp = $highImp; path = $OutPath }
}

# Compute Monday of this week (DayOfWeek: Sun=0, Mon=1, ... Sat=6)
function Get-WeekBounds {
    $today = (Get-Date).Date
    $dow = [int]$today.DayOfWeek          # Sun=0, Mon=1, ..., Sat=6
    $offsetToMon = if ($dow -eq 0) { -6 } else { -($dow - 1) }
    $thisMon = $today.AddDays($offsetToMon)
    $thisSun = $thisMon.AddDays(6)
    $nextMon = $thisMon.AddDays(7)
    $nextSun = $thisMon.AddDays(13)
    return [PSCustomObject]@{
        thisMon = $thisMon
        thisSun = $thisSun
        today   = $today
        nextMon = $nextMon
        nextSun = $nextSun
    }
}

do {
    $start = Get-Date
    Write-Host ("[{0}] Calendar fetch (US/JP/KR)..." -f $start.ToString('HH:mm:ss')) -ForegroundColor Cyan

    # Review = this calendar week Mon..today (라벨 전용 — 발표완료/과거 이벤트 구간)
    # Preview = next calendar week Mon..Sun (upcoming events)
    # calendar-week.json(#weekly 뷰)은 이번주 전체(월~일)를 담는다 — 주 초반에도 일주일치 다 보이도록
    $wb = Get-WeekBounds
    # 라벨용 Review 구간(월~오늘) + #weekly 뷰용 이번주 전체(월~일)
    $reviewFrom  = '{0:yyyy-MM-dd}' -f $wb.thisMon
    $reviewTo    = '{0:yyyy-MM-dd}' -f $wb.today
    $weekFrom    = '{0:yyyy-MM-dd}' -f $wb.thisMon
    $weekTo      = '{0:yyyy-MM-dd}' -f $wb.thisSun
    $previewFrom = '{0:yyyy-MM-dd}' -f $wb.nextMon
    $previewTo   = '{0:yyyy-MM-dd}' -f $wb.nextSun

    $today    = Save-Calendar -Tab 'today' -OutPath $TodayFile
    $week     = Save-Calendar -Tab 'custom' -DateFrom $weekFrom    -DateTo $weekTo    -OutPath $WeekFile
    $nextWeek = Save-Calendar -Tab 'custom' -DateFrom $previewFrom -DateTo $previewTo -OutPath $NextWeekFile

    $elapsed = [int](New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds
    Write-Host ("  today:    {0} events ({1} medium+) -> calendar.json"           -f $today.count,    $today.highImp)    -ForegroundColor Green
    Write-Host ("  Week ({0}~{1}): {2} events ({3} medium+) -> calendar-week.json" -f $weekFrom, $weekTo, $week.count, $week.highImp) -ForegroundColor Green
    Write-Host ("  Preview ({0}~{1}): {2} events ({3} medium+) -> calendar-next-week.json" -f $previewFrom, $previewTo, $nextWeek.count, $nextWeek.highImp) -ForegroundColor Green

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

        # Pick up to 7 by importance, but force-include tier-1 indicators
        # (Nonfarm Payrolls, PCE YoY pair, ECB rate decision) when present.
        # MoM/sub-index variants and ECB speaker/press-conf noise are filtered out.
        $maxN = 7
        $pickTop5 = {
            param($events)
            if (-not $events) { return @() }
            # Drop MoM/sub-index variants (CPI/PPI/PCE show only YoY) + ECB 발언/회견/성명 noise.
            $filtered = @($events | Where-Object {
                -not (
                    ($_.indicator -match '(?i)PCE.*\(MoM\)') -or
                    ($_.indicator -match '(?i)^(Core\s+)?CPI \(MoM\)$') -or
                    ($_.indicator -match '(?i)^CPI[,]?\s*(n\.s\.a|s\.a|Index)') -or
                    ($_.indicator -match '(?i)^Cleveland CPI') -or
                    ($_.indicator -match '(?i)Speaks$') -or
                    ($_.indicator -match '(?i)Press Conference') -or
                    ($_.indicator -match '(?i)^ECB (Monetary Policy Statement|Marginal Lending|Economic Bulletin)')
                )
            })
            # Pin tier-1 indicators (always included if present):
            #   - Nonfarm Payrolls
            #   - Core / Headline PCE YoY
            #   - Headline CPI (YoY) + Core CPI (YoY)
            #   - Headline PPI (YoY) + Core PPI (YoY) — US only
            #   - ECB Interest Rate Decision / Deposit Facility Rate (Eurozone, flagKey=Europe)
            $pinned = @($filtered | Where-Object {
                ($_.indicator -match '(?i)^Nonfarm Payrolls$') -or
                ($_.indicator -match '(?i)^(Core\s+)?PCE.*Price.*Index.*\(YoY\)$') -or
                ($_.indicator -match '(?i)^(Core\s+)?CPI \(YoY\)$') -or
                (($_.indicator -match '(?i)^(Core\s+)?PPI \(YoY\)$') -and ($_.flagKey -eq 'United_States')) -or
                (($_.indicator -match '(?i)^ECB Interest Rate Decision$') -and ($_.flagKey -eq 'Europe'))
            })
            # If more than $maxN pinned, keep top by importance DESC then datetime ASC
            if ($pinned.Count -gt $maxN) {
                $pinned = @($pinned |
                    Sort-Object @{Expression={ [int]$_.importance }; Descending=$true}, @{Expression='datetime'; Descending=$false} |
                    Select-Object -First $maxN)
            }
            $pinnedIds = @{}
            foreach ($p in $pinned) { $pinnedIds[$p.id] = $true }
            # Fill remaining slots with top-importance non-pinned events
            $remaining = @($filtered |
                Where-Object { ($_.importance -as [int]) -ge 2 -and -not $pinnedIds.ContainsKey($_.id) } |
                Sort-Object @{Expression={ [int]$_.importance }; Descending=$true}, @{Expression='datetime'; Descending=$false})
            $needed = $maxN - $pinned.Count
            if ($needed -lt 0) { $needed = 0 }
            $picked = @($pinned) + @($remaining | Select-Object -First $needed)
            # Final sort: by datetime ascending for chronological display
            return @($picked | Sort-Object datetime)
        }
        $thisTop5 = & $pickTop5 $weekData.events
        $nextTop5 = & $pickTop5 $nextData.events

        $frozen = [ordered]@{
            updated      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            updatedKr    = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            frozenDow    = $dow.ToString()
            reviewRange  = "$reviewFrom~$reviewTo"
            previewRange = "$previewFrom~$previewTo"
            thisWeek     = @($thisTop5)   # legacy name kept for app.js compat — actually "Review" content
            nextWeek     = @($nextTop5)   # legacy name kept — actually "Preview" content
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
