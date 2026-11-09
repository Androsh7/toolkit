$buckets = New-Object System.Collections.Generic.List[byte[]]
$chunk_size_bytes = 64MB
while ($true) {
    $bucket = [byte[]]::new($chunk_size_bytes)
    # touch one byte per page so the allocation becomes resident memory
    for ($offset = 0; $offset -lt $chunk_size_bytes; $offset += 4096) { $bucket[$offset] = 1 }
    $buckets.Add($bucket)
}
