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

# Walk through streams
$streams | ForEach-Object {
    if ($_.Stream -ne ':$DATA') {
        $user_input = Read-Host -Prompt "Delete stream `"$($_.Stream)`" - Length $($_.Length) (Y/n)"
        if ($user_input -eq "Y") {
            Remove-Item -Path $file_path -Stream $_.Stream
            Write-Host "Deleted data stream `"$($_.Stream)`"" -ForegroundColor Yellow
        }
    }
}

# Get the updated stream count
$stream_count = (Get-Item -Path $file_path -Stream * | Measure-Object).Count

# Print remaining streams
if ($stream_count -gt 1) {
    Write-Host "WARNING: File has $($stream_count - 1) alternative data streams" -ForegroundColor Yellow
} else {
    Write-Host "File has no alternative data streams" -ForegroundColor Green
}