# =============================================================
#  Naver Finance FX (Seoul-close basis)
#
#  Pulls past 10-30 days of 매매기준율 (Seoul interbank close) for the
#  4 KRW-base pairs Naver supports, then:
#    - Selects the most recent Friday close → "current" for dashboard
#    - WoW = prev Friday close / current
#    - MoM = ~4 Fridays back
#    - YTD = first trading day of year
#    - Derives USD-base cross rates (USDJPY etc.) from KRW pairs
#
#  Output: fx-naver-snapshot.json (consumed by refresh.ps1 to override Yahoo FX)
#
#  Why this is needed: Yahoo's KRW=X close is NY-close (Sat 06 AM KST),
#  which differs from Seoul interbank close (Fri 15:30 KST) by 5-15 won
#  typically. Korean financial media report the Seoul close.
# =============================================================
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

# Naver only supports KRW-base FX. fdtc=4 = currency category.
# `page=` parameter not respected for these; one call returns ~10 most recent days.
# For deeper history (YTD), we walk multiple page numbers.
$pairs = [ordered]@{
    USDKRW = 'FX_USDKRW'
    JPYKRW = 'FX_JPYKRW'   # quoted per 100 JPY
    CNYKRW = 'FX_CNYKRW'
    EURKRW = 'FX_EURKRW'
}

function Get-NaverDailyHistory {
    param([string]$Code, [int]$Pages = 12)
    $all = @()
    for ($p = 1; $p -le $Pages; $p++) {
        try {
            $url = "https://finance.naver.com/marketindex/exchangeDailyQuote.naver?marketindexCd=$Code&fdtc=4&page=$p"
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add('User-Agent', $UA)
            $bytes = $wc.DownloadData($url)
            $wc.Dispose()
            $html = [System.Text.Encoding]::GetEncoding('EUC-KR').GetString($bytes)
            $rx = '<tr[^>]*>\s*<td class="date">(\d{4}\.\d{2}\.\d{2})</td>\s*<td class="num">([\d,\.]+)</td>'
            $rows = [regex]::Matches($html, $rx, 'Singleline')
            if ($rows.Count -eq 0) { break }
            foreach ($m in $rows) {
                $date = $m.Groups[1].Value -replace '\.', '-'   # 2026.05.22 -> 2026-05-22
                $price = [double](($m.Groups[2].Value -replace ',', '').Trim())
                $all += [PSCustomObject]@{ date = $date; close = $price }
            }
            Start-Sleep -Milliseconds 600
        } catch {
            Write-Warning ("Page $p fail for ${Code}: " + $_.Exception.Message)
            break
        }
    }
    # Dedupe + sort ascending
    $seen = @{}
    $out = @()
    foreach ($r in ($all | Sort-Object date)) {
        if (-not $seen.ContainsKey($r.date)) { $seen[$r.date] = $true; $out += $r }
    }
    return ,$out
}

