# =============================================================
#  Reverent Partners - Economic Calendar Fetcher
#  Source: Investing.com /Service/getCalendarFilteredData
#  Output: calendar.json (ASCII keys; UI labels mapped in app.js)
# =============================================================
param([switch]$Loop, [int]$IntervalSec = 1800)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Web

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
$TodayFile    = Join-Path $PSScriptRoot 'calendar.json'
$WeekFile     = Join-Path $PSScriptRoot 'calendar-week.json'
$NextWeekFile = Join-Path $PSScriptRoot 'calendar-next-week.json'
$FrozenFile   = Join-Path $PSScriptRoot 'market-update-frozen.json'

# ── __NEXT_DATA__ scraper (fallback for 403-blocked AJAX API) ────────
# The calendar page embeds all today's events as JSON in __NEXT_DATA__.
# curl.exe bypasses PowerShell's TLS/redirect quirks and reliably gets 200.
# Returns events in the same schema as Parse-Events so the patch logic can
# match them against the frozen file by indicator + date.
function Get-TodayFromNextData {
    try {
        $raw = & curl.exe -sL 'https://www.investing.com/economic-calendar/' `
            -H "User-Agent: $UA" `
            -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' `
            -H 'Accept-Language: en-US,en;q=0.5' `
            -H 'Upgrade-Insecure-Requests: 1' 2>$null
        if (-not $raw) { return @() }
        $html = $raw -join "`n"

        $m = [regex]::Match($html,
            '<script id="__NEXT_DATA__"[^>]*>(.*?)</script>',
            [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if (-not $m.Success) { return @() }

        $pattern = '\{[^\{\}]*?"country"\s*:\s*"[^"]*"[^\{\}]*?"actual"\s*:\s*"[^"]*"[^\{\}]*?\}'
        $hits = [regex]::Matches($m.Groups[1].Value, $pattern)
        $events = @()
        foreach ($h in $hits) {
            try {
                $obj = $h.Value | ConvertFrom-Json
                $indicator = $obj.event
                if ($obj.suffix) { $indicator = "$indicator $($obj.suffix)" }
                $flagKey = ($obj.country -replace ' ', '_')
                $kstTime = ''
                $kstDate = $null
                if ($obj.time -match 'T(\d{2}):(\d{2}):\d{2}Z') {
                    $utcH = [int]$Matches[1]; $utcM = $Matches[2]
                    if ($obj.date -match '^\d{4}-\d{2}-\d{2}') {
                        $utcDt = [datetime]::ParseExact($obj.date, 'yyyy-MM-dd', $null)
                        $kstH = $utcH + 9
                        if ($kstH -ge 24) { $kstH -= 24; $utcDt = $utcDt.AddDays(1) }
                        $kstTime = '{0:D2}:{1}' -f $kstH, $utcM
                        $kstDate = $utcDt
                    }
                }
                $shortDate = ''
                if ($kstDate) {
                    $shortDate = "{0}/{1}" -f $kstDate.Month, $kstDate.Day
                }
                $dtKst = ''
                if ($kstDate -and $kstTime) {
                    $dtKst = $kstDate.ToString('yyyy/MM/dd') + " ${kstTime}:00"
                }
                $events += [PSCustomObject]@{
                    indicator  = $indicator
                    flagKey    = $flagKey
                    date       = $shortDate
                    datetime   = $dtKst
                    actual     = if ($obj.actual) { $obj.actual } else { '' }
                    forecast   = if ($obj.forecast) { $obj.forecast } else { '' }
                    previous   = if ($obj.previous) { $obj.previous } else { '' }
                    importance = [int]$obj.importance
                    period     = ($obj.period -replace '^\(|\)$', '')
                }
            } catch {}
        }
        return $events
    } catch {
        Write-Warning ("__NEXT_DATA__ fetch fail: " + $_.Exception.Message)
        return @()
    }
}

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
    param([string]$Tab, [string]$OutPath, [string]$DateFrom = '', [string]$DateTo = '', [string]$FrozenKey = '')

    $html = Get-InvestingCalendar -Tab $Tab -DateFrom $DateFrom -DateTo $DateTo
    $events = @(Parse-Events -Html $html)

    # Fallback: investing.com economic calendar is Cloudflare-blocked (HTTP 403),
    # leaving events empty and the #weekly view blank. market-update-frozen.json
    # holds this-week / next-week top events in the SAME schema (Monday snapshot),
    # so fill from it when the live scrape returns nothing -> calendar never empty.
    #
    # BUT: never let a 403 destroy a good file. The full calendar is periodically
    # refilled by hand from a logged-in browser (same-origin fetch bypasses
    # Cloudflare, ~50 events vs the frozen digest's ~6). Every server start used to
    # overwrite that with the thin fallback. So if the existing file already holds
    # real investing data for the SAME tab/range, keep it and bail out.
    #
    # The tab/range check used to require an EXACT match, which broke on Sundays:
    # Get-WeekBounds calls Mon~Sun of the *calendar* week (e.g. 08-24~08-30) while
    # the hand-filled file targets the upcoming week (08-31~09-06). The ranges
    # differ, the guard fell through, and a 403 wiped ~60 real events. So also
    # keep the file when its range simply has not expired yet (end date >= today).
    if ($events.Count -eq 0 -and (Test-Path $OutPath)) {
        try {
            $prev = Get-Content $OutPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $prevTab = if ($Tab -eq 'custom') { "custom $DateFrom~$DateTo" } else { $Tab }
            # ISO yyyy-MM-dd sorts lexicographically, so a plain string compare is
            # enough here — and avoids TryParseExact's [ref] binding quirks in PS 5.1
            # (a throw there would be swallowed by the catch and silently skip the guard).
            $stillValid = $false
            if ($prev.tab -match 'custom\s+\d{4}-\d{2}-\d{2}~(\d{4}-\d{2}-\d{2})') {
                $stillValid = ($Matches[1] -ge (Get-Date).ToString('yyyy-MM-dd'))
            }
            if ($prev.source -eq 'investing' -and @($prev.events).Count -gt 0 -and ($prev.tab -eq $prevTab -or $stillValid)) {
                # Materialise the array once — inline `@($prev.events).Count` inside a
                # format operator misreports as 1 in PS 5.1, which reads like data loss.
                $prevEvents  = @($prev.events)
                $prevCount   = $prevEvents.Count
                $highImpPrev = @($prevEvents | Where-Object { $_.importance -ge 2 }).Count
                Write-Host ("  keep existing investing data ({0} events) -> {1}" -f $prevCount, (Split-Path $OutPath -Leaf)) -ForegroundColor DarkYellow
                return [PSCustomObject]@{ count = $prevCount; highImp = $highImpPrev; path = $OutPath }
            }
        } catch {}
    }

    $srcNote = 'investing'
    if ($events.Count -eq 0 -and $FrozenKey) {
        $frozenPath = Join-Path $PSScriptRoot 'market-update-frozen.json'
        if (Test-Path $frozenPath) {
            try {
                $fz = Get-Content $frozenPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($fz.$FrozenKey) { $events = @($fz.$FrozenKey); $srcNote = 'frozen-fallback' }
            } catch { Write-Warning ("frozen fallback fail: " + $_.Exception.Message) }
        }
    }

    $tabLabel = if ($Tab -eq 'custom') { "custom $DateFrom~$DateTo" } else { $Tab }
    $output = [ordered]@{
        updated   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        updatedKr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        countries = $COUNTRY_IDS
        tab       = $tabLabel
        source    = $srcNote
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
    $weekFrom    = '{0:yyyy-MM-dd}' -f $wb.thisMon
    $weekTo      = '{0:yyyy-MM-dd}' -f $wb.thisSun
    $previewFrom = '{0:yyyy-MM-dd}' -f $wb.nextMon
    $previewTo   = '{0:yyyy-MM-dd}' -f $wb.nextSun
    # REVIEW/PREVIEW 카드 제목에 찍히는 라벨은 영업주(월~금) 기준으로 고정한다.
    # (fetch 구간은 위 월~일 그대로 두고 라벨만 금요일에서 끊는다)
    $reviewLabelTo  = '{0:yyyy-MM-dd}' -f $wb.thisMon.AddDays(4)
    $previewLabelTo = '{0:yyyy-MM-dd}' -f $wb.nextMon.AddDays(4)

    $today    = Save-Calendar -Tab 'today' -OutPath $TodayFile -FrozenKey 'thisWeek'
    $week     = Save-Calendar -Tab 'custom' -DateFrom $weekFrom    -DateTo $weekTo    -OutPath $WeekFile     -FrozenKey 'thisWeek'
    $nextWeek = Save-Calendar -Tab 'custom' -DateFrom $previewFrom -DateTo $previewTo -OutPath $NextWeekFile -FrozenKey 'nextWeek'

    $elapsed = [int](New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds
    Write-Host ("  today:    {0} events ({1} medium+) -> calendar.json"           -f $today.count,    $today.highImp)    -ForegroundColor Green
    Write-Host ("  Week ({0}~{1}): {2} events ({3} medium+) -> calendar-week.json" -f $weekFrom, $weekTo, $week.count, $week.highImp) -ForegroundColor Green
    Write-Host ("  Preview ({0}~{1}): {2} events ({3} medium+) -> calendar-next-week.json" -f $previewFrom, $previewTo, $nextWeek.count, $nextWeek.highImp) -ForegroundColor Green

    # ─── Frozen weekly snapshot for Market Update dashboard section ───
    # REVIEW/PREVIEW 짝은 '일요일'에만 넘어간다 (사용자 규칙).
    # 일요일 freeze → REVIEW = 막 끝난 주, PREVIEW = 다가오는 주.
    # 월~토에는 그 짝이 그대로 유지되므로 주중에 라벨이 바뀌지 않는다.
    $dow = (Get-Date).DayOfWeek
    $isRollDay = ($dow -eq [System.DayOfWeek]::Sunday)

    # Preserve manual curation: if a freeze for THIS week already exists, keep it.
    # Week identity = this-week Monday ($reviewFrom) + next-week Monday ($previewFrom),
    # both stable across Fri→Sun. The auto-pick below would clobber indicators the
    # user manually added/removed in the dashboard, so only (re)freeze when the file
    # is missing OR it's a genuinely NEW week. (The first freeze of the week is the
    # auto-digest; the user curates it, and weekend restarts no longer overwrite it.)
    $sameWeek = $false
    if (Test-Path $FrozenFile) {
        try {
            $existingFrozen = Get-Content $FrozenFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $exRevFrom  = ($existingFrozen.reviewRange  -split '~')[0]
            $exPrevFrom = ($existingFrozen.previewRange -split '~')[0]
            if ($exRevFrom -eq $reviewFrom -and $exPrevFrom -eq $previewFrom) { $sameWeek = $true }
        } catch {}
    }
    # ── Shared helpers for freeze / Friday update ──
    # 주당 10~16건 (미국+한국+일본). 종전 top-7은 너무 적어 preview가 매번 잘려나갔다.
    $maxN = 14
    $pickTop5 = {
        param($events)
        if (-not $events) { return @() }
        # Macro Economy 섹션은 ★★★만 구성한다 (app.js MACRO_MIN_IMPORTANCE = 3).
        $events = @($events | Where-Object { ($_.importance -as [int]) -ge 3 })
        $filtered = @($events | Where-Object {
            -not (
                ($_.indicator -match '(?i)PCE.*\(MoM\)') -or
                ($_.indicator -match '(?i)^(Core\s+)?CPI \(MoM\)$') -or
                ($_.indicator -match '(?i)^CPI[,]?\s*(n\.s\.a|s\.a|Index)') -or
                ($_.indicator -match '(?i)^Cleveland CPI') -or
                ($_.indicator -match '(?i)Speaks$') -or
                ($_.indicator -match '(?i)Press Conference') -or
                ($_.indicator -match '(?i)^ECB (Monetary Policy Statement|Marginal Lending|Economic Bulletin)') -or
                (($_.indicator -match '(?i)CPI') -and ($_.flagKey -eq 'Europe')) -or
                ($_.indicator -match '(?i)^FOMC (Economic Projections|Statement)$')
            )
        })
        $pinned = @($filtered | Where-Object {
            ($_.indicator -match '(?i)^Nonfarm Payrolls$') -or
            ($_.indicator -match '(?i)^(Core\s+)?PCE.*Price.*Index.*\(YoY\)$') -or
            ($_.indicator -match '(?i)^(Core\s+)?CPI \(YoY\)$') -or
            (($_.indicator -match '(?i)^(Core\s+)?PPI \(YoY\)$') -and ($_.flagKey -eq 'United_States')) -or
            (($_.indicator -match '(?i)^ECB Interest Rate Decision$') -and ($_.flagKey -eq 'Europe')) -or
            (($_.indicator -match '(?i)^Fed Interest Rate Decision$') -and ($_.flagKey -eq 'United_States'))
        })
        if ($pinned.Count -gt $maxN) {
            $pinned = @($pinned |
                Sort-Object @{Expression={ [int]$_.importance }; Descending=$true}, @{Expression='datetime'; Descending=$false} |
                Select-Object -First $maxN)
        }
        $pinnedIds = @{}
        foreach ($p in $pinned) { $pinnedIds[$p.id] = $true }
        $remaining = @($filtered |
            Where-Object { ($_.importance -as [int]) -ge 2 -and -not $pinnedIds.ContainsKey($_.id) } |
            Sort-Object @{Expression={ [int]$_.importance }; Descending=$true}, @{Expression='datetime'; Descending=$false})
        $needed = $maxN - $pinned.Count
        if ($needed -lt 0) { $needed = 0 }
        $picked = @($pinned) + @($remaining | Select-Object -First $needed)
        return @($picked | Sort-Object datetime)
    }
    $applyFedRange = {
        param($evs)
        foreach ($e in $evs) {
            if ($e.indicator -match '(?i)^Fed Interest Rate Decision$') {
                foreach ($fld in 'forecast','previous','actual') {
                    $v = "$($e.$fld)"
                    if ($v -match '^\s*([0-9]+(?:\.[0-9]+)?)\s*%\s*$') {
                        $hi = [double]$Matches[1]
                        $lo = $hi - 0.25
                        $e.$fld = ('{0:0.00}%~{1:0.00}%' -f $lo, $hi)
                    }
                }
            }
        }
    }

    $shouldFreeze = (-not (Test-Path $FrozenFile)) -or ($isRollDay -and -not $sameWeek)
    $isFriday = ($dow -eq [System.DayOfWeek]::Friday)

    if ($shouldFreeze) {
        $weekData = $null; $nextData = $null
        try { $weekData = Get-Content $WeekFile     -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
        try { $nextData = Get-Content $NextWeekFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}

        $thisTop5 = & $pickTop5 $weekData.events
        $nextTop5 = & $pickTop5 $nextData.events
        & $applyFedRange $thisTop5
        & $applyFedRange $nextTop5

        $frozen = [ordered]@{
            updated      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            updatedKr    = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            frozenDow    = $dow.ToString()
            reviewRange  = "$reviewFrom~$reviewLabelTo"
            previewRange = "$previewFrom~$previewLabelTo"
            thisWeek     = @($thisTop5)
            nextWeek     = @($nextTop5)
        }
        $json = $frozen | ConvertTo-Json -Depth 8
        [System.IO.File]::WriteAllText($FrozenFile, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host ("  frozen:   thisWeek={0} nextWeek={1} -> market-update-frozen.json" -f $thisTop5.Count, $nextTop5.Count) -ForegroundColor Yellow
    } else {
        # Event lineup stays frozen, but patch actual/forecast from the freshly-
        # fetched calendar data so released values show up immediately.
        $why = if ($sameWeek) { "lineup kept" } else { "weekday $dow" }
        try {
            $fz = Get-Content $FrozenFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $weekEvents = @()
            $nextEvents = @()
            if (Test-Path $WeekFile) {
                try { $weekEvents = @((Get-Content $WeekFile -Raw -Encoding UTF8 | ConvertFrom-Json).events) } catch {}
            }
            if (Test-Path $NextWeekFile) {
                try { $nextEvents = @((Get-Content $NextWeekFile -Raw -Encoding UTF8 | ConvertFrom-Json).events) } catch {}
            }

            # Also fetch today's events from __NEXT_DATA__ (bypasses 403 AJAX block)
            $todayLive = @(Get-TodayFromNextData)
            if ($todayLive.Count -gt 0) {
                Write-Host ("  __NEXT_DATA__: {0} events for today" -f $todayLive.Count) -ForegroundColor DarkGray
            }

            $patched = 0
            $patchFromCalendar = {
                param($frozenEvents, $freshEvents)
                if (-not $frozenEvents -or -not $freshEvents -or $freshEvents.Count -eq 0) { return 0 }
                $count = 0
                foreach ($fe in $frozenEvents) {
                    $match = $freshEvents | Where-Object {
                        $_.datetime -eq $fe.datetime -and $_.indicator -eq $fe.indicator
                    } | Select-Object -First 1
                    if (-not $match) { continue }
                    if ($match.actual -and $match.actual -ne $fe.actual) {
                        $fe.actual = $match.actual
                        $fe.type = 'review'
                        $count++
                    }
                    if ($match.forecast -and $match.forecast -ne $fe.forecast) {
                        $fe.forecast = $match.forecast
                        $count++
                    }
                }
                return $count
            }
            $patchFromLive = {
                param($frozenEvents, $liveEvents)
                if (-not $frozenEvents -or -not $liveEvents -or $liveEvents.Count -eq 0) { return 0 }
                $count = 0
                foreach ($fe in $frozenEvents) {
                    $match = $liveEvents | Where-Object {
                        $_.date -eq $fe.date -and $_.indicator -eq $fe.indicator -and $_.flagKey -eq $fe.flagKey
                    } | Select-Object -First 1
                    if (-not $match) { continue }
                    if ($match.actual -and $match.actual -ne $fe.actual) {
                        $fe.actual = $match.actual
                        $fe.type = 'review'
                        $count++
                    }
                    if ($match.forecast -and $match.forecast -ne $fe.forecast) {
                        $fe.forecast = $match.forecast
                        $count++
                    }
                }
                return $count
            }

            # 일요일 롤 정책(2026-08-17)에서 frozen.thisWeek = 막 끝난 주,
            # frozen.nextWeek = '지금 진행 중인 주'다. 즉 nextWeek의 실제치는
            # calendar-next-week.json이 아니라 calendar-week.json에 들어온다.
            # 매칭 키가 datetime+indicator 완전일치라 두 소스를 합쳐도 오매칭 없음.
            $allEvents = @($weekEvents) + @($nextEvents)
            if ($fz.thisWeek) {
                $patched += & $patchFromCalendar $fz.thisWeek $allEvents
                $patched += & $patchFromLive $fz.thisWeek $todayLive
            }
            if ($fz.nextWeek) {
                $patched += & $patchFromCalendar $fz.nextWeek $allEvents
                $patched += & $patchFromLive $fz.nextWeek $todayLive
            }

            # Friday: refresh nextWeek PREVIEW lineup with next week's events
            if ($isFriday) {
                $nextData = $null
                try { $nextData = Get-Content $NextWeekFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
                $nextTop5 = & $pickTop5 $nextData.events
                & $applyFedRange $nextTop5
                $fz.nextWeek = @($nextTop5)
                $fz.previewRange = "$previewFrom~$previewLabelTo"
                $patched++
                Write-Host ("  frozen:   Friday — PREVIEW refreshed ({0} events, {1})" -f $nextTop5.Count, $fz.previewRange) -ForegroundColor Cyan
            }

            if ($patched -gt 0) {
                # Re-apply Fed range formatting on patched values
                foreach ($side in @($fz.thisWeek, $fz.nextWeek)) {
                    if (-not $side) { continue }
                    foreach ($e in $side) {
                        if ($e.indicator -match '(?i)^Fed Interest Rate Decision$') {
                            foreach ($fld in 'forecast','previous','actual') {
                                $v = "$($e.$fld)"
                                if ($v -match '^\s*([0-9]+(?:\.[0-9]+)?)\s*%\s*$') {
                                    $hi = [double]$Matches[1]
                                    $lo = $hi - 0.25
                                    $e.$fld = ('{0:0.00}%~{1:0.00}%' -f $lo, $hi)
                                }
                            }
                        }
                    }
                }
                $fz.updated = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                $fz.updatedKr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                $json = $fz | ConvertTo-Json -Depth 8
                [System.IO.File]::WriteAllText($FrozenFile, $json, (New-Object System.Text.UTF8Encoding($false)))
                Write-Host ("  frozen:   $why — patched $patched actual/forecast value(s)") -ForegroundColor Yellow
            } else {
                Write-Host ("  frozen:   $why — no new actuals") -ForegroundColor DarkGray
            }
        } catch {
            Write-Warning ("frozen patch fail: " + $_.Exception.Message)
        }
    }

    # --- frozen -> calendar-week / calendar-next-week reverse sync ---------
    # #weekly view reads calendar-week.json / calendar-next-week.json, but
    # Investing is Cloudflare-blocked (403) so those files stay pinned to the
    # last hand-filled snapshot. Only market-update-frozen.json gets the
    # curated lineup and the actuals filled in by the daily task (Trading
    # Economics / WebSearch), so #weekly kept showing empty actuals while the
    # dashboard Macro Economy card was current (2026-09-02 user report).
    # Treat frozen as the source of truth and push its values back:
    #   - match on date + indicator + flagKey (minute-level time differs by source)
    #   - never overwrite with an empty frozen value (protects live-scraped data)
    #   - append frozen events the calendar file does not have at all
    #     (KR/JP indicators that only exist in the curated frozen lineup)
    $syncFrozenToCalendar = {
        param($FrozenPath, $Targets)
        if (-not (Test-Path $FrozenPath)) { return }
        $fz = $null
        try { $fz = Get-Content $FrozenPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return }
        $frozenAll = @()
        foreach ($k in 'thisWeek','nextWeek') { if ($fz.$k) { $frozenAll += @($fz.$k) } }
        if ($frozenAll.Count -eq 0) { return }

        foreach ($t in $Targets) {
            if (-not (Test-Path $t.Path)) { continue }
            $leaf = Split-Path $t.Path -Leaf
            $data = $null
            try { $data = Get-Content $t.Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
            $events = @($data.events)
            $changed = 0; $added = 0
            foreach ($fe in $frozenAll) {
                # frozen datetime is "yyyy/MM/dd HH:mm:ss" (slash separator is
                # mandatory for parseInvestingDateTime); tolerate hyphen anyway.
                $d = ''
                if ("$($fe.datetime)" -match '^(\d{4})[/-](\d{2})[/-](\d{2})') {
                    $d = "$($Matches[1])-$($Matches[2])-$($Matches[3])"
                }
                if (-not $d) { continue }
                # route each frozen event by its own date, not by which array it
                # sits in (the Sunday roll shifts thisWeek/nextWeek meaning)
                if ($d -lt $t.From -or $d -gt $t.To) { continue }

                $match = $events | Where-Object {
                    $_.date -eq $fe.date -and
                    "$($_.indicator)".Trim() -eq "$($fe.indicator)".Trim() -and
                    $_.flagKey -eq $fe.flagKey
                } | Select-Object -First 1

                if (-not $match) {
                    $events += $fe
                    $added++
                    continue
                }
                foreach ($fld in 'actual','forecast','previous') {
                    $v = "$($fe.$fld)"
                    if ($v -ne '' -and $v -ne "$($match.$fld)") { $match.$fld = $v; $changed++ }
                }
                if ("$($fe.actual)" -ne '' -and $match.type -ne 'review') {
                    $match.type = 'review'
                    $changed++
                }
                # frozen is hand-curated at importance 3; Investing sometimes rates
                # the same indicator 2 (e.g. Core CPI YoY), which hid it behind the
                # #weekly star filter while the Macro card showed it. Raise only.
                if (($fe.importance -as [int]) -gt ($match.importance -as [int])) {
                    $match.importance = ($fe.importance -as [int])
                    $changed++
                }
            }
            if ($changed -eq 0 -and $added -eq 0) {
                Write-Host ("  sync:     {0} already matches frozen" -f $leaf) -ForegroundColor DarkGray
                continue
            }
            $data.events    = @($events | Sort-Object datetime)
            $data.updated   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            $data.updatedKr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            $json = $data | ConvertTo-Json -Depth 6
            [System.IO.File]::WriteAllText($t.Path, $json, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host ("  sync:     {0} <- frozen ({1} value(s) patched, {2} event(s) added)" -f $leaf, $changed, $added) -ForegroundColor Yellow
        }
    }
    & $syncFrozenToCalendar $FrozenFile @(
        [PSCustomObject]@{ Path = $WeekFile;     From = $weekFrom;    To = $weekTo },
        [PSCustomObject]@{ Path = $NextWeekFile; From = $previewFrom; To = $previewTo }
    )

    Write-Host ("  done in {0}s" -f $elapsed) -ForegroundColor DarkGray

    if ($Loop) { Start-Sleep -Seconds $IntervalSec }
} while ($Loop)
