param(
    [Alias('l')][switch]$Listen,
    [Alias('u')][switch]$Udp,
    [Parameter(Position = 0)][string]$HostAddress,
    [Parameter(Position = 1)][Alias('p')][int]$Port,
    [Alias('s')][string]$SendFile,
    [Alias('o')][string]$OutFile,
    [switch]$Log,
    [string]$LogFile
)

Clear-Host

if (-not $PSBoundParameters.ContainsKey('Udp')) {
    $ans = Read-Host -Prompt "Protocol - (T)CP or (U)DP? [default TCP]"
    if ($ans -match '^(U|UDP)$') { $Udp = $true }
}
if (-not $PSBoundParameters.ContainsKey('Listen')) {
    $ans = Read-Host -Prompt "Mode - (C)onnect or (L)isten? [default Connect]"
    if ($ans -match '^(L|Listen)$') { $Listen = $true }
}

$proto = if ($Udp) { "UDP" } else { "TCP" }
$role  = if ($Listen) { "LISTENER" } else { "CLIENT" }

$Host.UI.RawUI.WindowTitle = "NETPS1 $proto $role"

# resize the powershell window (ignored on hosts that don't support it)
try {
    $Window = $Host.UI.RawUI.WindowSize
    $Window.Height = 25
    $Window.Width  = 88
    $Host.UI.RawUI.Set_WindowSize($Window)
} catch { }

Write-Host "------------------------------------ NETPS1 $proto $role ------------------------------------" -ForegroundColor Yellow

# --------------------------------------------------------------------------------------
# Optional session transcript logging (set up early so connection events are captured)
# --------------------------------------------------------------------------------------
if (-not $PSBoundParameters.ContainsKey('Log') -and -not $PSBoundParameters.ContainsKey('LogFile')) {
    $ans = Read-Host -Prompt "Save session transcript to results? (y/N)"
    if ($ans -match '^(Y|Yes)$') { $Log = $true }
}
$script:log_writer = $null
if ($Log -or $LogFile) {
    $base_dir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $results_dir = Join-Path $base_dir 'results'
    if (-not (Test-Path -LiteralPath $results_dir)) {
        New-Item -ItemType Directory -Path $results_dir -Force | Out-Null
    }
    if ([string]::IsNullOrWhiteSpace($LogFile)) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $LogFile = Join-Path $results_dir ("netps1_{0}_{1}_{2}.log" -f $proto.ToLower(), $role.ToLower(), $stamp)
    }
    try {
        $script:log_writer = New-Object System.IO.StreamWriter($LogFile, $true)  # append
        Write-Host "Logging session transcript to $LogFile" -ForegroundColor DarkGray
    } catch {
        Write-Host "WARNING: could not open log file ${LogFile}: $_" -ForegroundColor Red
    }
}

