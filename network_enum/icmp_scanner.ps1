$Host.UI.RawUI.WindowTitle = "ICMP Scanner"

$max_connections = 100 # increase to speed up scans (100 is default)

$show_unreachable = $false # shows unsuccessful pings

$debug = $false # prints debug information

function Get_Addresses_Between ([byte[]]$StartBytes, [byte[]]$EndBytes) {
    $address_array = @()

    $StartInt = [int32]"0x$([System.BitConverter]::ToString($StartBytes).Replace('-',''))"
    $EndInt = [int32]"0x$([System.BitConverter]::ToString($EndBytes).Replace('-',''))"

    ${StartInt}..$([math]::max(${EndInt},${StartInt})) | ForEach-Object {
        $HexString = [convert]::ToString($_, 16).PadLeft(8, "0")
        $oct1 = [convert]::FromHexString($HexString.Substring(0,2))
        $oct2 = [convert]::FromHexString($HexString.Substring(2,2))
        $oct3 = [convert]::FromHexString($HexString.Substring(4,2))
        $oct4 = [convert]::FromHexString($HexString.Substring(6,2))
        $address_array += [ipaddress]"$oct1.$oct2.$oct3.$oct4"
    }
    return $address_array
}
function Parse_Machines ($user_input) {
    $out_array = @()
    $user_input -split "," | ForEach-Object {
        if ($_ -match "^(\d+\.){3}\d+$") {
            $out_array += [ipaddress]$_
        } elseif ($_ -match '^(\d+\.){3}\d+-(\d+\.){3}\d+$') {
            $range = $_ -split "-"
            $startIP = [ipaddress]($range[0])
            $endIP = [ipaddress]($range[1])
            $startBytes = $startIP.GetAddressBytes()
            $endBytes = $endIP.GetAddressBytes()

            Get_Addresses_Between -StartBytes $startBytes -EndBytes $endBytes | ForEach-Object {
                $out_array += $_
            }

        } elseif ($_ -match '^(\d+\.){3}\d+/\d{1,2}$') {
            $split_IP = $_ -split "/"
            $currentIP = [ipaddress]$split_ip[0]
            $currentBytes = $currentIP.GetAddressBytes()

            $currentBinary = ""
            0..3 | ForEach-Object {
                $currentBinary += [convert]::ToString($currentBytes[$_], 2).PadLeft(8, "0")
            }
            
            $subnetMask = [int32]$split_IP[1]
            $subnetBinary = "$("1" * $subnetMask)$("0" * (32 - $subnetMask))"
            
            $startBinary = ""
            $startBinary = ""
            0..31 | ForEach-Object {
                if ($subnetBinary[$_] -eq "1") {
                    $endBinary += $currentBinary[$_]
                    $startBinary += $currentBinary[$_]
                } else {
                    $endBinary += "1"
                    $startBinary += "0"
                }
            }

            $endBytes = New-Object byte[] 4
            $startBytes = New-Object byte[] 4
            0..3 | ForEach-Object {
                $startBytes[$_] = [convert]::ToInt32(($startBinary.Substring($_ * 8, 8)), 2)
                $endBytes[$_] = [convert]::ToInt32(($endBinary.Substring($_ * 8, 8)), 2)
            }

            Get_Addresses_Between -StartBytes $startBytes -EndBytes $endBytes | ForEach-Object {
                $out_array += $_
            }

        }   else {
            $out_array += "$_"
        }
    }
    Return $out_array
}

While ($true) {
    Clear-Host
    Write-Host "Running ICMP_Scanner.ps1 at $(Get-Date)" -ForegroundColor Cyan
    $input = Read-Host "Enter IP addresses I.E: (192.168.1.1, 10.15.1.1-10.15.1.255, Machine15)"
    $machines = Parse_Machines -user_input $input.Replace(" ", "")

    Write-Host "========================================================================" -ForegroundColor Cyan

    # builds the ping objects
    $connectors = @()
    1..$([math]::max(${max_connections}, $machines.Count)) | ForEach-Object {
        $connector = New-Object psobject
        # States: 
        # 0 = ready to connect
        # 1 = waiting to connect
        $connector | Add-Member -MemberType NoteProperty -Name "State" -Value 0
        $connector | Add-Member -MemberType NoteProperty -Name "Host" -Value $null
        $connector | Add-Member -MemberType NoteProperty -Name "Time" -Value $null
        $connector | Add-Member -MemberType NoteProperty -Name "Ping_Result" -Value $null
        $connector | Add-Member -MemberType NoteProperty -Name "Pinger" -Value $(New-Object System.Net.NetworkInformation.Ping)
        $connectors += $connector
    }
    if ($debug) { Write-Host "Setup $($connectors.Count) pingers" -ForegroundColor Yellow }

    # run the scan
    $host_iter = 0
    $finished_connections = $false
    $finished_checks = $false
    $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    $last_update = $stopWatch.Elapsed.TotalSeconds
    while ($finished_connections -eq $false -or $finished_checks -eq $false) {
        # start the connections
        0..$($connectors.length - 1) | Where-Object { $connectors[$_].State -eq 0 } | ForEach-Object {
            if ($host_iter -ge $machines.Count) {
                $finished_connections = $true
                return
            }
            $connectors[$_].Host = $machines[$host_iter]
            $connectors[$_].Ping_Result = $($connectors[$_].Pinger.SendPingAsync($machines[$host_iter]))
            $connectors[$_].Time = $stopWatch.Elapsed
            $connectors[$_].State = 1
            if ($debug) { Write-Host "Setup pinger $_ - pinging host $($connectors[$_].Host) at $($connectors[$_].Time)"}
            $host_iter++
        }

        # check on connections
        $finished_checks = $true
        0..$($connectors.Length - 1) | Where-Object { $connectors[$_].State -eq 1} | ForEach-Object {
            if ($connectors[$_].Ping_Result.IsCompleted -ne $true) {
                $finished_checks = $false
                return
            }

            # show resolved ip address for hostnames
            $hostname = $connectors[$_].Host
            if ($hostname -notmatch "^(\d{1,3}\.){3}\d{1,3}$") {
                $hostname = "$hostname ($($connectors[$_].Ping_Result.Result.Address))"
            }

            # color different kinds of connections
            $state = $connectors[$_].Ping_Result.Result.Status
            $color = ""
            switch ($state) {
                "Success" {
                    $state = "Reachable ($($connectors[$_].Ping_Result.Result.RoundTripTime)ms)"
                    $color = "Green" 
                }
                "TimedOut" {
                    $state = "Timed Out"
                    $color = "Red" 
                }
                "DestinationHostUnreachable" {
                    $state = "Host Unreachable"
                    $color = "Red"
                }
                Default { 
                    $color = "Yellow" 
                }
            }
            
            if ($show_unreachable -or $state -match "^Reachable") {
                Write-Host "Host $hostname - $state" -ForegroundColor $color
            }
            
            # reset connector
            $connectors[$_].Host = $null
            $connectors[$_].State = 0
        }
    }
    
    # destroy connector objects
    if ($debug) { Write-Host "Destroying 100 pingers" -ForegroundColor Yellow}
    $connectors | ForEach-Object {
        $_.Pinger.Dispose()
    }
    $connectors.Clear()

    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "Scanned $($machines.Count) hosts in $([math]::Round($stopWatch.Elapsed.TotalSeconds, 2)) seconds" -ForegroundColor Cyan

    $userinput = Read-Host "Press Enter to continue or Q to quit"
    if ($userinput -match "Q") { exit }
}