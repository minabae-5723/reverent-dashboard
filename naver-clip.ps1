# =============================================================
#  Naver blog clip collector - browse normally, collect as you read
#
#  Solves the general research case: any blog, any topic, no keywords,
#  no links to hand over one at a time.
#
#  Flow:
#    1. .\naver-clip.ps1 -Bookmarklet     (once - install in Chrome)
#    2. .\naver-clip.ps1 -Watch           (leave running in a terminal)
#    3. Browse Naver blog normally. On any post worth keeping, click the
#       bookmark. The watcher notices and files it away.
#    4. .\naver-clip.ps1 -Dump            (whole collection -> clipboard)
#    5. Paste into chat.
#
#  This script never touches the network. It only ever reads what you
#  explicitly copied - it is a clipboard manager, not a fetcher. Naver's
#  robots.txt opts out of automated AI/RAG collection, so the "which
#  posts" decision stays with you, one post at a time. In exchange you
#  get full text, which neither the RSS feed nor the search API returns.
#
#  Related: naver-research.ps1 (keyword discovery, snippets only)
#           fetch-naver-blog.ps1 (RSS monitoring of known blogs)
# =============================================================
param(
    # Poll the clipboard and file away any Naver blog capture it sees
    [switch]$Watch,
    # 0 = until Ctrl+C. Set a number to stop automatically.
    [int]$WatchSeconds = 0,
    # Put the whole collection on the clipboard, chat-ready
    [switch]$Dump,
    # Show what has been collected so far
    [switch]$List,
    # Empty the collection
    [switch]$Clear,
    # Print the capture bookmarklet
    [switch]$Bookmarklet,
    # -Dump normally leaves the collection in place; this empties it after
    [switch]$ClearAfterDump
)

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root
$clipFile = Join-Path $root 'naver-clips.md'

# Bookmarklet emits: title \n url \n\n body
# The watcher only accepts captures whose 2nd line is a Naver blog URL,
# so ordinary copying never ends up in the collection by accident.
$NAVER_URL_RX = '^https?://(m\.)?blog\.naver\.com/'

function Get-Clips {
    if (-not (Test-Path -LiteralPath $clipFile)) { return @() }
    $raw = [System.IO.File]::ReadAllText($clipFile, [System.Text.Encoding]::UTF8)
    $out = @()
    foreach ($m in [regex]::Matches($raw, '<!--\s*clip:\s*(?<url>\S+)\s*\|\s*(?<at>[^|]+?)\s*\|\s*(?<chars>\d+)\s*-->\r?\n(?<body>.*?)(?=\r?\n<!--\s*clip:|\z)', 'Singleline')) {
        $out += [PSCustomObject]@{
            url   = $m.Groups['url'].Value
            at    = $m.Groups['at'].Value
            chars = [int]$m.Groups['chars'].Value
            block = $m.Groups['body'].Value.TrimEnd()
        }
    }
    return ,$out
}

