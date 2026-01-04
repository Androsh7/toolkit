$Host.UI.RawUI.WindowTitle = "UDP SERVER"

# resize the powershell window
$Window = $Host.UI.RawUI.WindowSize
$Window.Height = 25
$Window.Width  = 88
$Host.UI.RawUI.Set_WindowSize($Window)

Write-Host "-------------------------------------- UDP SERVER -------------------------------------" -ForegroundColor Yellow

# determine if listener should be open to the network or only on loopback
$scope = Read-Host -Prompt "Local (127.0.0.1) or Remote (0.0.0.0)? L/R"
if ($scope -contains "L" -or $scope -contains "Local") {
    Write-Host "Setting up listener on loopback (127.0.0.1)" -ForegroundColor Cyan
    $src_ip = [ipaddress]"127.0.0.1"
} elseif ($scope -contains "R" -or $scope -contains "Remote") {
    Write-Host "Setting up network-facing listener (0.0.0.0)" -ForegroundColor Cyan
    $src_ip = [ipaddress]"0.0.0.0"
} else {
    Write-Host "Invalid input, defaulting to setting up listener on loopback (127.0.0.1)" -ForegroundColor Red
    $src_ip = [ipaddress]"127.0.0.1"
}

[int32]$src_port = Read-Host -Prompt "Destination Port"

# attempt to connect
try {
    Write-Host "Opening local endpoint on ${src_ip}:${src_port}" -ForegroundColor Cyan
    $group_endpoint = New-Object System.Net.IPEndPoint($src_ip, $src_port)
    $udp_client = New-Object System.Net.Sockets.UdpClient($group_endpoint)
}
catch {
    Write-Host "Failed to open local endpoint on ${src_ip}:${src_port}" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    Pause
    Exit
}

Clear-Host
$Host.UI.RawUI.WindowTitle = "UDP SERVER ON $($udp_client.Client.LocalEndPoint)"
Write-Host "---------------------------------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "UDP SERVER ON $($udp_client.Client.LocalEndPoint)" -ForegroundColor Yellow
Write-Host "---------------------------------------------------------------------------------------" -ForegroundColor Yellow

# set the read variables
$async_receive = $udp_client.ReceiveAsync()
$read_string = ""
$key_read = $true

# set the write variables
$write_string = ""
$remote_endpoint = $null
$encoding = [System.Text.Encoding]::ASCII

try {
    while ($true) {

        # checks if data is available to be printed
        if ($async_receive.IsCompleted) {
            if ($key_read) {
                0..$($write_string.Length) | ForEach-Object { Write-Host "`b `b" -NoNewline }
                $key_read = $false
            }

            # read the input
            $read_bytes = $async_receive.Result.Buffer.Length
            $read_buffer = $async_receive.Result.Buffer
            $remote_endpoint = $async_receive.Result.RemoteEndPoint
            $read_string = [Text.Encoding]::ASCII.GetString($read_buffer, 0, $read_bytes)

            # write to the screen
            Write-Host "${remote_endpoint}> " -ForegroundColor Green -NoNewline
            Write-Host $read_string -NoNewline -ForegroundColor Green
            if (-not $read_string.EndsWith("`n")) {
                Write-Host ""
            }

            # create a new async receive object
            $async_receive = $udp_client.ReceiveAsync()
        }
        if (-not $key_read) {
            Write-Host $write_string -NoNewline
            [console]::SetCursorPosition($write_string.Length, [console]::CursorTop)
            $key_read = $true
        }
        # checks if a keyboard input has been read (NOTE: this can read multiple queued key presses)
        while ([Console]::KeyAvailable) {
            $key_read = $true
            $key = [console]::ReadKey()
            if ($key.Key -eq "Enter") {
                # send the write_string
                $write_string = $write_string + "`n"
                $out_buffer = $encoding.GetBytes($write_string)

                # exception handling for closed connections
                try {
                    $udp_client.Send($out_buffer, $remote_endpoint) 1>$null
                }
                catch {
                    Write-Host "Failed to write to remote endpoint: $remote_endpoint $_" -ForegroundColor Red
                    if ($udp_client.Active -ne $true) {
                        Write-Host "The connection was closed by the remote host" -ForegroundColor Red
                    }    
                    break
                }

                # write to the screen
                Write-Host "$($udp_client.Client.LocalEndPoint) to $remote_endpoint> " -ForegroundColor Cyan -NoNewline
                Write-Host "$($write_string.Remove($write_string.Length - 1))" -ForegroundColor Cyan

                # clears the write_string
                $write_string = "" 
                break
            } elseif ($key.Key -eq "Backspace") {
                Write-Host " `b" -NoNewline
                if ($write_string.Length -ne 0) {
                    $write_string = $write_string.Remove($write_string.Length - 1)
                }
            } elseif ($key.Key -eq "Escape") {
                # this is a placeholder that will be used to cancel the input
            } else {
                $write_string += $key.KeyChar
            }
        }
    }
} finally {
    # shutdown the listener and client
    $udp_client.Close()
    $udp_client.Dispose()

    # clear variables
    $remote_endpoint = $null
    $read_string = $null
    $read_buffer = $null
}

Write-Host "---------------------------------- CONNECTION CLOSED ----------------------------------" -ForegroundColor Yellow
Write-Host "`nPress ENTER to Exit"
Read-Host