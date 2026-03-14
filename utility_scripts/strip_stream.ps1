$Host.UI.RawUI.WindowTitle = "Strip streams"

# Get file path input
$file_path = Read-Host -Prompt "File path"
try {
    $streams = Get-Item -Path $file_path -Stream * -ErrorAction Stop
}
catch {
    Write-Host "ERROR: Failed to parse path: `"${file_path}`"" -ForegroundColor Red
    exit 1
}

$has_data_stream = $false

# Walk through streams
$streams | ForEach-Object {
    if ($_.Stream -ne ':$DATA') {
        $user_input = Read-Host -Prompt "Delete stream `"$($_.Stream)`" - Length $($_.Length) (Y/n)"
        if ($user_input -eq "Y") {
            Remove-Item -Path $file_path -Stream $_.Stream
            Write-Host "Deleted data stream `"$($_.Stream)`"" -ForegroundColor Yellow
        }
    } else {
        $has_data_stream = $true
    }
}
$stream_count = ($streams | Measure-Object).Count

# Print status
if (-not $has_data_stream) {
    Write-Host 'WARNING: File contains no :$DATA stream' -ForegroundColor Yellow
}
if ($stream_count - 1 + [int]$has_data_stream -gt 1) {
    Write-Host "WARNING: File has $($stream_count - [int]$has_data_stream) alternative data streams" -ForegroundColor Yellow
}
if ($has_data_stream -and $stream_count -eq 1) {
    Write-Host "File has no alternative data streams" -ForegroundColor Green
}