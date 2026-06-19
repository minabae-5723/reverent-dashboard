# =============================================================
#  DART corp_code resolver
#  Reads DART_API_KEY from config.json (gitignored), downloads the
#  full corpCode.xml registry once, and prints corp_code matches for
#  each target name listed in a UTF-8 names file (one name per line).
#  ASCII-only comments (PS 5.1 reads .ps1 as cp949).
#  Usage: powershell -File .\find-corpcode.ps1 -NamesFile C:\path\names.txt
# =============================================================
param([string]$NamesFile = '')
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

$cfg = Get-Content (Join-Path $root 'config.json') -Raw | ConvertFrom-Json
$key = $cfg.DART_API_KEY
if (-not $key) { Write-Host 'FATAL: DART_API_KEY missing'; exit 1 }

if (-not $NamesFile -or -not (Test-Path $NamesFile)) { Write-Host 'FATAL: -NamesFile required'; exit 1 }
$targets = Get-Content -LiteralPath $NamesFile -Encoding UTF8 | Where-Object { $_.Trim() -ne '' }

$zip = Join-Path $env:TEMP 'dart-corpcode.zip'
$dir = Join-Path $env:TEMP 'dart-corpcode'
Invoke-WebRequest -Uri "https://opendart.fss.or.kr/api/corpCode.xml?crtfc_key=$key" -OutFile $zip -TimeoutSec 90
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
Expand-Archive $zip -DestinationPath $dir -Force
$xmlPath = Get-ChildItem $dir -Filter *.xml | Select-Object -First 1 -ExpandProperty FullName
$raw = [System.IO.File]::ReadAllText($xmlPath, [System.Text.Encoding]::UTF8)
Write-Host ("Registry: {0} ({1} MB)" -f $xmlPath, [math]::Round((Get-Item $xmlPath).Length/1MB,1))
Write-Host ""

foreach ($t in $targets) {
    $tt = $t.Trim()
    $pattern = "<list>\s*<corp_code>(\d{8})</corp_code>\s*<corp_name>([^<]*" + [regex]::Escape($tt) + "[^<]*)</corp_name>\s*<stock_code>([^<]*)</stock_code>"
    $mx = [regex]::Matches($raw, $pattern)
    if ($mx.Count -eq 0) {
        Write-Host ("[{0}] -> NO MATCH" -f $tt)
    } else {
        foreach ($m in $mx) {
            $stock = $m.Groups[3].Value.Trim()
            $listed = if ($stock) { "LISTED $stock" } else { "unlisted" }
            Write-Host ("[{0}] code={1} name={2} ({3})" -f $tt, $m.Groups[1].Value, $m.Groups[2].Value.Trim(), $listed)
        }
    }
}
