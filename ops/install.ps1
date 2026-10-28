# =============================================================
#  One-shot setup for running the dashboard on THIS PC
#
#  Idempotent: safe to re-run (updates tasks in place). What it does:
#    1. checks git + GitHub access (read, and write via push --dry-run)
#    2. registers the user-state.json merge driver
#    3. creates config.json from config.json.example and asks for API keys
#    4. registers the Windows scheduled tasks listed in ops/tasks.json,
#       launched hidden through ops/silent-ps.vbs (shipped in the repo)
#    5. prints which roles (ops/hosts.json) this PC currently owns
#
#  Usage (from the repo root, in a normal - not admin - PowerShell):
#    powershell -NoProfile -ExecutionPolicy Bypass -File .\ops\install.ps1
#    ... -DryRun          show what would happen, change nothing
#    ... -SkipConfig      do not touch config.json
#    ... -Uninstall       remove this repo's scheduled tasks (old operator, after handover)
#
#  Must be run from the main clone, not a linked git worktree: the tasks point
#  at this folder and must keep working after any worktree is deleted.
# =============================================================
param(
    [switch]$DryRun,
    [switch]$SkipConfig,
    [switch]$Uninstall,
    [switch]$Force
)
# 'Continue': in PS 5.1 any git stderr line (even "Everything up-to-date")
# becomes an error record, so 'Stop' would abort on harmless output.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8   # decode git's UTF-8 (Korean names/paths)
$repo = Split-Path $PSScriptRoot -Parent
Set-Location $repo
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE = 'Never'

function Step([string]$m) { Write-Host ""; Write-Host "== $m" -ForegroundColor Cyan }
function Ok([string]$m)   { Write-Host "   OK   $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Host "   WARN $m" -ForegroundColor Yellow }
function Info([string]$m) { Write-Host "        $m" -ForegroundColor DarkGray }

$tasksDef = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'tasks.json') -Raw -Encoding UTF8 | ConvertFrom-Json).tasks

# ---------- Uninstall ----------
if ($Uninstall) {
    Step "Removing scheduled tasks"
    foreach ($t in $tasksDef) {
        if (Get-ScheduledTask -TaskName $t.name -ErrorAction SilentlyContinue) {
            if ($DryRun) { Info "would remove $($t.name)" }
            else { Unregister-ScheduledTask -TaskName $t.name -Confirm:$false; Ok "removed $($t.name)" }
        }
    }
    Info "config.json and the clone itself are left in place."
    exit 0
}

# ---------- 0. Location sanity ----------
Step "Repository: $repo"
$dotGit = Join-Path $repo '.git'
if (-not (Test-Path -LiteralPath $dotGit)) { throw "Not a git clone: $repo" }
# Main clone: .git is a directory. Linked worktree: .git is a file.
if (-not (Test-Path -LiteralPath $dotGit -PathType Container) -and -not $Force) {
    throw "This is a linked git worktree. Run install.ps1 from the main clone (or pass -Force)."
}
if ($repo -match 'OneDrive') { Warn "Repo is inside OneDrive - sync conflicts are likely. Prefer C:\Users\<you>\code\" }
$branch = (& git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne 'main') { Warn "Checked out branch is '$branch'. Scheduled jobs commit to HEAD - switch to main before relying on them." }
else { Ok "on main" }

# ---------- 1. Git access ----------
Step "Git access"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git not found. Install Git for Windows first." }
$name  = (& git config user.name)
$email = (& git config user.email)
if ($name -and $email) { Ok "commit identity: $name <$email>" }
else { Warn "git user.name / user.email not set:  git config --global user.name ""Your Name"" ; git config --global user.email you@company.com" }

& git ls-remote --exit-code origin HEAD 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Ok "can read origin" } else { Warn "cannot read origin - sign in once with:  git fetch  (Git Credential Manager opens a browser)" }

& git push --dry-run origin HEAD:refs/heads/main 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Ok "can push to origin/main (dry run)" }
else { Warn "push dry-run failed. Either no write access (ask the repo owner to add you as a collaborator) or local main is behind (run: git pull)." }

# ---------- 2. Merge driver ----------
Step "user-state.json merge driver"
if ($DryRun) { Info "would set merge.userstate.*" }
else {
    & git config merge.userstate.name 'user-state.json entry-union'
    & git config merge.userstate.driver 'powershell -NoProfile -ExecutionPolicy Bypass -File merge-userstate.ps1 %O %A %B'
    Ok "registered"
}

