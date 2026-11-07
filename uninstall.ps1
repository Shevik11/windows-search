# Removes the `search` command from your PowerShell profiles.
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
# Does not delete this folder and does not change your execution policy.
param([string[]]$ProfilePath)   # optional: target specific profile files (used for testing)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'profile-helpers.ps1')

$profiles = if ($ProfilePath) { $ProfilePath } else { Get-DefaultProfiles -All }

foreach ($p in $profiles) {
    if (-not (Test-Path $p)) { continue }
    $lines = Read-ProfileLines $p
    $kept  = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) { if (-not (Test-SearchLine $l)) { $kept.Add($l) } }
    if ($kept.Count -ne $lines.Count) {
        Write-ProfileLines $p $kept
        Write-Host "Removed from: $p" -ForegroundColor Green
    }
}

Remove-Module Search -ErrorAction SilentlyContinue
Write-Host 'Uninstalled. You can now delete this folder.' -ForegroundColor Green
