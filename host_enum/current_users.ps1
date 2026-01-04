$Host.UI.RawUI.WindowTitle = "View Current Users"

# Verify user has administrator permissions (only when running in Powershell version 5.1)
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -and $host.Version.Major -lt 7) {
    Write-Host "This script needs to be run as an Administrator." -ForegroundColor Red
    try {
        Start-Process -FilePath "conhost.exe" -ArgumentList "powershell.exe -executionpolicy Bypass -File ${PSScriptRoot}/Current_Users.ps1" -Verb runas
    }
    catch {
        Write-Host "Failed to run this program as administrator" -ForegroundColor Red
        Write-Host "`nPress ENTER to exit" -ForegroundColor Red
        Read-Host
    }
    Exit
}

Clear-Host
$prev_lines = 0
while ($true) {
    Write-Host "------------------------------ Current Users ------------------------------" -ForegroundColor Cyan
    $sorted_processes = Get-Process -IncludeUserName | sort-object Username, StartTime -ErrorAction SilentlyContinue
    $users = @()
    $sorted_processes | Where-Object { $_.Username -notin $users.Username } | ForEach-Object {
        $users += $_
    }
    $users_formatted = @()
    $Current_Date = $(Get-Date)
    $users | ForEach-Object {
        $user_formatted = New-Object -TypeName psobject
        $user_formatted | Add-Member -MemberType NoteProperty -Name "SessionId" -Value $_.SessionId
        $user_formatted | Add-Member -MemberType NoteProperty -Name "Username" -Value $_.Username
        $date_span = New-TimeSpan -Start $_.StartTime -End $Current_Date
        $date_span = "$($date_span.Days)d $($date_span.Hours)h $($date_span.Minutes)m $($date_span.Seconds)s      "
        $user_formatted | Add-Member -MemberType NoteProperty -Name "Uptime" -Value $date_span
        $user_formatted | Add-Member -MemberType NoteProperty -Name "Process" -Value $_.Name
        $user_formatted | Add-Member -MemberType NoteProperty -Name "PID" -Value $_.ID
        $users_formatted += $user_formatted
    }
    $users_formatted | Sort-Object -Property SessionId, Username -Descending | Select-Object SessionId, Username, Process, PID, Uptime | Format-Table
    $current_lines = ($users_formatted | Measure-Object).Count
    if ($current_lines -lt $prev_lines) {
        0..$($prev_lines - $current_lines) | ForEach-Object {
            Write-Host ""
        }
    }
    $prev_lines = $current_lines
    [console]::SetCursorPosition(0,0)
    Start-Sleep 1
}
Read-Host