# ---------- 3. config.json ----------
if (-not $SkipConfig) {
    Step "config.json (personal API keys, gitignored)"
    $cfgPath = Join-Path $repo 'config.json'
    $exPath  = Join-Path $repo 'config.json.example'
    $example = Get-Content -LiteralPath $exPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (Test-Path -LiteralPath $cfgPath) {
        $cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Ok "exists - checking for missing keys"
    } else {
        $cfg = $example
        Info "creating from config.json.example"
    }
    $hints = @{
        ANTHROPIC_API_KEY  = 'AI chat widget - https://console.anthropic.com/ > API Keys'
        DATA_GO_KR_API_KEY = 'monthly trade data - https://www.data.go.kr/ (KCS export/import API)'
        DART_API_KEY       = 'valuation / audit fetchers - https://opendart.fss.or.kr/'
    }
    $changed = -not (Test-Path -LiteralPath $cfgPath)
    foreach ($p in $example.PSObject.Properties) {
        if ($p.Name -like '_*') { continue }
        $cur = $cfg.PSObject.Properties[$p.Name]
        if ($null -eq $cur) {
            $cfg | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
            $cur = $cfg.PSObject.Properties[$p.Name]
            $changed = $true
        }
        $isPlaceholder = ("$($cur.Value)" -match 'PASTE-YOUR')
        if ($isPlaceholder) {
            if ($DryRun) { Warn "$($p.Name) not set"; continue }
            if ($hints[$p.Name]) { Info $hints[$p.Name] }
            $v = Read-Host "   $($p.Name) (Enter = skip, feature stays off)"
            if ($v) { $cur.Value = $v.Trim(); $changed = $true; Ok "$($p.Name) set" }
            else { Warn "$($p.Name) skipped" }
        } else {
            Ok "$($p.Name) present"
        }
    }
    if ($changed -and -not $DryRun) {
        $json = $cfg | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($cfgPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        Ok "config.json written"
    }
}

# ---------- 4. Scheduled tasks ----------
Step "Windows scheduled tasks"
$vbs = Join-Path $PSScriptRoot 'silent-ps.vbs'
if (-not (Test-Path -LiteralPath $vbs)) { throw "missing launcher: $vbs" }
. (Join-Path $PSScriptRoot 'role.ps1')

foreach ($t in $tasksDef) {
    $script = Join-Path $repo $t.script
    if (-not (Test-Path -LiteralPath $script)) { Warn "$($t.name): $($t.script) not found - skipped"; continue }

    $trg = @()
    switch ($t.trigger.type) {
        'repeat' {
            $trg += New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
                -RepetitionInterval (New-TimeSpan -Minutes $t.trigger.minutes) `
                -RepetitionDuration (New-TimeSpan -Days 3650)
            if ($t.trigger.atLogon) { $trg += New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME }
        }
        'daily'  {
            # "daily" + daysOfWeek (e.g. Mon-Fri) = a weekly trigger on those days;
            # a plain -Daily trigger would silently run on weekends too.
            if ($t.trigger.daysOfWeek) { $trg += New-ScheduledTaskTrigger -Weekly -DaysOfWeek $t.trigger.daysOfWeek -At $t.trigger.at }
            else { $trg += New-ScheduledTaskTrigger -Daily -At $t.trigger.at }
        }
        'weekly' { $trg += New-ScheduledTaskTrigger -Weekly -DaysOfWeek $t.trigger.days -At $t.trigger.at }
    }
    if ($trg.Count -eq 0) { Warn "$($t.name): unknown trigger type '$($t.trigger.type)' - skipped"; continue }

    $roleNote = ''
    if ($t.role) { $roleNote = if (Test-ReverentRole $t.role) { " [role $($t.role): ACTIVE here]" } else { " [role $($t.role): skips here]" } }

    if ($DryRun) { Info ("would register {0} -> {1}{2}" -f $t.name, $t.script, $roleNote); continue }

    $act = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"{0}" "{1}"' -f $vbs, $script) -WorkingDirectory $repo
    $set = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
             -ExecutionTimeLimit (New-TimeSpan -Minutes $t.limitMinutes) `
             -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $pr  = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $t.name -Action $act -Trigger $trg -Principal $pr -Settings $set `
        -Description $t.description -Force | Out-Null
    Ok ("{0}{1}" -f $t.name, $roleNote)
}

# The pre-keepalive console launcher; never let it spawn a duplicate server.
$legacy = Get-ScheduledTask -TaskName 'ReverentDashServer' -ErrorAction SilentlyContinue
if ($legacy -and $legacy.State -ne 'Disabled' -and -not $DryRun) {
    Disable-ScheduledTask -TaskName 'ReverentDashServer' | Out-Null
    Ok "disabled legacy task ReverentDashServer"
}

# ---------- 5. Roles ----------
Step "Roles (ops/hosts.json)"
Info "this PC's host id: $(Get-ReverentHostId)"
$hosts = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'hosts.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($r in $hosts.roles.PSObject.Properties) {
    $mark = if (Test-ReverentRole $r.Name) { 'THIS PC' } else { '-' }
    Info ("{0,-10} owner='{1}'  {2}" -f $r.Name, $r.Value, $mark)
}
Info "To make this PC the operator: put its host id under roles.primary in ops/hosts.json, commit, push."

Step "Done"
Info "Start the local server now:  .\START.bat   (KeepAlive also starts it within 5 min)"
Info "Claude Code automations live in the private reverent-dashboard-ops repo - see ops/README.md."
