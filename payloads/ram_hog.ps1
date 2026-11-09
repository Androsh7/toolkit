$worker_code = @'
$buckets = New-Object System.Collections.Generic.List[byte[]]
$chunk_size_bytes = 64MB
while ($true) {
    try {
        $bucket = [byte[]]::new($chunk_size_bytes)
        # touch one byte per page so the allocation becomes resident memory
        for ($offset = 0; $offset -lt $chunk_size_bytes; $offset += 4096) { $bucket[$offset] = 1 }
        $buckets.Add($bucket)
    } catch {
        Start-Sleep -Milliseconds 100
    }
}
'@

$worker_count = [Environment]::ProcessorCount
$encoded_worker = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($worker_code))

Write-Host "Spawning $worker_count memory hog workers (Ctrl+C to stop)..."
$current_powershell = (Get-Process -Id $PID).Path
$workers = @()
foreach ($worker_number in 1..$worker_count) {
    $workers += Start-Process $current_powershell -ArgumentList "-NoProfile", "-EncodedCommand", $encoded_worker -PassThru -WindowStyle Hidden
}

try {
    while ($true) {
        Start-Sleep -Seconds 1
        $live_workers = @($workers | Where-Object { -not $_.HasExited })
        $total_working_set_bytes = ($live_workers | Get-Process -ErrorAction SilentlyContinue | Measure-Object WorkingSet64 -Sum).Sum
        if (-not $total_working_set_bytes) { $total_working_set_bytes = 0 }
        Write-Host ("Workers: {0} alive, holding {1:N1} GB" -f $live_workers.Count, ($total_working_set_bytes / 1GB))
    }
} finally {
    foreach ($worker in $workers) {
        if (-not $worker.HasExited) { Stop-Process -Id $worker.Id -Force }
    }
}
