# =============================================================
#  Naver Blog research digest -> clipboard (paste into chat)
#
#  Purpose: keyword-driven discovery with NO blog IDs / links to
#  supply by hand. You give topics, it returns a ranked digest and
#  puts a chat-ready markdown block on your clipboard.
#
#  Channel: openapi.naver.com/v1/search/blog.json (검색 API)
#    - free, 25,000 calls/day per app
#    - needs NAVER_CLIENT_ID / NAVER_CLIENT_SECRET in config.json
#    - register: developers.naver.com -> 애플리케이션 등록
#                -> 사용 API: 검색
#
#  What you get per hit: title, link, date, blog name, short snippet.
#  What you do NOT get: full post text. Naver's robots.txt opts out of
#  AI/RAG bot access, and the API only returns snippets. To read a post
#  in full, open its link and use the bookmarklet (see -Bookmarklet).
#
#  Why sort=sim by default: a single broad keyword returns ~1,000 posts
#  per week on Naver blog, most of it content-farm output. sort=date
#  then just surfaces whoever posted most recently, which is noise.
#  Relevance order plus the spam filter below is what makes this usable.
#
#  Usage:
#    .\naver-research.ps1 -Query "반도체 실적","HBM 가격"
#    .\naver-research.ps1 -Query "조선 수주" -Days 7 -Top 15
#    .\naver-research.ps1 -Query "2차전지" -Sort date      # monitoring
#    .\naver-research.ps1 -Query "2차전지" -NoFilter       # see raw
#    .\naver-research.ps1 -Bookmarklet                     # copy helper
# =============================================================
param(
    # Topics to search. No blog IDs needed.
    [string[]]$Query = @(),
    # Only keep posts newer than this many days
    [int]$Days = 14,
    # Max hits to include in the digest after ranking
    [int]$Top = 25,
    # 'sim' = Naver relevance (default, best for research)
    # 'date' = newest first (best for monitoring a fast-moving topic)
    [ValidateSet('sim','date')]
    [string]$Sort = 'sim',
    # Stop pulling after this many raw results per keyword.
    # Relevance decays fast; going deeper mostly adds farm output.
    [int]$Max = 200,
    # Keep content-farm / AI-generated posts instead of dropping them
    [switch]$NoFilter,
    # Print the full-text copy bookmarklet and exit
    [switch]$Bookmarklet
)

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

# --- bookmarklet: user-initiated, one post at a time ----------
# This is NOT a crawler. You open a post yourself, click the bookmark,
# and the post's own text goes to your clipboard - same as Ctrl+A/Ctrl+C,
# just cleaned up. Then paste it into chat for full-text analysis.
if ($Bookmarklet) {
    # Single source of truth for capture lives in naver-clip.ps1.
    Write-Host ""
    Write-Host "  본문 캡처는 naver-clip.ps1 로 옮겼습니다:" -ForegroundColor Cyan
    Write-Host "    .\naver-clip.ps1 -Bookmarklet   # 북마클릿 설치" -ForegroundColor Yellow
    Write-Host "    .\naver-clip.ps1 -Watch         # 읽으면서 모으기" -ForegroundColor Yellow
    Write-Host "    .\naver-clip.ps1 -Dump          # 한 번에 채팅으로" -ForegroundColor Yellow
    Write-Host ""
    return
}

if ($Query.Count -eq 0) {
    Write-Host "  -Query 를 지정하세요. 예: .\naver-research.ps1 -Query '반도체 실적','HBM'" -ForegroundColor Yellow
    return
}

