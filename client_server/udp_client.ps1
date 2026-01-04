$Host.UI.RawUI.WindowTitle = "UDP CLIENT"

# resize the powershell window
$Window = $Host.UI.RawUI.WindowSize
$Window.Height = 25
$Window.Width  = 88
$Host.UI.RawUI.Set_WindowSize($Window)

Write-Host "-------------------------------------- UDP CLIENT -------------------------------------" -ForegroundColor Yellow
$dst_ip = Read-Host -Prompt "Destination IP Address"
[int32]$dst_port = Read-Host -Prompt "Destination Port"

# Build the udp_client object
$udp_client = New-Object System.Net.Sockets.UdpClient

# attempt to connect
try {
    Write-Host "Attempting to connect to ${dst_ip}:${dst_port}" -ForegroundColor Cyan
    $udp_client.Connect($dst_ip, $dst_port)
}
catch {
    Write-Host "Failed to connect to ${dst_ip}:${dst_port}" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    Pause
    Exit
}
Clear-Host
$Host.UI.RawUI.WindowTitle = "UDP CLIENT CONNECTION $($udp_client.Client.LocalEndPoint) --> $($udp_client.Client.RemoteEndPoint)"
Write-Host "---------------------------------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "UDP CLIENT CONNECTION $($udp_client.Client.LocalEndPoint) --> $($udp_client.Client.RemoteEndPoint)" -ForegroundColor Yellow
Write-Host "---------------------------------------------------------------------------------------" -ForegroundColor Yellow

# set the read variables
$async_receive = $udp_client.ReceiveAsync()
$read_string = ""
$key_read = $true

# set the write variables
$write_string = ""
$encoding = [System.Text.Encoding]::ASCII

while ($udp_client.Client.Connected) {

    # checks if data is available to be printed
    if ($async_receive.IsCompleted) {
        if ($key_read) {
            0..$($write_string.Length) | ForEach-Object { Write-Host "`b `b" -NoNewline }
            $key_read = $false
        }

        # read the input
        $read_bytes = $async_receive.Result.Buffer.Length
        $read_buffer = $async_receive.Result.Buffer
        $read_string = [Text.Encoding]::ASCII.GetString($read_buffer, 0, $read_bytes)

        # write to the screen
        Write-Host "$($udp_client.Client.RemoteEndPoint)> " -ForegroundColor Green -NoNewline
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
                $udp_client.Send($out_buffer) 1>$null
            }
            catch {
                Write-Host "Failed to write to remote endpoint: $($udp_client.Client.RemoteEndPoint) $_" -ForegroundColor Red
                if ($udp_client.Active -ne $true) {
                    Write-Host "The connection was closed by the remote host" -ForegroundColor Red
                }    
                break
            }
            

            # write to the screen
            Write-Host "$($udp_client.Client.LocalEndPoint)> " -ForegroundColor Cyan -NoNewline
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

Write-Host "---------------------------------- CONNECTION CLOSED ----------------------------------" -ForegroundColor Yellow
Write-Host "`nPress ENTER to Exit"
Read-Host