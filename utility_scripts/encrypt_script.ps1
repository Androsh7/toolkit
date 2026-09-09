param(
    [ValidateSet("encrypt", "decrypt")]
    [string]$Mode,
    [string]$File,
    [System.Security.SecureString]$Password,
    [string]$Salt = "qtsbp6j643ah8e0omygzwlv9u75xcfrk4j63fdane78w1zgxhucsytkirol0v25q",
    [string]$OutFile
)

Clear-Host
$Host.UI.RawUI.WindowTitle = "Encrypt/Decrypt File"
Write-Host "Running encrypt_script.ps1 at $(Get-Date)" -ForegroundColor Cyan

# Prompt for any missing arguments
if ([string]::IsNullOrWhiteSpace($Mode)) {
    $Mode = Read-Host -Prompt "Mode (encrypt/decrypt)"
}
$Mode = $Mode.ToLower()
if ($Mode -ne "encrypt" -and $Mode -ne "decrypt") {
    Write-Host "ERROR: Mode must be 'encrypt' or 'decrypt'" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($File)) {
    $File = Read-Host -Prompt "File path"
}
if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
    Write-Host "ERROR: Failed to parse path: `"${File}`"" -ForegroundColor Red
    exit 1
}

if ($null -eq $Password -or $Password.Length -eq 0) {
    $Password = Read-Host -Prompt "Password" -AsSecureString
}

# Derive a 256-bit key from the password and salt.
$saltBytes = [System.Text.Encoding]::UTF8.GetBytes($Salt)
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
try {
    $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    $passBytes = [System.Text.Encoding]::UTF8.GetBytes($plainPass)
    $keyDerive = New-Object Security.Cryptography.Rfc2898DeriveBytes($passBytes, $saltBytes, 1000, 'SHA256')
    $keyBytes = $keyDerive.GetBytes(32) # 256-bit key
}
finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    if ($null -ne $passBytes) { [Array]::Clear($passBytes, 0, $passBytes.Length) }
    $plainPass = $null
}

if ($Mode -eq "encrypt") {
    # Default output: append .encrypt to the input file name
    if ([string]::IsNullOrWhiteSpace($OutFile)) {
        $OutFile = "$File.encrypt"
    }

    $plainBytes = [System.IO.File]::ReadAllBytes($File)

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $keyBytes
    $aes.GenerateIV()
    $encryptor = $aes.CreateEncryptor()
    $encryptedBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)

    # Prepend the IV so it can be recovered at decryption time
    $ivAndEnc = $aes.IV + $encryptedBytes
    [System.IO.File]::WriteAllBytes($OutFile, $ivAndEnc)

    Write-Host "Encrypted `"$File`" -> `"$OutFile`"" -ForegroundColor Green
}
else {
    # Default output: strip the trailing .encrypt from the input file name
    if ([string]::IsNullOrWhiteSpace($OutFile)) {
        if ($File.ToLower().EndsWith(".encrypt")) {
            $OutFile = $File.Substring(0, $File.Length - ".encrypt".Length)
        } else {
            $OutFile = "$File.decrypt"
        }
    }

    $cipherBytes = [System.IO.File]::ReadAllBytes($File)
    if ($cipherBytes.Length -le 16) {
        Write-Host "ERROR: File is too small to contain an IV and ciphertext" -ForegroundColor Red
        exit 1
    }

    $decryptAes = [System.Security.Cryptography.Aes]::Create()
    $decryptAes.Key = $keyBytes
    $decryptAes.IV = $cipherBytes[0..15] # First 16 bytes are the IV
    $decryptor = $decryptAes.CreateDecryptor()
    try {
        $decryptedBytes = $decryptor.TransformFinalBlock($cipherBytes, 16, $cipherBytes.Length - 16)
    }
    catch {
        Write-Host "ERROR: Decryption failed (wrong password/salt or corrupted file)" -ForegroundColor Red
        exit 1
    }
    [System.IO.File]::WriteAllBytes($OutFile, $decryptedBytes)

    Write-Host "Decrypted `"$File`" -> `"$OutFile`"" -ForegroundColor Green
}
