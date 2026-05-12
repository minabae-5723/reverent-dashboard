# Extract SSD / NAND / DRAM monthly export data to JSON
# Input path via $env:XLSX_PATH, output path via $env:JSON_OUT
$path = $env:XLSX_PATH
$out  = $env:JSON_OUT

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$wb = $excel.Workbooks.Open($path)

function Extract-Sheet {
    param([object]$Sheet)
    $rows = $Sheet.UsedRange.Rows.Count
    $data = @()

    # Scan rows; col B should match "YYYY<non-digits>M<non-digits>" pattern
    # (Korean date format YYYY-Nyun M-Wol, but written in regex without
    # Korean characters so this .ps1 stays ASCII-safe across PS encodings)
    for ($r = 1; $r -le $rows; $r++) {
        $yymm = $Sheet.Cells.Item($r, 2).Text
        if ($yymm -match '^\s*(\d{4})\D+(\d{1,2})\D*$') {
            $year  = [int]$matches[1]
            $month = [int]$matches[2]
            if ($month -lt 1 -or $month -gt 12) { continue }
            $valueText = $Sheet.Cells.Item($r, 3).Text
            $vClean = $valueText -replace '[,\s]', ''
            $value = $null
            if ($vClean -match '^-?\d+(\.\d+)?$') { $value = [double]$vClean }
            $monthStr = ('{0:D4}-{1:D2}' -f $year, $month)
            $data += [PSCustomObject]@{
                month = $monthStr
                value = $value
            }
        }
    }
    return ,$data
}

$result = [ordered]@{
    updated   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    updatedKr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    source    = 'Manual Excel import — see read-trade-excel.ps1'
}

foreach ($s in $wb.Sheets) {
    $name = $s.Name.ToLower()
    $extracted = Extract-Sheet -Sheet $s
    $result[$name] = $extracted
    $first = if ($extracted.Count -gt 0) { $extracted[0].month } else { '(empty)' }
    $last  = if ($extracted.Count -gt 0) { $extracted[-1].month } else { '(empty)' }
    Write-Host ("  " + $s.Name + ": " + $extracted.Count + " rows  [" + $first + " .. " + $last + "]")
}

$wb.Close($false)
$excel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
[System.GC]::Collect()

$json = $result | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($out, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ""
Write-Host ("OK -> " + $out + "  (" + ((Get-Item -LiteralPath $out).Length) + " bytes)")
