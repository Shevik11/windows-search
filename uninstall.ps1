# Removes the `search` command from your PowerShell profiles.
#   powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
# Does not delete this folder and does not change your execution policy.

$docs = [Environment]::GetFolderPath('MyDocuments')
$profiles = @(
    Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
    Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'
)

foreach ($p in $profiles) {
    if (-not (Test-Path $p)) { continue }
    $lines = @(Get-Content -Path $p)
    $kept  = @($lines | Where-Object { $_ -notmatch 'windows-search[\\/]Search\.psm1' })
    if ($kept.Count -ne $lines.Count) {
        Set-Content -Path $p -Value $kept -Encoding UTF8
        Write-Host "Removed from: $p" -ForegroundColor Green
    }
}

Remove-Module Search -ErrorAction SilentlyContinue
Write-Host 'Uninstalled. You can now delete this folder.' -ForegroundColor Green
