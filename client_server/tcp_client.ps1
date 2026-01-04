$Host.UI.RawUI.WindowTitle = "TCP CLIENT"

# resize the powershell window
$Window = $Host.UI.RawUI.WindowSize
$Window.Height = 25
$Window.Width  = 88
$Host.UI.RawUI.Set_WindowSize($Window)

Write-Host "-------------------------------------- TCP CLIENT -------------------------------------" -ForegroundColor Yellow
$dst_ip = Read-Host -Prompt "Destination IP Address"
[int32]$dst_port = Read-Host -Prompt "Destination Port"

# Build the tcp_client object
$tcp_client = New-Object System.Net.Sockets.TcpClient

# attempt to connect
try {
    Write-Host "Attempting to connect to ${dst_ip}:${dst_port}" -ForegroundColor Cyan
    $tcp_client.Connect($dst_ip, $dst_port)
}
catch {
    Write-Host "Failed to connect to ${dst_ip}:${dst_port}" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    Pause
    Exit
}
Clear-Host
$Host.UI.RawUI.WindowTitle = "TCP CLIENT CONNECTION $($tcp_client.Client.LocalEndPoint) --> $($tcp_client.Client.RemoteEndPoint)"
Write-Host "---------------------------------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "TCP CLIENT CONNECTION $($tcp_client.Client.LocalEndPoint) --> $($tcp_client.Client.RemoteEndPoint)" -ForegroundColor Yellow
Write-Host "---------------------------------------------------------------------------------------" -ForegroundColor Yellow

# grab stream reader
$tcp_stream = $tcp_client.GetStream()

# set the read variables
$read_string = ""
$read_buffer = New-Object byte[] 65536
$key_read = $true

# set the write variables
$write_string = ""
$encoding = [System.Text.Encoding]::ASCII

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

            # exception handling for closed connections
            try {
                $tcp_stream.Write($out_buffer, 0, $write_string.Length) 1>$null
            }
            catch {
                Write-Host "Failed to write to remote endpoint: $($tcp_client.Client.RemoteEndPoint)" -ForegroundColor Red
                if ($tcp_client.Connected -ne $true) {
                    Write-Host "The connection was closed by the remote host" -ForegroundColor Red
                }    
                break
            }
            

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

Write-Host "---------------------------------- CONNECTION CLOSED ----------------------------------" -ForegroundColor Yellow
Write-Host "`nPress ENTER to Exit"
Read-Host