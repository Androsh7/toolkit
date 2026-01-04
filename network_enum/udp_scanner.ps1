$Host.UI.RawUI.WindowTitle = "UDP_Scanner"

$max_connections = 100 # increase to speed up scans (100 is default)
$timeout = 2000 # milliseconds until a port is deemed to be closed (2000 is default)

$show_updates = $true # prints an update every 1000 ports
$show_closed = $false # shows closed ports
$debug = $false # prints information on individual socket connections (not recommended)

$UDPPorts = @{
    53    = "DNS Queries"
    67    = "DHCP (Server)"
    68    = "DHCP (Client)"
    69    = "TFTP"
    123   = "NTP"
    135   = "RPC Locator Service"
    137   = "NetBIOS Name Service"
    138   = "NetBIOS Datagram Service"
    161   = "SNMP"
    162   = "SNMP Trap"
    500   = "IKE (IPsec VPN Negotiation)"
    514   = "Syslog (UDP - Common)"
    520   = "RIP (Routing Information Protocol)"
    623   = "IPMI (Remote Management)"
    1434  = "MSSQL Browser"
    1645  = "RADIUS Authentication (Alternative)"
    1646  = "RADIUS Accounting (Alternative)"
    1701  = "L2TP VPN"
    1812  = "RADIUS Authentication"
    1813  = "RADIUS Accounting"
    1900  = "SSDP (UPnP Discovery)"
    2049  = "NFS (Also TCP)"
    3478  = "STUN (Session Traversal)"
    4500  = "IPsec NAT-T"
    5004  = "RTP (Media Streaming)"
    5005  = "RTCP (Control for RTP)"
    5353  = "mDNS (Multicast DNS)"
    5355  = "LLMNR (Link-Local Multicast Name Resolution)"
    5683  = "CoAP (IoT Protocol)"
    64738 = "Mumble VoIP"
}


function Resolve_Port ([int]$open_port) {
    if ($UDPPorts.ContainsKey($open_port)) {
        return " - $($UDPPorts[$open_port])"
    }
    return ""
}

# takes port ranges and breaks them into individual ports (I.E: 1-5 to 1,2,3,4,5)
function Parse_Ports {
    param (
        [string]$portsInput
    )
    $ports = @()
    $portsInput.Split(',') | ForEach-Object {
        if ($_ -match '(\d+)-(\d+)') {
            $ports += ($matches[1]..$matches[2])
        } else {
            $ports += [int]$_
        }
    }
    return $ports
}

