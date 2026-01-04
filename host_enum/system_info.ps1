$Host.UI.RawUI.WindowTitle = "Systeminfo"
Write-Host "Running Systeminfo.ps1 at $(Get-Date)" -NoNewline -ForegroundColor Cyan
"Systeminfo $(Get-Date)" > $env:TEMP\Systeminfo.txt
"Runas ${env:USERNAME} on ${env:COMPUTERNAME}" >> $env:TEMP\Systeminfo.txt
"Path $env:TEMP\Systeminfo.txt" >> $env:TEMP\Systeminfo.txt
systeminfo.exe >> $env:TEMP\SystemInfo.txt
Start-Process -FilePath "Notepad.exe" -ArgumentList "$env:TEMP\Systeminfo.txt"