$Host.UI.RawUI.WindowTitle = "TCP_Scanner"

$max_connections = 100 # increase to speed up scans (100 is default)
$timeout = 1500 # milliseconds until a port is deemed to be closed (1500 is default)

$show_updates = $true # prints an update every 1,000 ports
$show_closed = $false # shows closed ports
$debug = $false # prints information on individual socket connections (not recommended)

$TCPPorts = @{
    20   = "FTP (Data Transfer)"
    21   = "FTP (Control)"
    22   = "SSH"
    23   = "Telnet"
    25   = "SMTP"
    53   = "DNS Zone Transfers"
    80   = "HTTP"
    110  = "POP3"
    135  = "RPC"
    139  = "NetBIOS Session Service"
    143  = "IMAP"
    179  = "BGP"
    389  = "LDAP"
    443  = "HTTPS"
    445  = "SMB"
    465  = "SMTPS (SMTP over SSL)"
    514  = "Syslog (TCP - Less Common)"
    587  = "SMTP (Mail Submission)"
    636  = "LDAPS"
    873  = "Rsync"
    902  = "VMware ESXi Remote Console"
    912  = "VMware Authentication Daemon"
    989  = "FTPS (Data)"
    990  = "FTPS (Control)"
    993  = "IMAPS"
    995  = "POP3S"
    1080 = "SOCKS Proxy"
    1194 = "OpenVPN"
    1433 = "MSSQL"
    1521 = "Oracle Database"
    1723 = "PPTP VPN"
    1883 = "MQTT"
    2049 = "NFS"
    2375 = "Docker (Unsecured)"
    2376 = "Docker (Secured)"
    3306 = "MySQL"
    3389 = "RDP"
    3690 = "Subversion (SVN)"
    4444 = "Metasploit"
    4789 = "VXLAN"
    5000 = "Docker Registry / UPnP"
    5060 = "SIP (Unencrypted)"
    5061 = "SIP (Encrypted)"
    5432 = "PostgreSQL"
    5900 = "VNC"
    5985 = "WinRM (HTTP)"
    5986 = "WinRM (HTTPS)"
    6379 = "Redis"
    6667 = "IRC"
    8000 = "Common Web Applications"
    8080 = "HTTP Proxy / Alternative HTTP"
    8443 = "HTTPS Alternative"
    9000 = "SonarQube / Alternate Web Services"
    9090 = "Prometheus / Web Services"
    9200 = "Elasticsearch"
    11211 = "Memcached (Can use TCP)"
    27017 = "MongoDB"
    33848 = "VMware NFC (VM file transfer)"
}

function Resolve_Port ([int]$open_port) {
    if ($TCPPorts.ContainsKey($open_port)) {
        return " - $($TCPPorts[$open_port])"
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
    Write-Host "Running TCP_Scanner.ps1 at $(Get-Date)" -ForegroundColor Cyan
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

    # builds the tcp_clients
    $connectors = @()
    1..${max_connections} | ForEach-Object {
        $connector = New-Object psobject
        # States: 
        # 0 = ready to connect
        # 1 = waiting to connect
        $connector | Add-Member -MemberType NoteProperty -Name "State" -Value 0
        $connector | Add-Member -MemberType NoteProperty -Name "Port" -Value $null
        $connector | Add-Member -MemberType NoteProperty -Name "Time" -Value $null
        $connector | Add-Member -MemberType NoteProperty -Name "Tcp_Client" -Value $(New-Object System.Net.Sockets.TcpClient)
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
            $connectors[$_].Tcp_Client.ConnectAsync($target, $ports[$port_iter]) 1>$null
            $connectors[$_].Port = $ports[$port_iter]
            $connectors[$_].Time = $stopWatch.Elapsed
            $connectors[$_].State = 1
            if ($debug) { Write-Host "Setup TCP_Client $_ - ${target}:$($connectors[$_].Port) - Status $($connectors[$_].State) - Time $($connectors[$_].Time)" -ForegroundColor Yellow }
            if ($show_updates -and $port_iter % 1000 -eq 0) {
                Write-Host "Scanned $($port_iter) of $($ports.Count) ports" -ForegroundColor Yellow
            }
            $port_iter++
        }

        # check on connections
        $finished_checks = $true
        0..$($connectors.Length - 1) | Where-Object { $connectors[$_].State -eq 1 } | ForEach-Object {
            # check if connection is successful
            if ($connectors[$_].Tcp_Client.Connected -eq $true) {
                if ($debug) { Write-Host "Receiving TCP_Client $_ - ${target}:$($connectors[$_].Port) - " -ForegroundColor Yellow -NoNewline }
                Write-Host "Port $($connectors[$_].Port) is open$(Resolve_Port -open_port $connectors[$_].Port)" -ForegroundColor Green
                $connectors[$_].Tcp_Client.Client.Disconnect($true)
            }
            # check if connection failed
            elseif ($stopWatch.Elapsed.TotalMilliseconds - $connectors[$_].Time.TotalMilliseconds -gt $timeout) {
                if ($debug) { Write-Host "Receiving TCP_Client $_ - ${target}:$($connectors[$_].Port) - " -ForegroundColor Yellow -NoNewline }
                if ($show_closed) { Write-Host "Port $($connectors[$_].Port) is closed" -ForegroundColor Red }
            }
            # skip if connection is still pending
            else {
                $finished_checks = $false
                return
            }
            $finished_checks = $false

            # reset connector
            $connectors[$_].Tcp_Client.Dispose()
            $connectors[$_].Tcp_Client = New-Object System.Net.Sockets.TcpClient
            $connectors[$_].Time = $null
            $connectors[$_].Port = $null
            $connectors[$_].State = 0
        }

    }
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "Scanned $($ports.Count) ports in $([math]::Round($stopWatch.Elapsed.TotalSeconds, 2)) seconds" -ForegroundColor Cyan

    # destroy connector objects
    $connectors | ForEach-Object {
        $_.Tcp_Client.Dispose()
    }
    $connectors.Clear()

    $userinput = Read-Host "Press Enter to continue or Q to quit"
    if ($userinput -match "Q") { exit }
}