while ($true) {
    Clear-Host
    Write-Host "Running UDP_Scanner.ps1 at $(Get-Date)" -ForegroundColor Cyan
    $target = Read-Host "Enter the target IP address or hostname"

    # attempt to resolve the target
    if ($target -match "^(\d{1,3}\.){3}\d{1,3}$") {
        $target = [IPAddress]$target
    } else {
        try {
            Write-Host "Attempting to resolve $target" -ForegroundColor Yellow
            $dns_resolution = Resolve-DnsName -Name $target -ErrorAction Stop
            $target = [ipaddress]( $dns_resolution | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
            Write-Host "Resolved to $target" -foreground Cyan
        }
        catch {
            Write-Host "Failed to resolve the provided hostname: $target" -ForegroundColor Red
            Write-Host "Aborting scan" -ForegroundColor Red
            Write-Host "Press ENTER to continue"
            Read-Host
            continue
        }
    }
    $portsInput = Read-Host "Enter the ports to scan (e.g. 80, 443-500, 8080)"

    # creates port array
    $ports = Parse_Ports -portsInput $portsInput | Where-Object { $_ -gt 0 -and $_ -lt 65536 } | Sort-Object -Unique

    if ($ports.Count -eq 0) {
        Write-Host "No ports specified aborting scan" -ForegroundColor Red
        Write-Host "Press ENTER to continue"
        Read-Host
        continue
    }
    
    Write-Host "========================================================================" -ForegroundColor Cyan

    # builds the udp_clients
    $connectors = @()
    1..${max_connections} | ForEach-Object {
        $connector = New-Object PSObject
        # States: 
        # 0 = ready to connect
        # 1 = waiting to connect
        $connector | Add-Member -MemberType NoteProperty -Name "State" -Value 0
        $connector | Add-Member -MemberType NoteProperty -Name "Port" -Value $null
        $connector | Add-Member -MemberType NoteProperty -Name "Time" -Value $null
        $connector | Add-Member -MemberType NoteProperty -Name "Udp_Client" -Value $(New-Object System.Net.Sockets.UdpClient)
        $connectors += $connector
    }
    if ($debug) { Write-Host "Setup $($connectors.Count) connectors" -ForegroundColor Yellow }

    # run the scan
    $port_iter = 0
    $finished_connections = $false
    $finished_checks = $false
    $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($finished_connections -eq $false -or $finished_checks -eq $false) {
        # start the connections
        0..$($connectors.length - 1) | Where-Object { $connectors[$_].State -eq 0 } | ForEach-Object {
            if ($port_iter -ge $ports.Count) {
                $finished_connections = $true
                return
            }
            $connectors[$_].Udp_Client.Connect($target, $ports[$port_iter]) 1>$null
            $connectors[$_].Udp_Client.Send([System.Text.Encoding]::UTF8.GetBytes("`0")) 1>$null
            $connectors[$_].Port = $ports[$port_iter]
            $connectors[$_].Time = $stopWatch.Elapsed
            $connectors[$_].State = 1
            if ($debug) { Write-Host "Setup UDP_Client $_ - ${target}:$($connectors[$_].Port) - Status $($connectors[$_].State) - Time $($connectors[$_].Time)" -ForegroundColor Yellow }
            if ($show_updates -and $port_iter % 1000 -eq 0) {
                Write-Host "Scanned $($port_iter) of $($ports.Count) ports" -ForegroundColor Yellow
            }
            $port_iter++
        }

        # check on connections
        $finished_checks = $true
        0..$($connectors.Length - 1) | Where-Object { $connectors[$_].State -eq 1 } | ForEach-Object {
            # check if connection is successful
            if ($connectors[$_].Udp_Client.Client.Available -eq 0 -and $stopWatch.Elapsed.TotalMilliseconds -gt 1000) {
                if ($debug) { Write-Host "Receiving UDP_Client $_ - ${target}:$($connectors[$_].Port) - " -ForegroundColor Yellow -NoNewline }
                Write-Host "Port $($connectors[$_].Port) is open$(Resolve_Port -open_port $connectors[$_].Port)" -ForegroundColor Green
            }
            # check if connection failed
            elseif ($stopWatch.Elapsed.TotalMilliseconds - $connectors[$_].Time.TotalMilliseconds -gt $timeout) {
                if ($debug) { Write-Host "Receiving UDP_Client $_ - ${target}:$($connectors[$_].Port) - " -ForegroundColor Yellow -NoNewline }
                if ($show_closed) { Write-Host "Port $($connectors[$_].Port) is closed" -ForegroundColor Red }
            }
            # skip if connection is still pending
            else {
                $finished_checks = $false
                return
            }
            $finished_checks = $false

            # reset connector
            $connectors[$_].Udp_Client.Dispose()
            $connectors[$_].Udp_Client = New-Object System.Net.Sockets.UdpClient
            $connectors[$_].Time = $null
            $connectors[$_].Port = $null
            $connectors[$_].State = 0
        }

    }
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "NOTE: This UDP scanner relies on ICMP Type 3 Code 3 messages to determine if a port is closed." -ForegroundColor Yellow
    Write-Host "If a firewall is blocking these messages the port will be falsely reported as open" -ForegroundColor Yellow
    Write-Host "Scanned $($ports.Count) ports in $([math]::Round($stopWatch.Elapsed.TotalSeconds, 2)) seconds" -ForegroundColor Cyan

    # destroy connector objects
    $connectors | ForEach-Object {
        $_.Udp_Client.Dispose()
    }
    $connectors.Clear()

    $userinput = Read-Host "Press Enter to continue or Q to quit"
    if ($userinput -match "Q") { exit }
}