function Add-Clip {
    param([string]$Title, [string]$Url, [string]$Body)
    $existing = Get-Clips
    if ($existing | Where-Object { $_.url -eq $Url }) { return 'dup' }
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("<!-- clip: $Url | $stamp | $($Body.Length) -->")
    [void]$sb.AppendLine("## $Title")
    [void]$sb.AppendLine("$Url  ($($Body.Length)자, 수집 $stamp)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine($Body)
    [void]$sb.AppendLine()
    # Append as UTF-8; write the BOM only when creating the file.
    if (Test-Path -LiteralPath $clipFile) {
        [System.IO.File]::AppendAllText($clipFile, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    } else {
        [System.IO.File]::WriteAllText($clipFile, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
    }
    return 'added'
}

# --- bookmarklet ----------------------------------------------
if ($Bookmarklet) {
    $bm = 'javascript:(function(){var d=document,g=function(r){return r?(r.querySelector(".se-main-container")||r.querySelector("#postViewArea")||r.querySelector(".post-view")||r.querySelector("#viewTypeSelector")):null},e=g(d),f=d.querySelector("iframe#mainFrame");if(f){try{e=g(f.contentDocument)||e}catch(x){}}if(!e){e=d.body}var t=(e.innerText||"").replace(/[ \t]+\n/g,"\n").replace(/\n{3,}/g,"\n\n").trim();var ti=(d.title||"").replace(/\s*:\s*네이버\s*블로그\s*$/,"").trim();var u=location.href.split("?")[0];var h=ti+"\n"+u+"\n\n"+t;var a=d.createElement("textarea");a.value=h;d.body.appendChild(a);a.select();d.execCommand("copy");a.remove();alert("클립 복사: "+t.length+"자\n"+ti);})();'
    Write-Host ""
    Write-Host "=== 캡처 북마클릿 (1회 설치) ===" -ForegroundColor Cyan
    Write-Host "Chrome -> 북마크 관리자(Ctrl+Shift+O) -> 새 북마크 추가" -ForegroundColor Yellow
    Write-Host "이름: 네이버클립   /   URL: 아래 전체를 붙여넣기" -ForegroundColor Yellow
    Write-Host ""
    Write-Output $bm
    try { Set-Clipboard -Value $bm; Write-Host ""; Write-Host "(클립보드에 복사했습니다 - 북마크 URL 칸에 바로 붙여넣으세요)" -ForegroundColor Green } catch { }
    Write-Host ""
    Write-Host "설치 후: .\naver-clip.ps1 -Watch  를 켜두고 블로그를 평소처럼 보세요." -ForegroundColor Cyan
    return
}

# --- list -----------------------------------------------------
if ($List) {
    $clips = Get-Clips
    if ($clips.Count -eq 0) { Write-Host "  수집된 클립 없음." -ForegroundColor Yellow; return }
    Write-Host ""
    Write-Host ("  클립 " + $clips.Count + "건 (" + $clipFile + ")") -ForegroundColor Cyan
    $i = 0
    foreach ($c in $clips) {
        $i++
        $title = ($c.block -split "`n" | Where-Object { $_ -match '^##\s' } | Select-Object -First 1) -replace '^##\s*', ''
        Write-Host ("  $i. " + $title)
        Write-Host ("     " + $c.chars + "자 / " + $c.at + " / " + $c.url) -ForegroundColor DarkGray
    }
    Write-Host ""
    return
}

# --- clear ----------------------------------------------------
if ($Clear) {
    if (Test-Path -LiteralPath $clipFile) {
        $n = (Get-Clips).Count
        Remove-Item -LiteralPath $clipFile -Force
        Write-Host ("  클립 " + $n + "건 삭제했습니다.") -ForegroundColor Green
    } else {
        Write-Host "  삭제할 것이 없습니다." -ForegroundColor Yellow
    }
    return
}

# --- dump -----------------------------------------------------
if ($Dump) {
    $clips = Get-Clips
    if ($clips.Count -eq 0) {
        Write-Host "  수집된 클립이 없습니다. -Watch 를 켜고 북마클릿으로 모으세요." -ForegroundColor Yellow
        return
    }
    $totalChars = ($clips | Measure-Object -Property chars -Sum).Sum
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# 네이버 블로그 클립 " + $clips.Count + "건 (본문 전문)")
    [void]$sb.AppendLine("- 내가 직접 열어서 수집한 글입니다. 총 " + $totalChars + "자.")
    [void]$sb.AppendLine("- 아래 내용을 근거로 리서치를 진행해줘.")
    [void]$sb.AppendLine()
    foreach ($c in $clips) {
        [void]$sb.AppendLine($c.block)
        [void]$sb.AppendLine()
    }
    $digest = $sb.ToString()
    try {
        Set-Clipboard -Value $digest
        Write-Host ("  클립 " + $clips.Count + "건 / " + $totalChars + "자 -> 클립보드. 채팅에 붙여넣으세요.") -ForegroundColor Green
    } catch {
        Write-Host ("  클립보드 실패 - " + $clipFile + " 를 여세요.") -ForegroundColor Yellow
    }
    # Very large pastes get truncated by chat clients; warn rather than fail.
    if ($totalChars -gt 60000) {
        Write-Host ("  주의: " + $totalChars + "자는 한 번에 붙여넣기 어려울 수 있습니다. -Clear 로 나눠 보내세요.") -ForegroundColor DarkYellow
    }
    if ($ClearAfterDump) {
        Remove-Item -LiteralPath $clipFile -Force
        Write-Host "  수집분을 비웠습니다." -ForegroundColor DarkGray
    }
    return
}

# --- watch ----------------------------------------------------
if ($Watch) {
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host " Naver clip watcher" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  블로그 글을 열고 '네이버클립' 북마크를 클릭하면 여기에 쌓입니다."
    if ($WatchSeconds -gt 0) { Write-Host ("  " + $WatchSeconds + "초 후 자동 종료") -ForegroundColor DarkGray }
    else { Write-Host "  종료: Ctrl+C" -ForegroundColor DarkGray }
    Write-Host ""

    $seen  = ''
    $added = 0
    $start = Get-Date
    while ($true) {
        if ($WatchSeconds -gt 0 -and ((Get-Date) - $start).TotalSeconds -ge $WatchSeconds) { break }
        $cb = ''
        try { $cb = Get-Clipboard -Raw -ErrorAction Stop } catch { }
        if ($cb -and $cb -ne $seen) {
            $seen = $cb
            $lines = $cb -split "\r?\n"
            if ($lines.Count -ge 3 -and $lines[1] -match $NAVER_URL_RX) {
                $title = $lines[0].Trim()
                $url   = $lines[1].Trim()
                $body  = ($lines[2..($lines.Count-1)] -join "`n").Trim()
                if ($body.Length -lt 100) {
                    Write-Host ("  건너뜀 (본문 " + $body.Length + "자 - 글이 다 로드됐는지 확인): " + $title) -ForegroundColor DarkYellow
                } else {
                    $r = Add-Clip -Title $title -Url $url -Body $body
                    if ($r -eq 'added') {
                        $added++
                        Write-Host ("  [" + $added + "] + " + $title + "  (" + $body.Length + "자)") -ForegroundColor Green
                    } else {
                        Write-Host ("  이미 수집됨: " + $title) -ForegroundColor DarkGray
                    }
                }
            }
        }
        Start-Sleep -Milliseconds 1200
    }
    $total = (Get-Clips).Count
    Write-Host ""
    Write-Host ("  이번 세션 " + $added + "건 추가 / 누적 " + $total + "건") -ForegroundColor Green
    Write-Host "  .\naver-clip.ps1 -Dump  으로 채팅에 넘기세요." -ForegroundColor Cyan
    return
}

# --- no switch ------------------------------------------------
Write-Host ""
Write-Host " naver-clip.ps1 - 읽으면서 모으고, 한 번에 채팅으로" -ForegroundColor Cyan
Write-Host ""
Write-Host "  -Bookmarklet   캡처 북마클릿 출력 (1회 설치)"
Write-Host "  -Watch         클립보드 감시 시작 (켜두고 블로그 열람)"
Write-Host "  -List          수집 현황"
Write-Host "  -Dump          전체를 클립보드로 (채팅에 붙여넣기)"
Write-Host "  -Clear         수집분 비우기"
Write-Host ""
$n = (Get-Clips).Count
Write-Host ("  현재 누적: " + $n + "건") -ForegroundColor Green
Write-Host ""
