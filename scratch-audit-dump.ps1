# Download DART audit report originals (ZIP->XML) and dump to scratch files.
# ASCII-only comments (PS 5.1 reads .ps1 as cp949).
param([string]$OutDir = '')
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root
$cfg = Get-Content (Join-Path $root 'config.json') -Raw | ConvertFrom-Json
$k = $cfg.DART_API_KEY
if (-not $OutDir) { $OutDir = Join-Path $env:TEMP 'dart-docs' }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

$targets = @(
    @{ name = 'SKTNS';        rcept = '20260326000042' },
    @{ name = 'GongchaKorea'; rcept = '20260402003616' }
)

foreach ($t in $targets) {
    $zip = Join-Path $OutDir ($t.name + '.zip')
    $dir = Join-Path $OutDir $t.name
    Write-Host ("=== " + $t.name + " rcept=" + $t.rcept)
    Invoke-WebRequest -Uri ("https://opendart.fss.or.kr/api/document.xml?crtfc_key=$k&rcept_no=" + $t.rcept) -OutFile $zip -TimeoutSec 120
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    Expand-Archive $zip -DestinationPath $dir -Force
    Get-ChildItem $dir | ForEach-Object {
        Write-Host ("   file: " + $_.Name + "  " + [math]::Round($_.Length/1KB,0) + " KB")
    }
}
Write-Host ("OUTDIR=" + $OutDir)
