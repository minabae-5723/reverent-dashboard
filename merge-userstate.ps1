# =============================================================
#  Git merge driver: entry-level UNION for user-state.json
#
#  Manually-entered valuations / comments live in user-state.json as an
#  { version, updated, entries{} } map. The default whole-file text merge
#  either dropped one PC's entries (last-writer-wins) or left <<<<<<< markers
#  that then broke every /save-state write (ConvertFrom-Json threw) — i.e.
#  "수기 입력이 자꾸 저장 안 됨". This driver unions the two entry maps so an
#  entry added on either PC is never lost.
#
#  Registered idempotently by sync-repo.ps1 / serve.ps1 / deploy-snapshot.ps1:
#    git config merge.userstate.driver
#       "powershell -NoProfile -ExecutionPolicy Bypass -File <abs>\merge-userstate.ps1 %O %A %B"
#  with .gitattributes:  user-state.json merge=userstate
#  git passes %O=base(ancestor) %A=ours %B=theirs; the driver must write the
#  merged result into %A and exit 0 (resolved). On ANY error it leaves %A
#  untouched and still exits 0 — it must never corrupt the file or wedge a
#  rebase.
# =============================================================
param([string]$Base, [string]$Ours, [string]$Theirs)

$enc = New-Object System.Text.UTF8Encoding($false)

function Load-State([string]$p) {
    $r = @{ entries = @{}; updated = ''; version = 1 }
    if ($p -and (Test-Path -LiteralPath $p)) {
        try {
            $raw = [System.IO.File]::ReadAllText($p, $enc)
            if ($raw.Trim()) {
                $j = $raw | ConvertFrom-Json
                if ($j.version) { $r.version = $j.version }
                if ($j.updated) { $r.updated = "$($j.updated)" }
                if ($j.entries) {
                    foreach ($pr in $j.entries.PSObject.Properties) { $r.entries[$pr.Name] = $pr.Value }
                }
            }
        } catch {}
    }
    return $r
}

try {
    $o = Load-State $Base
    $a = Load-State $Ours
    $b = Load-State $Theirs

    # Which side is newer overall (decides keys edited on BOTH sides).
    $aNewer = $true
    try { if ($a.updated -and $b.updated) { $aNewer = ([datetime]$a.updated -ge [datetime]$b.updated) } } catch {}

    $merged = @{}
    $keys = @(@($a.entries.Keys) + @($b.entries.Keys) | Select-Object -Unique)
    foreach ($k in $keys) {
        $inA = $a.entries.ContainsKey($k)
        $inB = $b.entries.ContainsKey($k)
        if ($inA -and $inB) {
            $av = $a.entries[$k] | ConvertTo-Json -Depth 30 -Compress
            $bv = $b.entries[$k] | ConvertTo-Json -Depth 30 -Compress
            if ($av -eq $bv) { $merged[$k] = $a.entries[$k]; continue }
            $baseJson = if ($o.entries.ContainsKey($k)) { $o.entries[$k] | ConvertTo-Json -Depth 30 -Compress } else { $null }
            if ($null -ne $baseJson -and $av -eq $baseJson)      { $merged[$k] = $b.entries[$k] }  # only theirs changed
            elseif ($null -ne $baseJson -and $bv -eq $baseJson)  { $merged[$k] = $a.entries[$k] }  # only ours changed
            elseif ($aNewer)                                     { $merged[$k] = $a.entries[$k] }  # both changed -> newer
            else                                                 { $merged[$k] = $b.entries[$k] }
        } elseif ($inA) {
            $merged[$k] = $a.entries[$k]   # bias to KEEP (never lose a manual input)
        } else {
            $merged[$k] = $b.entries[$k]
        }
    }

    $newUpdated = if ($aNewer) { $a.updated } else { $b.updated }
    if (-not $newUpdated) { $newUpdated = $a.updated }
    $out = [ordered]@{ version = $a.version; updated = $newUpdated; entries = [PSCustomObject]$merged }
    $json = $out | ConvertTo-Json -Depth 30
    [System.IO.File]::WriteAllText($Ours, $json, $enc)
    exit 0
} catch {
    # Never corrupt user-state.json or wedge the merge — keep ours as-is.
    exit 0
}
