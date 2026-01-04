$Host.UI.RawUI.WindowTitle = "Active Directory Lookup"
function Enter_to_Exit {
    Read-Host "Press Enter to exit"
    Exit
}

$mode = (Read-Host "Mode (User, Group, Computer)").toLower()

# Check for valid mode
if (-not $mode -or ($mode -ne "user" -and $mode -ne "group" -and $mode -ne "computer")) {
    Write-Host "ERROR - Invalid mode. Please specify User, Group, or Computer." -ForegroundColor Red
    Enter_to_Exit
}

Write-Host "----- Active Directory $($mode.ToUpper()) Lookup -----" -ForegroundColor Cyan

# Check if Active Directory module is installed
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host "ERROR - The Active Directory module is not installed. Please install it before running this script." -ForegroundColor Red
    Enter_to_Exit
    exit
}
Write-Host "Current Domain: ${$(Get-ADDomain).DNSRoot}`n"

Write-Host "Lookup Information (leave blank to skip):" -ForegroundColor Cyan
if ($mode = "User") {
    $Username = Read-Host -Prompt "Enter Username to lookup"
    if (-not $Username) { $Username = "*" }
    $First_Name = Read-Host -Prompt "Enter First Name"
    if (-not $First_Name) { $First_Name = "*" }
    $Last_Name = Read-Host -Prompt "Enter Last Name"
    if (-not $Last_Name) { $Last_Name = "*" }
    $Middle_Initial = Read-Host -Prompt "Enter Middle Initial"
    if (-not $Middle_Initial) { $Middle_Initial = "*" }
} elseif ($mode = "Group") {
    $Username = Read-Host -Prompt "Enter Username to lookup"
    if (-not $Username) { $Username = "*" }
} elseif ($mode = "Computer") {
    $Computer = Read-Host -Prompt "Enter Computer to lookup"
    if (-not $Computer) { $Computer = "*" }
}

Write-Host ""

Write-Host "Known Domains:" -ForegroundColor Cyan
$domains = Get-Content -Path "domains.txt" | Where-Object { $_ -notmatch "^#" }
$domains | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }

$lookup_domain = Read-Host -Prompt "Enter search domain (blank for all):"
Write-Host "`nSearching for ${mode}:" -ForegroundColor Cyan
if (-not $lookup_domain) { 
    $domains | ForEach-Object {
        Write-Host "Searching domain $_" -ForegroundColor Cyan
        if ($global:mode = "User") {
            $QueryResults = Get-ADUser -Filter {SamAccountName -like $global:Username -and GivenName -like $global:First_Name -and Surname -like $global:Last_Name -and Initials -like $global:Middle_Initial} -Properties * -Server "$_"
        } elseif ($global:mode = "Group") {
            $QueryResults = Get-ADGroup -Filter {Name -like $global:Username} -Properties * -Server $_
        } elseif ($global:mode = "Computer") { 
            $QueryResults = Get-ADComputer -Filter {Name -like $global:Computer} -Properties * -Server $_
        }

        if ($QueryResults) {
            Write-Host $QueryResults
        } else {
            Write-Host "No results found in $_" -ForegroundColor Red
        }
    } 
}
Enter_to_Exit