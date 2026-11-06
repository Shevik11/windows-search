# Installs the `search` command for the current user.
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
# Safe to run more than once. Undo with uninstall.ps1.

$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'Search.psm1'
$line   = "Import-Module `"$module`"   # windows-search: search command"

# 1. Files downloaded from the internet (zip, email, Teams) are blocked by Windows - unblock ours.
Get-ChildItem -Path $PSScriptRoot -File | Unblock-File

# 2. Profiles only load if scripts are allowed. Offer to allow local scripts for this user.
#    Ignore the Process scope: "-ExecutionPolicy Bypass" on this run says nothing about new windows.
$effective = 'Restricted'   # Windows client default when nothing is set
foreach ($scope in 'MachinePolicy', 'UserPolicy', 'CurrentUser', 'LocalMachine') {
    $p = Get-ExecutionPolicy -Scope $scope
    if ($p -ne 'Undefined') { $effective = $p; break }
}
if ($effective -in 'Restricted', 'AllSigned') {
    Write-Host "PowerShell scripts are currently blocked on this PC (policy: $effective)." -ForegroundColor Yellow
    Write-Host "The search command needs: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
    $answer = Read-Host 'Allow local scripts for your user now? [Y/n]'
    if ($answer -eq '' -or $answer -match '^[Yy]') {
        try {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
        } catch {
            Write-Host "Could not change it ($($_.Exception.Message)). It may be locked by your organization." -ForegroundColor Red
        }
    } else {
        Write-Host 'Skipped. `search` will not load until scripts are allowed.' -ForegroundColor Yellow
    }
}

# 3. Add the import line to the profiles of Windows PowerShell 5.1 and PowerShell 7 (if installed).
$docs = [Environment]::GetFolderPath('MyDocuments')   # handles OneDrive-redirected Documents
$profiles = @(Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    $profiles += Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'
}

foreach ($p in $profiles) {
    if (-not (Test-Path $p)) { $null = New-Item -ItemType File -Force -Path $p }
    $content = Get-Content -Path $p -Raw
    if ($content -and $content.Contains($module)) {
        Write-Host "Already installed: $p" -ForegroundColor DarkGray
    } else {
        Add-Content -Path $p -Value $line -Encoding UTF8
        Write-Host "Added to: $p" -ForegroundColor Green
    }
}

# 4. Load it now (also compiles the search engine once, takes a second).
Import-Module $module -Force -Global
Write-Host ''
Write-Host 'Done! Try:  search "invoice"     (help: search --help)' -ForegroundColor Green
Write-Host 'Open a new PowerShell window if `search` is not found in this one.' -ForegroundColor DarkGray