function Write-Log {
    param([string]$Text)
    if ($script:log_writer) {
        $script:log_writer.WriteLine("[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $Text)
        $script:log_writer.Flush()
    }
}

# --------------------------------------------------------------------------------------
# Resolve connection details (prompt for anything not supplied on the command line)
# --------------------------------------------------------------------------------------
if ($Listen) {
    if ([string]::IsNullOrWhiteSpace($HostAddress)) {
        $scope = Read-Host -Prompt "Local (127.0.0.1) or Remote (0.0.0.0)? L/R"
        if ($scope -match '^(L|Local)$') {
            Write-Host "Setting up listener on loopback (127.0.0.1)" -ForegroundColor Cyan
            $bind_ip = [ipaddress]"127.0.0.1"
        } elseif ($scope -match '^(R|Remote)$') {
            Write-Host "Setting up network-facing listener (0.0.0.0)" -ForegroundColor Cyan
            $bind_ip = [ipaddress]"0.0.0.0"
        } else {
            Write-Host "Invalid input, defaulting to loopback (127.0.0.1)" -ForegroundColor Red
            $bind_ip = [ipaddress]"127.0.0.1"
        }
    } else {
        $bind_ip = [ipaddress]$HostAddress
    }
} else {
    if ([string]::IsNullOrWhiteSpace($HostAddress)) {
        $HostAddress = Read-Host -Prompt "Destination IP Address"
    }
}

if (-not $Port) {
    $prompt = if ($Listen) { "Listen Port" } else { "Destination Port" }
    [int32]$Port = Read-Host -Prompt $prompt
}

if (-not $PSBoundParameters.ContainsKey('SendFile')) {
    $SendFile = Read-Host -Prompt "File to send after connecting (blank for none)"
}
if (-not $PSBoundParameters.ContainsKey('OutFile')) {
    $OutFile = Read-Host -Prompt "File to save received bytes to (blank for none)"
}

# --------------------------------------------------------------------------------------
# Establish the connection. Each branch populates the shared $script:* transport state
# and the unified chat loop below drives it through the transport helper functions.
# --------------------------------------------------------------------------------------
$script:sock         = $null
$script:tcp_stream   = $null
$script:udp          = $null
$script:async        = $null
$script:udp_remote   = $null   # UDP listener learns this from the first datagram
$script:listener     = $null
$script:recv_raw     = $null   # raw bytes from the most recent read (for -OutFile)
$script:out_stream   = $null

try {
    if (-not $Udp -and -not $Listen) {
        # ---- TCP connect ----
        Write-Host "Attempting to connect to ${HostAddress}:${Port}" -ForegroundColor Cyan
        $script:sock = New-Object System.Net.Sockets.TcpClient
        $script:sock.Connect($HostAddress, $Port)
        $script:tcp_stream = $script:sock.GetStream()
    }
    elseif (-not $Udp -and $Listen) {
        # ---- TCP listen ----
        Write-Host "Opening local endpoint on ${bind_ip}:${Port}" -ForegroundColor Cyan
        $script:listener = New-Object System.Net.Sockets.TcpListener($bind_ip, [int32]$Port)
        $script:listener.Start()
        Write-Host "Waiting on connection" -ForegroundColor Yellow
        $script:sock = $script:listener.AcceptTcpClient()   # blocks until a client connects
        $script:listener.Stop()                             # refuse additional connections
        $script:tcp_stream = $script:sock.GetStream()
    }
    elseif ($Udp -and -not $Listen) {
        # ---- UDP connect ----
        Write-Host "Setting up UDP endpoint to ${HostAddress}:${Port}" -ForegroundColor Cyan
        $script:udp = New-Object System.Net.Sockets.UdpClient
        $script:udp.Connect($HostAddress, $Port)
        $script:async = $script:udp.ReceiveAsync()
    }
    else {
        # ---- UDP listen ----
        Write-Host "Opening local endpoint on ${bind_ip}:${Port}" -ForegroundColor Cyan
        $group_endpoint = New-Object System.Net.IPEndPoint($bind_ip, $Port)
        $script:udp = New-Object System.Net.Sockets.UdpClient($group_endpoint)
        $script:async = $script:udp.ReceiveAsync()
    }
}
catch {
    Write-Host "Failed to establish $proto $role" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    Write-Log "FAILED to establish $proto $role : $_"
    if ($script:log_writer) { $script:log_writer.Dispose() }
    Pause
    Exit
}

# --------------------------------------------------------------------------------------
# Transport helpers used by the shared chat loop
# --------------------------------------------------------------------------------------
function Get-LocalLabel {
    if ($Udp) { return $script:udp.Client.LocalEndPoint }
    else      { return $script:sock.Client.LocalEndPoint }
}
function Get-RemoteLabel {
    if ($Udp) {
        if ($Listen) { return $script:udp_remote }
        else         { return $script:udp.Client.RemoteEndPoint }
    }
    else { return $script:sock.Client.RemoteEndPoint }
}
function Test-Connected {
    # UDP is connectionless; keep looping until the window is closed / remote quits
    if ($Udp) { return $true }
    return $script:sock.Connected
}
function Test-DataAvailable {
    if ($Udp) { return $script:async.IsCompleted }
    return $script:tcp_stream.DataAvailable
}
function Read-Incoming {
    # Sets $script:recv_raw to the exact bytes received and returns the ASCII text.
    if ($Udp) {
        $result = $script:async.Result
        $script:udp_remote = $result.RemoteEndPoint    # remember sender (needed for UDP listen replies)
        $script:recv_raw = $result.Buffer
        $script:async = $script:udp.ReceiveAsync()      # queue the next datagram
        return [Text.Encoding]::ASCII.GetString($result.Buffer, 0, $result.Buffer.Length)
    }
    else {
        $read_buffer = New-Object byte[] 65536
        $read_bytes = $script:tcp_stream.Read($read_buffer, 0, 65536)
        $script:recv_raw = New-Object byte[] $read_bytes
        [Array]::Copy($read_buffer, 0, $script:recv_raw, 0, $read_bytes)
        return [Text.Encoding]::ASCII.GetString($read_buffer, 0, $read_bytes)
    }
}
function Send-Outgoing {
    param([byte[]]$Bytes)
    if ($Udp) {
        if ($Listen) {
            if ($null -eq $script:udp_remote) {
                Write-Host "No client has contacted this listener yet - nothing to reply to" -ForegroundColor Red
                return
            }
            $script:udp.Send($Bytes, $Bytes.Length, $script:udp_remote) 1>$null
        }
        else {
            $script:udp.Send($Bytes, $Bytes.Length) 1>$null
        }
    }
    else {
        $script:tcp_stream.Write($Bytes, 0, $Bytes.Length) 1>$null
    }
}

# --------------------------------------------------------------------------------------
# Connection banner
# --------------------------------------------------------------------------------------
Clear-Host
$title = if ($Udp -and $Listen) {
    "NETPS1 $proto $role ON $(Get-LocalLabel)"
} else {
    "NETPS1 $proto $role CONNECTION $(Get-LocalLabel) --> $(Get-RemoteLabel)"
}
$Host.UI.RawUI.WindowTitle = $title
Write-Host "---------------------------------------------------------------------------------------" -ForegroundColor Yellow
Write-Host $title -ForegroundColor Yellow
Write-Host "---------------------------------------------------------------------------------------" -ForegroundColor Yellow
Write-Log $title

# --------------------------------------------------------------------------------------
# Open the raw output file (received bytes) now that the connection succeeded
# --------------------------------------------------------------------------------------
if ($OutFile) {
    try {
        $script:out_stream = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        Write-Host "Writing received bytes to $OutFile" -ForegroundColor DarkGray
        Write-Log "Writing received bytes to $OutFile"
    } catch {
        Write-Host "WARNING: could not open output file ${OutFile}: $_" -ForegroundColor Red
    }
}

# --------------------------------------------------------------------------------------
# Optionally push a file's raw bytes over the connection before entering the chat loop
# --------------------------------------------------------------------------------------
if ($SendFile) {
    if (-not (Test-Path -LiteralPath $SendFile -PathType Leaf)) {
        Write-Host "ERROR: file to send not found: $SendFile" -ForegroundColor Red
        Write-Log "ERROR: file to send not found: $SendFile"
    } else {
        try {
            $file_bytes = [System.IO.File]::ReadAllBytes($SendFile)
            if ($Udp) {
                # keep datagrams under the practical UDP payload ceiling
                $chunk = 60000
                for ($off = 0; $off -lt $file_bytes.Length; $off += $chunk) {
                    $len = [Math]::Min($chunk, $file_bytes.Length - $off)
                    $seg = New-Object byte[] $len
                    [Array]::Copy($file_bytes, $off, $seg, 0, $len)
                    Send-Outgoing -Bytes $seg
                }
            } else {
                Send-Outgoing -Bytes $file_bytes
            }
            Write-Host "Sent file $SendFile ($($file_bytes.Length) bytes)" -ForegroundColor Cyan
            Write-Log "SENT FILE $SendFile ($($file_bytes.Length) bytes)"
        } catch {
            Write-Host "Failed to send file: $_" -ForegroundColor Red
            Write-Log "FAILED to send file ${SendFile}: $_"
        }
    }
}

# --------------------------------------------------------------------------------------
# Unified interactive chat loop
# --------------------------------------------------------------------------------------
$write_string = ""
$key_read = $true
$encoding = [System.Text.Encoding]::ASCII

try {
    while (Test-Connected) {

        # checks if data is available to be printed
        if (Test-DataAvailable) {
            if ($key_read) {
                0..$($write_string.Length) | ForEach-Object { Write-Host "`b `b" -NoNewline }
                $key_read = $false
            }

            $read_string = Read-Incoming

            # persist the raw received bytes if an output file is set
            if ($script:out_stream -and $script:recv_raw -and $script:recv_raw.Length -gt 0) {
                $script:out_stream.Write($script:recv_raw, 0, $script:recv_raw.Length)
                $script:out_stream.Flush()
            }

            # write to the screen
            Write-Host "$(Get-RemoteLabel)> " -ForegroundColor Green -NoNewline
            Write-Host $read_string -NoNewline -ForegroundColor Green
            if (-not $read_string.EndsWith("`n")) {
                Write-Host ""
            }
            Write-Log ("$(Get-RemoteLabel)> " + $read_string.TrimEnd("`r", "`n"))
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
                    Send-Outgoing -Bytes $out_buffer
                }
                catch {
                    Write-Host "Failed to write to remote endpoint: $(Get-RemoteLabel)" -ForegroundColor Red
                    if (-not (Test-Connected)) {
                        Write-Host "The connection was closed by the remote host" -ForegroundColor Red
                    }
                    Write-Log "FAILED to write to $(Get-RemoteLabel)"
                    break
                }

                # write to the screen
                Write-Host "$(Get-LocalLabel)> " -ForegroundColor Cyan -NoNewline
                Write-Host "$($write_string.Remove($write_string.Length - 1))" -ForegroundColor Cyan
                Write-Log ("$(Get-LocalLabel)> " + $write_string.Remove($write_string.Length - 1))

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
}
finally {
    Write-Log "CONNECTION CLOSED"

    # flush and close the received-bytes file
    if ($script:out_stream) { $script:out_stream.Flush(); $script:out_stream.Dispose() }

    # shutdown the socket(s)
    if ($script:tcp_stream) { $script:tcp_stream.Dispose() }
    if ($script:sock)       { $script:sock.Close(); $script:sock.Dispose() }
    if ($script:listener)   { $script:listener.Stop() }
    if ($script:udp)        { $script:udp.Close(); $script:udp.Dispose() }

    # close the transcript log
    if ($script:log_writer) { $script:log_writer.Flush(); $script:log_writer.Dispose() }
}

Write-Host "---------------------------------- CONNECTION CLOSED ----------------------------------" -ForegroundColor Yellow
Write-Host "`nPress ENTER to Exit"
Read-Host