# --- config ---------------------------------------------------
$cfgPath = Join-Path $root 'config.json'
$cfg = if (Test-Path -LiteralPath $cfgPath) {
    Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else { $null }
$clientId     = if ($cfg -and $cfg.PSObject.Properties['NAVER_CLIENT_ID'])     { $cfg.NAVER_CLIENT_ID }     else { '' }
$clientSecret = if ($cfg -and $cfg.PSObject.Properties['NAVER_CLIENT_SECRET']) { $cfg.NAVER_CLIENT_SECRET } else { '' }

if (-not $clientId -or -not $clientSecret) {
    Write-Host ""
    Write-Host "  NAVER_CLIENT_ID / NAVER_CLIENT_SECRET 가 config.json 에 없습니다." -ForegroundColor Red
    Write-Host "  키워드 검색은 검색 API 없이는 불가능합니다 (RSS는 블로그 ID가 필요)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1) https://developers.naver.com/apps/#/register" -ForegroundColor Cyan
    Write-Host "  2) 사용 API: '검색' 선택, 환경: WEB (URL은 http://localhost)" -ForegroundColor Cyan
    Write-Host "  3) 발급된 Client ID / Secret 을 config.json 에 추가:" -ForegroundColor Cyan
    Write-Host '       "NAVER_CLIENT_ID": "...", "NAVER_CLIENT_SECRET": "..."' -ForegroundColor DarkGray
    Write-Host ""
    return
}

$cutoff = (Get-Date).AddDays(-$Days)

function Strip-Html {
    param([string]$Text)
    if (-not $Text) { return '' }
    $t = $Text -replace '<br\s*/?>', ' '
    $t = $t -replace '<[^>]+>', ''            # 검색 API wraps matches in <b>
    $t = $t -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"' `
            -replace '&#39;', "'" -replace '&nbsp;', ' ' -replace '&amp;', '&'
    return ($t -replace '\s+', ' ').Trim()
}

# --- spam / AI-dump scoring -----------------------------------
# Naver blog search is dominated by content farms and reposted LLM
# output. We only have title / snippet / blog name / post frequency to
# work with, so these are cheap signals, not a classifier. Score >= 3
# gets dropped; -NoFilter keeps everything.
function Get-SpamScore {
    param([string]$Title, [string]$Snippet, [string]$BlogName, [int]$BlogPostCount)
    $s = 0
    $text = "$Title $Snippet"

    # Posting the same topic many times a week is farm behaviour, not
    # analysis. This is the signal the old frequency ranking got backwards.
    if ($BlogPostCount -ge 6)  { $s += 2 }
    if ($BlogPostCount -ge 12) { $s += 3 }

    # Pasted chatbot output: offers to keep helping, names the model,
    # or carries the bracketed citation markers assistants emit.
    if ($text -match '찾아드릴까요|알려드릴까요|정리해드릴까요|도와드릴까요') { $s += 3 }
    if ($text -match 'GPT|챗지피티|제미나이|AI가 정리|AI 요약')              { $s += 3 }
    if ($text -match '\[\d+(,\s*\d+)+\]')                                   { $s += 2 }

    # Default blog name means the author never set one up.
    if ($BlogName -match '님의 블로그$') { $s += 1 }

    # Keyword-stuffed title with no spaces, e.g. "테크윙HBM검사장비"
    if ($Title.Length -ge 10 -and $Title -notmatch '\s') { $s += 2 }

    return $s
}

function Search-NaverBlog {
    param([string]$Q, [int]$Display, [int]$Start)
    $enc = [System.Uri]::EscapeDataString($Q)
    $url = "https://openapi.naver.com/v1/search/blog.json?query=$enc&display=$Display&start=$Start&sort=$Sort"
    try {
        return Invoke-RestMethod -Uri $url -TimeoutSec 25 -Headers @{
            'X-Naver-Client-Id'     = $clientId
            'X-Naver-Client-Secret' = $clientSecret
        }
    } catch {
        Write-Warning ("search '$Q' start=$Start : " + $_.Exception.Message)
        return $null
    }
}

# --- run ------------------------------------------------------
Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " Naver Blog research digest" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ("  window: last $Days days (since " + $cutoff.ToString('yyyy-MM-dd') + ")  sort=$Sort")

$all = @()
$rank = 0
foreach ($q in $Query) {
    Write-Host ("  search '$q' ...") -NoNewline -ForegroundColor Yellow
    $kept = 0
    $pulled = 0
    # display caps at 100, start caps at 1000.
    for ($start = 1; $start -le 1000 -and $pulled -lt $Max; $start += 100) {
        $r = Search-NaverBlog -Q $q -Display 100 -Start $start
        if (-not $r -or -not $r.items -or $r.items.Count -eq 0) { break }
        $pulled += $r.items.Count
        $pageHasFresh = $false
        foreach ($it in $r.items) {
            $pub = $null
            if ($it.postdate) {
                try { $pub = [DateTime]::ParseExact($it.postdate, 'yyyyMMdd', $null) } catch { }
            }
            if ($pub -and $pub -lt $cutoff) { continue }
            $pageHasFresh = $true
            $rank++
            $all += [PSCustomObject]@{
                keyword  = $q
                apiRank  = $rank        # preserves Naver's relevance order
                title    = Strip-Html $it.title
                link     = $it.link
                date     = if ($pub) { $pub.ToString('yyyy-MM-dd') } else { '' }
                blogName = Strip-Html $it.bloggername
                blogId   = ($it.bloggerlink -replace '^.*blog\.naver\.com/', '' -replace '/.*$', '')
                snippet  = Strip-Html $it.description
            }
            $kept++
        }
        # sort=date is chronological, so once a whole page predates the
        # window nothing later can qualify. sort=sim is not ordered by
        # date, so we must keep paging to $Max regardless.
        if ($Sort -eq 'date' -and -not $pageHasFresh) { break }
        Start-Sleep -Milliseconds 300
    }
    Write-Host (" $kept in window (of $pulled pulled)")
    Start-Sleep -Milliseconds 300
}

if ($all.Count -eq 0) {
    Write-Host "  결과 없음 - 기간을 늘리거나 키워드를 바꿔보세요." -ForegroundColor Yellow
    return
}

# Dedupe by link, merging the keywords that surfaced the same post.
# A post hit by several of your topics is usually the more relevant one.
$byLink = [ordered]@{}
foreach ($h in $all) {
    if ($byLink.Contains($h.link)) {
        $e = $byLink[$h.link]
        if ($e.keywords -notcontains $h.keyword) { $e.keywords += $h.keyword }
        if ($h.apiRank -lt $e.apiRank) { $e.apiRank = $h.apiRank }
    } else {
        $h | Add-Member -NotePropertyName keywords -NotePropertyValue @($h.keyword) -Force
        $byLink[$h.link] = $h
    }
}
$uniq = @($byLink.Values)

# Per-blog post counts feed the spam score, so compute them first.
$freq = @{}
foreach ($u in $uniq) { if ($u.blogId) { $freq[$u.blogId] = 1 + [int]$freq[$u.blogId] } }

foreach ($u in $uniq) {
    $cnt = 0
    if ($u.blogId) { $cnt = [int]$freq[$u.blogId] }
    $score = Get-SpamScore -Title $u.title -Snippet $u.snippet -BlogName $u.blogName -BlogPostCount $cnt
    $u | Add-Member -NotePropertyName spam      -NotePropertyValue $score -Force
    $u | Add-Member -NotePropertyName blogPosts -NotePropertyValue $cnt   -Force
}

$clean   = @($uniq | Where-Object { $_.spam -lt 3 })
$dropped = $uniq.Count - $clean.Count
if ($NoFilter) { $clean = $uniq; $dropped = 0 }

if ($clean.Count -eq 0) {
    Write-Host ("  " + $uniq.Count + "건 전부 스팸 필터에 걸렸습니다. -NoFilter 로 원본을 확인하세요.") -ForegroundColor Yellow
    return
}

# Rank: multi-keyword hits first, then Naver's own relevance (sim) or
# recency (date).
if ($Sort -eq 'date') {
    $ranked = @($clean | Sort-Object -Property @{Expression={$_.keywords.Count}; Descending=$true}, `
                                               @{Expression={$_.date};           Descending=$true})
} else {
    $ranked = @($clean | Sort-Object -Property @{Expression={$_.keywords.Count}; Descending=$true}, `
                                               @{Expression={$_.apiRank};        Descending=$false})
}
$picked = @($ranked | Select-Object -First $Top)

# Follow candidates: blogs that recur a little are topical writers.
# Blogs that recur a lot are farms - the old version promoted exactly
# those, so cap the range and list the high-volume ones separately.
$follow = @($freq.GetEnumerator() | Where-Object { $_.Value -ge 2 -and $_.Value -le 5 } |
            Sort-Object -Property Value -Descending | Select-Object -First 10)
$farms  = @($freq.GetEnumerator() | Where-Object { $_.Value -ge 6 } |
            Sort-Object -Property Value -Descending | Select-Object -First 5)

# --- build chat-pasteable digest ------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# 네이버 블로그 리서치 다이제스트")
# $($Days)일 not $Days일 - Korean chars are legal in PS variable names, so
# "$Days일" parses as a variable named "Days일" and silently yields empty.
[void]$sb.AppendLine("- 수집: " + (Get-Date).ToString('yyyy-MM-dd HH:mm') + " / 최근 $($Days)일 / 정렬: $Sort / 검색어: " + ($Query -join ', '))
[void]$sb.AppendLine("- 고유 " + $uniq.Count + "건 → 스팸 " + $dropped + "건 제외 → 상위 " + $picked.Count + "건")
[void]$sb.AppendLine("- 출처: 네이버 검색 API (스니펫만, 본문 전문 아님)")
[void]$sb.AppendLine()
$i = 0
foreach ($p in $picked) {
    $i++
    $tag = if ($p.keywords.Count -gt 1) { " `[" + ($p.keywords -join '+') + "`]" } else { "" }
    [void]$sb.AppendLine("$i. **$($p.title)**$tag")
    [void]$sb.AppendLine("   $($p.blogName) / $($p.date) / $($p.link)")
    [void]$sb.AppendLine("   > $($p.snippet)")
    [void]$sb.AppendLine()
}
if ($follow.Count -gt 0) {
    [void]$sb.AppendLine("## RSS 추적 후보 (2-5건 반복 = 해당 주제를 꾸준히 쓰는 블로그)")
    foreach ($f in $follow) {
        [void]$sb.AppendLine("- $($f.Key) ($($f.Value)건) - https://rss.blog.naver.com/$($f.Key).xml")
    }
    [void]$sb.AppendLine()
}
if ($farms.Count -gt 0) {
    [void]$sb.AppendLine("## 고빈도 (6건+ / 양산형 의심, 추적 비권장)")
    [void]$sb.AppendLine("- " + (($farms | ForEach-Object { "$($_.Key)($($_.Value))" }) -join ', '))
    [void]$sb.AppendLine()
}
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("위 목록에서 읽을 글을 골라줘. 전문이 필요한 건 내가 열어서 붙여넣을게.")

$digest = $sb.ToString()

$outPath = Join-Path $root 'naver-research.md'
# BOM here (unlike the .json outputs): this .md gets opened by hand on
# Windows, and without a BOM the Korean shows up as mojibake.
[System.IO.File]::WriteAllText($outPath, $digest, (New-Object System.Text.UTF8Encoding($true)))
try {
    Set-Clipboard -Value $digest
    $clip = 'clipboard OK - 채팅에 그대로 붙여넣으세요'
} catch {
    $clip = 'clipboard 실패 - naver-research.md 파일을 여세요'
}

Write-Host ""
Write-Host ("  unique: " + $uniq.Count + "  spam dropped: " + $dropped + "  ->  digest: " + $picked.Count) -ForegroundColor Green
if ($follow.Count -gt 0) {
    Write-Host ("  RSS 추적 후보: " + (($follow | ForEach-Object { $_.Key }) -join ', ')) -ForegroundColor Green
}
if ($farms.Count -gt 0) {
    Write-Host ("  양산형 의심 (제외): " + (($farms | ForEach-Object { $_.Key }) -join ', ')) -ForegroundColor DarkYellow
}
Write-Host ("  saved -> " + $outPath) -ForegroundColor Green
Write-Host ("  " + $clip) -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Cyan
