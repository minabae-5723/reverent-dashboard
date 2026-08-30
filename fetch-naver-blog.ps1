# =============================================================
#  Naver Blog research fetcher (sanctioned channels only)
#
#  Naver's robots.txt explicitly disallows ClaudeBot / GPTBot / etc.
#  across blog.naver.com, so WebFetch and the browser tools cannot
#  read it. Naver does, however, publish two machine-readable front
#  doors, and this script uses only those:
#
#    1. RSS   - https://rss.blog.naver.com/{blogId}.xml
#               Per-blog feed, ~50 most recent posts.
#               <description> is a PREVIEW (~300-400 chars of text,
#               ends in ".."), not the full post. No key required.
#               Use for watchlist monitoring / triage.
#
#    2. 검색 API - https://openapi.naver.com/v1/search/blog.json
#               Keyword search across all of Naver blog.
#               Needs NAVER_CLIENT_ID / NAVER_CLIENT_SECRET in
#               config.json (free, 25,000 calls/day per app).
#               Register at developers.naver.com -> 애플리케이션 등록
#               -> 사용 API: 검색.  Use for discovery.
#
#  Output: naver-blog.json
#
#  LIMIT: neither channel returns full post text. Both give
#  title + link + date + a short preview/snippet. That is enough to
#  decide WHAT to read; reading a full post means opening its link in
#  a browser yourself.
#
#  Deliberately NOT done here: scraping blog.naver.com HTML with a
#  spoofed User-Agent to recover full text. That is the exact access
#  Naver's robots.txt opts out of, and it also breaks whenever they
#  change markup. The two channels above are stable and permitted.
# =============================================================
param(
    # Blog IDs to pull via RSS. blog.naver.com/ranto28 -> 'ranto28'
    [string[]]$BlogIds = @(),
    # Keywords for 검색 API discovery (requires client id/secret)
    [string[]]$Keywords = @(),
    # Only keep posts newer than this many days
    [int]$Days = 14,
    [int]$DisplayPerKeyword = 30
)

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

