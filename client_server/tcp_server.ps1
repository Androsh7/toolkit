$Host.UI.RawUI.WindowTitle = "TCP SERVER"

# resize the powershell window
$Window = $Host.UI.RawUI.WindowSize
$Window.Height = 25
$Window.Width  = 88
$Host.UI.RawUI.Set_WindowSize($Window)

Write-Host "-------------------------------------- TCP SERVER -------------------------------------" -ForegroundColor Yellow

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
    $tcp_listener = New-Object System.Net.Sockets.TcpListener($src_ip, [int32]$src_port)
    $tcp_listener.Start()
}
catch {
    Write-Host "Failed to open local endpoint on ${src_ip}:${src_port}" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    Pause
    Exit
}

Write-Host "Waiting on connection" -ForegroundColor Yellow

# blocks the script until a connection is received
$tcp_client = $tcp_listener.AcceptTcpClient()

# stop the listener to prevent additional connections
$tcp_listener.Stop()

Clear-Host
$Host.UI.RawUI.WindowTitle = "TCP SERVER CONNECTION $($tcp_client.Client.LocalEndPoint) --> $($tcp_client.Client.RemoteEndPoint)"
Write-Host "---------------------------------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "TCP SERVER CONNECTION $($tcp_client.Client.LocalEndPoint) <-- $($tcp_client.Client.RemoteEndPoint)" -ForegroundColor Yellow
Write-Host "---------------------------------------------------------------------------------------" -ForegroundColor Yellow

# create tcp stream
$tcp_stream = $tcp_client.GetStream()

# set the read variables
$read_string = ""
$read_buffer = New-Object byte[] 65536
$key_read = $true

# set the write variables
$write_string = ""
$encoding = [System.Text.Encoding]::ASCII

try {
    while ($tcp_client.Connected) {

        # checks if data is available to be printed
        if ($tcp_stream.DataAvailable) {
            if ($key_read) {
                0..$($write_string.Length) | ForEach-Object { Write-Host "`b `b" -NoNewline }
                $key_read = $false
            }

            # read the input
            $read_bytes = $tcp_stream.Read($read_buffer, 0, 1024)
            $read_string = [Text.Encoding]::ASCII.GetString($read_buffer, 0, $read_bytes)

            # write to the screen
            Write-Host "$($tcp_client.Client.RemoteEndPoint)> " -ForegroundColor Green -NoNewline
            Write-Host $read_string -NoNewline -ForegroundColor Green
            if (-not $read_string.EndsWith("`n")) {
                Write-Host ""
            }

            # clear the read buffer
            0..${read_bytes} | ForEach-Object {
                $read_buffer[$_] = [byte]0
            }
        }
        if (-not $key_read) {
            Write-Host $write_string -NoNewline
            [console]::SetCursorPosition($write_string.Length, [console]::CursorTop)
            $key_read = $true
        }
        # checks if a keyboard input has been read (NOTE: this can read multiple queued keypresses)
        while ([Console]::KeyAvailable) {
            $key_read = $true
            $key = [console]::ReadKey()
            if ($key.Key -eq "Enter") {
                # send the write_string
                $write_string = $write_string + "`n"
                $out_buffer = $encoding.GetBytes($write_string)
                $tcp_stream.Write($out_buffer, 0, $write_string.Length) 1>$null

                # write to the screen
                Write-Host "$($tcp_client.Client.LocalEndPoint)> " -ForegroundColor Cyan -NoNewline
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
    $tcp_client.Close()
    $tcp_listener.Dispose()
    $tcp_client.Dispose()

    # clear variables
    $read_string = $null
    $read_buffer = $null
}

Write-Host "---------------------------------- CONNECTION CLOSED ----------------------------------" -ForegroundColor Yellow
Write-Host "`nPress ENTER to Exit"
Read-Host