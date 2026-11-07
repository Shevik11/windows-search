# Shared by install.ps1 and uninstall.ps1: find, read and rewrite PowerShell profiles safely.

$script:Marker = '# windows-search'

function Get-DefaultProfiles([switch]$All) {
    # MyDocuments follows OneDrive redirection and localized folder names
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $list = @(Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
    if ($All -or (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        $list += Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'
    }
    return $list
}

function Test-SearchLine([string]$l) {
    # Our line (current or older installer versions), or any hand-written / broken import of this module
    return $l.Contains($script:Marker) -or $l -match 'windows-search[\\/]+Search\.psm1'
}

function Read-ProfileLines([string]$path) {
    if (-not (Test-Path $path)) { return ,@() }
    $bytes = [IO.File]::ReadAllBytes($path)
    try   { $text = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes) }   # UTF-8 (strict)
    catch { $text = [Text.Encoding]::Default.GetString($bytes) }                     # legacy ANSI file
    $text  = $text.TrimStart([char]0xFEFF)
    $lines = New-Object System.Collections.Generic.List[string]
    if ($text.Length -gt 0) { $lines.AddRange([string[]]($text -split "\r?\n")) }
    while ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -eq '') { $lines.RemoveAt($lines.Count - 1) }
    return ,$lines
}

function Write-ProfileLines([string]$path, $lines) {
    $dir = Split-Path $path
    if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Force -Path $dir }
    $text = if ($lines.Count) { ($lines -join "`r`n") + "`r`n" } else { '' }
    # UTF-8 with BOM: read correctly by both Windows PowerShell 5.1 and PowerShell 7
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($true)))
}