# Find most recent Friday in a history list (date strings yyyy-MM-dd, ascending)
function Find-LastFriday {
    param([array]$History)
    for ($i = $History.Count - 1; $i -ge 0; $i--) {
        $dt = [DateTime]::Parse($History[$i].date)
        if ($dt.DayOfWeek -eq [System.DayOfWeek]::Friday) {
            return [PSCustomObject]@{ idx = $i; entry = $History[$i] }
        }
    }
    return $null
}
function Find-PrevFriday {
    param([array]$History, [int]$FromIdx, [int]$WeeksBack = 1)
    $c = 0
    for ($i = $FromIdx - 1; $i -ge 0; $i--) {
        $dt = [DateTime]::Parse($History[$i].date)
        if ($dt.DayOfWeek -eq [System.DayOfWeek]::Friday) {
            $c++
            if ($c -eq $WeeksBack) { return $History[$i] }
        }
    }
    return $null
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " Naver Finance FX (Seoul-close basis)" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# Fetch all pairs
$histories = @{}
foreach ($key in $pairs.Keys) {
    Write-Host ("  Fetching $key history...") -ForegroundColor Yellow
    $h = Get-NaverDailyHistory -Code $pairs[$key] -Pages 12
    Write-Host ("    -> " + $h.Count + " days [" + $h[0].date + " .. " + $h[-1].date + "]")
    $histories[$key] = $h
    Start-Sleep -Milliseconds 800
}

# For each pair, compute current (last Friday) + WoW/MoM/YTD pct
$result = [ordered]@{}
foreach ($key in $pairs.Keys) {
    $h = $histories[$key]
    if (-not $h -or $h.Count -lt 2) { continue }
    $curFri = Find-LastFriday -History $h
    if (-not $curFri) { continue }
    $prevFri = Find-PrevFriday -History $h -FromIdx $curFri.idx -WeeksBack 1
    $momFri  = Find-PrevFriday -History $h -FromIdx $curFri.idx -WeeksBack 4
    $year    = ([DateTime]::Parse($curFri.entry.date)).Year
    $ytd     = $h | Where-Object { $_.date.StartsWith("$year-") } | Select-Object -First 1

    $cur = $curFri.entry.close
    $result[$key] = [ordered]@{
        current  = $cur
        wow      = if ($prevFri) { [Math]::Round((($cur - $prevFri.close) / $prevFri.close) * 100, 2) } else { $null }
        mom      = if ($momFri)  { [Math]::Round((($cur - $momFri.close) / $momFri.close) * 100, 2)  } else { $null }
        ytd      = if ($ytd)     { [Math]::Round((($cur - $ytd.close) / $ytd.close) * 100, 2)         } else { $null }
        asOf     = $curFri.entry.date
        prevDate = if ($prevFri) { $prevFri.date } else { $null }
    }
}

# Derive USD-base cross rates from KRW pairs
$derived = [ordered]@{}
if ($result.USDKRW) {
    $usdkrw = $result.USDKRW.current
    $derived['USDKRW'] = $result.USDKRW
    if ($result.JPYKRW) {
        $usdjpy = [Math]::Round($usdkrw / ($result.JPYKRW.current / 100.0), 3)
        # WoW/MoM/YTD for USDJPY: combine inverse-pct of JPYKRW relative to USDKRW
        # Approximation: USDJPY pct change ≈ USDKRW pct - JPYKRW pct
        $derived['USDJPY'] = [ordered]@{
            current = $usdjpy
            wow  = if ($null -ne $result.USDKRW.wow -and $null -ne $result.JPYKRW.wow) { [Math]::Round($result.USDKRW.wow - $result.JPYKRW.wow, 2) } else { $null }
            mom  = if ($null -ne $result.USDKRW.mom -and $null -ne $result.JPYKRW.mom) { [Math]::Round($result.USDKRW.mom - $result.JPYKRW.mom, 2) } else { $null }
            ytd  = if ($null -ne $result.USDKRW.ytd -and $null -ne $result.JPYKRW.ytd) { [Math]::Round($result.USDKRW.ytd - $result.JPYKRW.ytd, 2) } else { $null }
            asOf = $result.USDKRW.asOf
        }
    }
    if ($result.CNYKRW) {
        $usdcny = [Math]::Round($usdkrw / $result.CNYKRW.current, 4)
        $derived['USDCNY'] = [ordered]@{
            current = $usdcny
            wow  = if ($null -ne $result.USDKRW.wow -and $null -ne $result.CNYKRW.wow) { [Math]::Round($result.USDKRW.wow - $result.CNYKRW.wow, 2) } else { $null }
            mom  = if ($null -ne $result.USDKRW.mom -and $null -ne $result.CNYKRW.mom) { [Math]::Round($result.USDKRW.mom - $result.CNYKRW.mom, 2) } else { $null }
            ytd  = if ($null -ne $result.USDKRW.ytd -and $null -ne $result.CNYKRW.ytd) { [Math]::Round($result.USDKRW.ytd - $result.CNYKRW.ytd, 2) } else { $null }
            asOf = $result.USDKRW.asOf
        }
    }
    if ($result.EURKRW) {
        $usdeur = [Math]::Round($usdkrw / $result.EURKRW.current, 4)
        $derived['USDEUR'] = [ordered]@{
            current = $usdeur
            wow  = if ($null -ne $result.USDKRW.wow -and $null -ne $result.EURKRW.wow) { [Math]::Round($result.USDKRW.wow - $result.EURKRW.wow, 2) } else { $null }
            mom  = if ($null -ne $result.USDKRW.mom -and $null -ne $result.EURKRW.mom) { [Math]::Round($result.USDKRW.mom - $result.EURKRW.mom, 2) } else { $null }
            ytd  = if ($null -ne $result.USDKRW.ytd -and $null -ne $result.EURKRW.ytd) { [Math]::Round($result.USDKRW.ytd - $result.EURKRW.ytd, 2) } else { $null }
            asOf = $result.USDKRW.asOf
        }
    }
}

Write-Host ""
Write-Host "Seoul-close FX snapshot:" -ForegroundColor Green
foreach ($k in $derived.Keys) {
    $r = $derived[$k]
    Write-Host ("  $k  current=$($r.current)  WoW=$($r.wow)%  asOf=$($r.asOf)")
}

$out = [ordered]@{
    updated = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    source  = 'finance.naver.com exchangeDailyQuote (Seoul 매매기준율)'
    fx      = $derived
}
$snapPath = Join-Path $root 'fx-naver-snapshot.json'
$json = $out | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($snapPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ""
Write-Host (" Saved -> " + $snapPath + "  (" + ((Get-Item -LiteralPath $snapPath).Length) + " bytes)") -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Cyan
