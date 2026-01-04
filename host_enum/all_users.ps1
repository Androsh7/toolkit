$Host.UI.RawUI.WindowTitle = "View Current Users"
Write-Host "Running All_Users.ps1 at $(Get-Date)" -ForegroundColor Cyan
Get-WmiObject win32_Useraccount | Select-Object Domain, Name, Disabled, SID | Sort-Object Disabled -Descending | Format-Table -Wrap
Write-Host "Press ENTER to exit" -ForegroundColor Cyan
Read-Host