# --- config ---------------------------------------------------
$cfgPath = Join-Path $root 'config.json'
$cfg = if (Test-Path -LiteralPath $cfgPath) {
    Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else { $null }
$clientId     = if ($cfg -and $cfg.PSObject.Properties['NAVER_CLIENT_ID'])     { $cfg.NAVER_CLIENT_ID }     else { '' }
$clientSecret = if ($cfg -and $cfg.PSObject.Properties['NAVER_CLIENT_SECRET']) { $cfg.NAVER_CLIENT_SECRET } else { '' }

$cutoff = (Get-Date).AddDays(-$Days)

# Naver wraps title/description/category in CDATA, so $item.description is an
# XmlElement (stringifies to "System.Xml.XmlElement"), not a string. Pull InnerText.
function Get-NodeText {
    param($Node)
    if ($null -eq $Node)      { return '' }
    if ($Node -is [string])   { return $Node }
    if ($Node -is [array])    { return (($Node | ForEach-Object { Get-NodeText $_ }) -join ', ') }
    return [string]$Node.InnerText
}

function Strip-Html {
    param([string]$Text)
    if (-not $Text) { return '' }
    $t = $Text -replace '<br\s*/?>', "`n"
    $t = $t -replace '<[^>]+>', ''
    $t = $t -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"' `
            -replace '&#39;', "'" -replace '&nbsp;', ' ' -replace '&amp;', '&'
    return ($t -replace '[ \t]+', ' ').Trim()
}

# --- 1) RSS per blog ------------------------------------------
function Get-NaverBlogRss {
    param([string]$BlogId)
    $url = "https://rss.blog.naver.com/$BlogId.xml"
    try {
        $resp = Invoke-WebRequest -Uri $url -MaximumRedirection 5 -TimeoutSec 25 -UseBasicParsing
    } catch {
        Write-Warning ("RSS fail ${BlogId}: " + $_.Exception.Message)
        return @()
    }
    # Feed is UTF-8 XML; decode from raw bytes to avoid mojibake
    $xmlText = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
    if ($xmlText.Length -lt 500) {
        Write-Warning "RSS empty for ${BlogId} (blog missing or RSS disabled)"
        return @()
    }
    try { $xml = [xml]$xmlText } catch {
        Write-Warning ("RSS parse fail ${BlogId}: " + $_.Exception.Message); return @()
    }

    $out = @()
    foreach ($item in $xml.rss.channel.item) {
        $pub = $null
        if ($item.pubDate) { try { $pub = [DateTime]::Parse($item.pubDate) } catch { } }
        if ($pub -and $pub -lt $cutoff) { continue }

        # RSS description is a truncated preview ending in ".." - drop the
        # trailing thumbnail markup, keep the text.
        $body = Strip-Html (Get-NodeText $item.description)
        $link = (Get-NodeText $item.link) -replace '\?fromRss=true.*$', ''
        $out += [PSCustomObject]@{
            source   = 'rss'
            blogId   = $BlogId
            title    = Strip-Html (Get-NodeText $item.title)
            link     = $link
            date     = if ($pub) { $pub.ToString('yyyy-MM-dd') } else { $null }
            category = Get-NodeText $item.category
            chars    = $body.Length
            preview  = $body
        }
    }
    return ,$out
}

# --- 2) 검색 API keyword discovery ----------------------------
function Search-NaverBlog {
    param([string]$Query, [int]$Display = 30)
    if (-not $clientId -or -not $clientSecret) { return @() }
    $enc = [System.Uri]::EscapeDataString($Query)
    $url = "https://openapi.naver.com/v1/search/blog.json?query=$enc&display=$Display&sort=date"
    try {
        $r = Invoke-RestMethod -Uri $url -TimeoutSec 25 -Headers @{
            'X-Naver-Client-Id'     = $clientId
            'X-Naver-Client-Secret' = $clientSecret
        }
    } catch {
        Write-Warning ("Search API fail '${Query}': " + $_.Exception.Message)
        return @()
    }
    $out = @()
    foreach ($it in $r.items) {
        $pub = $null
        if ($it.postdate) {
            try { $pub = [DateTime]::ParseExact($it.postdate, 'yyyyMMdd', $null) } catch { }
        }
        if ($pub -and $pub -lt $cutoff) { continue }
        $out += [PSCustomObject]@{
            source   = 'search'
            keyword  = $Query
            title    = Strip-Html $it.title
            link     = $it.link
            date     = if ($pub) { $pub.ToString('yyyy-MM-dd') } else { $null }
            blogName = Strip-Html $it.bloggername
            blogId   = ($it.bloggerlink -replace '^.*blog\.naver\.com/', '' -replace '/.*$', '')
            summary  = Strip-Html $it.description   # snippet only, not full body
        }
    }
    return ,$out
}

# --- run ------------------------------------------------------
Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " Naver Blog fetch (RSS + Search API)" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ("  window: last $Days days (since " + $cutoff.ToString('yyyy-MM-dd') + ")")

$posts = @()
foreach ($id in $BlogIds) {
    Write-Host ("  RSS  $id ...") -NoNewline -ForegroundColor Yellow
    $p = Get-NaverBlogRss -BlogId $id
    Write-Host (" " + $p.Count + " posts")
    $posts += $p
    Start-Sleep -Milliseconds 700
}

$hits = @()
if ($Keywords.Count -gt 0) {
    if (-not $clientId -or -not $clientSecret) {
        Write-Host "  Search API skipped - add NAVER_CLIENT_ID / NAVER_CLIENT_SECRET to config.json" -ForegroundColor DarkYellow
    } else {
        foreach ($k in $Keywords) {
            Write-Host ("  search '$k' ...") -NoNewline -ForegroundColor Yellow
            $h = Search-NaverBlog -Query $k -Display $DisplayPerKeyword
            Write-Host (" " + $h.Count + " hits")
            $hits += $h
            Start-Sleep -Milliseconds 400
        }
    }
}

# Flag search hits that also came through a watched blog's RSS feed, so you
# can tell "this is from someone I already follow" from a cold hit.
$byLink = @{}
foreach ($p in $posts) { if ($p.link) { $byLink[$p.link] = $p } }
foreach ($h in $hits) {
    $watched = ($h.link -and $byLink.ContainsKey($h.link))
    $h | Add-Member -NotePropertyName fromWatchedBlog -NotePropertyValue $watched -Force
}

$out = [ordered]@{
    updated  = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
    source   = 'rss.blog.naver.com (preview) + openapi.naver.com/v1/search/blog.json (snippet)'
    note     = 'preview/summary only - neither channel returns full post text'
    days     = $Days
    blogIds  = $BlogIds
    keywords = $Keywords
    posts    = @($posts | Sort-Object -Property date -Descending)
    hits     = @($hits  | Sort-Object -Property date -Descending)
}
$outPath = Join-Path $root 'naver-blog.json'
$json = $out | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($outPath, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host ("  RSS posts (preview): " + $posts.Count) -ForegroundColor Green
Write-Host ("  Search hits (snippet): " + $hits.Count) -ForegroundColor Green
Write-Host (" Saved -> " + $outPath + "  (" + ((Get-Item -LiteralPath $outPath).Length) + " bytes)") -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Cyan
