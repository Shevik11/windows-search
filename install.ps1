# Installs the `search` command for the current user.
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
# Safe to run more than once: it also repairs old or broken `search` lines in your profile.
# Undo with uninstall.ps1.
param([string[]]$ProfilePath)   # optional: target specific profile files (used for testing)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'profile-helpers.ps1')

$module = Join-Path $PSScriptRoot 'Search.psm1'
$quoted = $module.Replace("'", "''")   # single quotes: nothing in the path ($, `) gets expanded
# Test-Path guard: if the folder is moved or deleted, new windows stay quiet instead of showing errors
$line   = "if (Test-Path '$quoted') { Import-Module '$quoted' }   $Marker"

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

# 3. Put exactly one correct import line in the profiles of Windows PowerShell 5.1 and
#    PowerShell 7 (if installed), replacing any old, moved or broken `search` lines.
$profiles = if ($ProfilePath) { $ProfilePath } else { Get-DefaultProfiles }

foreach ($p in $profiles) {
    $lines = Read-ProfileLines $p
    $old   = @($lines | Where-Object { Test-SearchLine $_ })
    if ($old.Count -eq 1 -and $old[0] -eq $line) {
        Write-Host "Already installed: $p" -ForegroundColor DarkGray
        continue
    }
    $new = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) { if (-not (Test-SearchLine $l)) { $new.Add($l) } }
    $new.Add($line)
    Write-ProfileLines $p $new

    if ($old.Count) {
        Write-Host "Fixed: $p" -ForegroundColor Green
        foreach ($o in $old) { Write-Host "  removed old line: $($o.Trim())" -ForegroundColor DarkGray }
    } else {
        Write-Host "Added to: $p" -ForegroundColor Green
    }
}

# 4. Load it now (also compiles the search engine once, takes a second).
Import-Module $module -Force -Global
Write-Host ''
Write-Host 'Done! Try:  search "invoice"     (help: search --help)' -ForegroundColor Green
Write-Host 'Open a new PowerShell window if `search` is not found in this one.' -ForegroundColor DarkGray
