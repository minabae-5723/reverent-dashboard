# Parse DART audit-report XML: print table rows whose label matches a target
# account, with the numeric cells found in that row. ASCII-only comments.
param([string]$File = '', [string]$Tag = '')
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $File)) { Write-Host "FATAL: file not found"; exit 1 }
$raw = [System.IO.File]::ReadAllText($File, [System.Text.Encoding]::UTF8)

# Target account labels as unicode code-point arrays (avoids cp949 mangling).
$targets = @(
    @{ n = 'REVENUE';        cp = @(47588,52636,50629) },                  # 매출액
    @{ n = 'REVENUE2';       cp = @(47588,52636) },                        # 매출
    @{ n = 'OP_INCOME';      cp = @(50689,50629,51060,51come=0) }
)
Write-Host "placeholder"
