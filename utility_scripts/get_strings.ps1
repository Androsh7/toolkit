Add-Type -AssemblyName System.Windows.Forms

$Host.UI.RawUI.WindowTitle = "Get Strings"

Write-Host "Running Get_Strings.ps1 at $(Get-Date)"-ForegroundColor Cyan

$out_file = "${env:TEMP}\Strings.txt"

# opens a prompt to select a file
Write-Host "Please select a file"
$OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$OpenFileDialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')
$OpenFileDialog.Filter = "All files (*.*)|*.*"
$OpenFileDialog.Multiselect = $false

if ($OpenFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $selectedFile = $OpenFileDialog.FileName
    Write-Host "Selected file: $selectedFile" -ForegroundColor Cyan
} else {
    Write-Host "No file selected." -ForegroundColor Red
    Exit
}

# prompts the user to select the minimum string length
[int]$min_string_len = Read-Host "Select the minimum string length (default 3)"
if ($null -eq $min_string_len) { $min_string_len = 3 }

# tests to ensure the file exists
if (Test-Path $selectedFile) {
    Write-Host "File is accessible, proceeding to parse for strings" -ForegroundColor Green
    $Host.UI.RawUI.WindowTitle = "GetStrings - $selectedFile"
} else {
    Write-Host "File is inaccessible, verify you have permissions to read this file" -ForegroundColor Red
    Read-Host "`nPress ENTER to exit"
    Exit
}

# add output file headers
"GetStrings.ps1 running on $(Get-Date)" > $out_file
"Parsing File: `"$selectedFile`"" >> $out_file
"Minimum String Length: $min_string_len" >> $out_file
"This file is saved in $out_file" >> $out_file
"------------------------------------------------------------------------------" >> $out_file

[System.IO.File]::ReadAllLines($selectedFile) |
    ForEach-Object {
        [regex]::Matches($_, "[\x20-\x7E]{${min_string_len},}") |
            ForEach-Object { $_.Value }
    } |
    Tee-Object -FilePath $out_file -Append

Start-Process -FilePath "Notepad.exe" -ArgumentList $out_file