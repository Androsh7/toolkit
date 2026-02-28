$Host.UI.RawUI.WindowTitle = "Get Strings"
Write-Host "Running Get_Strings.ps1 at $(Get-Date)" -ForegroundColor Cyan

# Select input/output file
$selectedFile = Read-Host -Prompt "Input file"
$out_file = Read-Host -Prompt "Output file"

# Minimum length
$min_string_len = Read-Host "Select the minimum string length (default 3)"
if ([string]::IsNullOrWhiteSpace($min_string_len)) { $min_string_len = 3 }
$min_string_len = [int]$min_string_len
if ($min_string_len -lt 1) { $min_string_len = 3 }

$bytes = [System.IO.File]::ReadAllBytes($selectedFile)
@(
    "GetStrings.ps1 running on $(Get-Date)"
    "Parsing File: `"$selectedFile`""
    "Minimum String Length: $min_string_len"
    "------------------------------------------------------------------------------"
) | Set-Content -LiteralPath $out_file -Encoding ascii
$temp_string = ""
Write-Host "Parsing file, this may take a while..." -ForegroundColor Green
$bytes | foreach-object {
    if ($_ -ge 32 -and $_ -le 126) {
        $temp_string += [char]$_
    } else {
        if ($temp_string.Length -ge $min_string_len) {
            Out-File -InputObject $temp_string -FilePath $out_file -Append -Encoding ascii
        }
        $temp_string = ""
    }
}

Write-Host "Wrote output to $out_file" -ForegroundColor Green