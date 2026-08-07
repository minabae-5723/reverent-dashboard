# =============================================================
#  Insert preliminary (잠정치) month rows into trade.json.
#
#  Rows carry preliminary=$true. fetch-trade.ps1 replaces any month it
#  successfully fetches from the Customs API, so once the confirmed figures
#  are published the preliminary row (and its flag) is overwritten
#  automatically. No change to fetch-trade.ps1 is required.
#
#  ASCII-only comments (PS 5.1 reads .ps1 as cp949).
#  Usage: powershell -ExecutionPolicy Bypass -File .\add-trade-prelim.ps1
# =============================================================
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root
$path = Join-Path $root 'trade.json'

$raw  = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
$data = $raw | ConvertFrom-Json

# 2026-07 preliminary export figures (Korea Customs provisional release).
# expDlrRaw is the published USD amount; weight is derived as expDlr/unitPrice.
# SSD was published rounded to 3 significant figures with no unit price, so
# weight/unitPrice stay null for it.
$rows = @(
    @{ key='dram'; value=13552; weight=155819; unitPrice=86970;  expDlrRaw=13551550000 },
    @{ key='mcp';  value=10086; weight=105714; unitPrice=95407;  expDlrRaw=10085850000 },
    @{ key='nand'; value=1781;  weight=28835;  unitPrice=61751;  expDlrRaw=1780650000  },
    @{ key='ssd';  value=4510;  weight=$null;  unitPrice=$null;  expDlrRaw=4510000000  }
)
$month = '2026-07'

foreach ($r in $rows) {
    $k = $r.key
    $series = @($data.$k)
    # Drop an existing row for this month so re-running is idempotent
    $series = @($series | Where-Object { $_.month -ne $month })
    $newRow = [PSCustomObject]@{
        month       = $month
        value       = [double]$r.value
        weight      = $r.weight
        unitPrice   = $r.unitPrice
        expDlrRaw   = [double]$r.expDlrRaw
        impDlrRaw   = $null
        impWgtRaw   = $null
        preliminary = $true
    }
    $series += $newRow
    $data.$k = @($series | Sort-Object month)
    $last = $data.$k[-1]
    Write-Host ("  {0,-5} -> {1} rows, last={2} value={3}" -f $k, $data.$k.Count, $last.month, $last.value)
}

$data | Add-Member -NotePropertyName preliminaryMonths -NotePropertyValue @($month) -Force
$data | Add-Member -NotePropertyName preliminaryNote -NotePropertyValue 'DRAM/MCP/NAND/SSD 2026-07 are provisional (jamjeongchi). fetch-trade.ps1 overwrites them once the Customs API publishes confirmed figures.' -Force

$json = $data | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host (" Saved -> " + $path + "  (" + ((Get-Item -LiteralPath $path).Length) + " bytes)")
