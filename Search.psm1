#Requires -Version 5.1
# search - fast file name search for Windows.
#   search "invoice"                 files whose name contains "invoice" (current folder, recursive)
#   search "*.pdf" D:\Docs           wildcards + explicit folder
#   search "report" -All             every fixed drive
#   search "config" -Dirs            include folders in the results
# Note: keep this file ASCII-only (Windows PowerShell 5.1 reads BOM-less files as ANSI).

Set-StrictMode -Version 2

# --- load (and cache) the compiled C# engine ---------------------------------
if (-not ('WinSearch.Finder' -as [type])) {
    $src  = Join-Path $PSScriptRoot 'FastFind.cs'
    $hash = (Get-FileHash -Path $src -Algorithm SHA256).Hash.Substring(0, 12)
    $dll  = Join-Path $PSScriptRoot "bin\FastFind-$hash.dll"
    if (-not (Test-Path $dll)) {
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $dll)
        Get-ChildItem (Split-Path $dll) -Filter 'FastFind-*.dll' | Remove-Item -ErrorAction SilentlyContinue
        Add-Type -Path $src -OutputAssembly $dll -OutputType Library -IgnoreWarnings
    }
    Add-Type -Path $dll
}

# --- helpers -------------------------------------------------------------------
$script:E        = [char]27
$script:Ellipsis = [string][char]0x2026
$script:HLine    = [char]0x2500
$script:Dot      = [char]0x00B7

function Format-Size([long]$bytes) {
    if ($bytes -lt 0)    { return 'folder' }
    if ($bytes -lt 1KB)  { return "$bytes B" }
    if ($bytes -lt 1MB)  { return '{0:N1} KB' -f ($bytes / 1KB) }
    if ($bytes -lt 1GB)  { return '{0:N1} MB' -f ($bytes / 1MB) }
    return '{0:N2} GB' -f ($bytes / 1GB)
}

function Limit-End([string]$s, [int]$w) {
    if ($s.Length -le $w) { return $s }
    if ($w -le 1) { return $script:Ellipsis }
    return $s.Substring(0, $w - 1) + $script:Ellipsis
}

function Limit-Middle([string]$s, [int]$w) {
    if ($s.Length -le $w) { return $s }
    if ($w -le 3) { return Limit-End $s $w }
    $left  = [int][math]::Ceiling(($w - 1) * 0.4)
    $right = ($w - 1) - $left
    return $s.Substring(0, $left) + $script:Ellipsis + $s.Substring($s.Length - $right)
}

function Get-Link([string]$path, [string]$text, [bool]$enabled) {
    # OSC 8 hyperlink: Ctrl+Click in Windows Terminal opens the file / folder
    if (-not $enabled) { return $text }
    $uri = ([Uri]$path).AbsoluteUri
    return "$E]8;;$uri$E\$text$E]8;;$E\"
}

function Write-SearchTable($hits, [string]$pattern, [bool]$color, [string[]]$roots) {
    $width = 160
    try { if ($Host.UI.RawUI.WindowSize.Width -gt 0) { $width = $Host.UI.RawUI.WindowSize.Width } } catch { }
    $links = $color -and [bool]$env:WT_SESSION

    $sizeW = 9; $dateW = 16; $gap = '  '
    $maxName = ($hits | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
    $nameW = [math]::Max(4, [math]::Min($maxName, 50))
    $folderW = $width - $nameW - $sizeW - $dateW - 3 * $gap.Length - 1
    if ($folderW -lt 30) {
        $nameW = [math]::Max(16, $nameW - (30 - $folderW))
        $folderW = [math]::Max(20, $width - $nameW - $sizeW - $dateW - 3 * $gap.Length - 1)
    }

    if ($color) {
        $R = "$E[0m"; $Hd = "$E[1;36m"; $Dim = "$E[90m"; $Hi = "$E[1;30;43m"
        $FileC = "$E[97m"; $DirC = "$E[1;94m"; $SizeC = "$E[32m"; $DateC = "$E[37m"
    } else {
        $R = $Hd = $Dim = $Hi = $FileC = $DirC = $SizeC = $DateC = ''
    }
    $literal = $pattern.IndexOfAny([char[]]'*?') -lt 0

    # If full folder paths don't fit, show them relative to the search folder (.\sub\dir)
    $relRoot = $null
    $maxFolder = ($hits | ForEach-Object { $_.Folder.Length } | Measure-Object -Maximum).Maximum
    if ($roots.Count -eq 1 -and $maxFolder -gt $folderW -and $roots[0].TrimEnd('\').Length -gt 2) {
        $relRoot = $roots[0].TrimEnd('\')
    }
    $folderHeader = if ($relRoot) { "Folder  $Dim(.\ = $relRoot)" } else { 'Folder' }

    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine()
    $null = $sb.AppendLine($Hd + 'Name'.PadRight($nameW) + $gap + 'Size'.PadLeft($sizeW) + $gap + 'Modified'.PadRight($dateW) + $gap + $folderHeader + $R)
    $null = $sb.AppendLine($Dim + ([string]$HLine * $nameW) + $gap + ([string]$HLine * $sizeW) + $gap + ([string]$HLine * $dateW) + $gap + ([string]$HLine * [math]::Min($folderW, 60)) + $R)

    foreach ($h in $hits) {
        $nameC = if ($h.IsFolder) { $DirC } else { $FileC }
        $name  = Limit-End $h.Name $nameW
        $pad   = ' ' * ($nameW - $name.Length)

        # highlight the matched part of the name
        $shown = $name
        if ($color -and $literal) {
            $i = $name.IndexOf($pattern, [StringComparison]::OrdinalIgnoreCase)
            if ($i -ge 0 -and $i + $pattern.Length -le $name.Length) {
                $shown = $name.Substring(0, $i) + $Hi + $name.Substring($i, $pattern.Length) + $R + $nameC + $name.Substring($i + $pattern.Length)
            }
        }
        $shown  = Get-Link $h.FullName $shown $links
        $size   = (Format-Size $h.Size).PadLeft($sizeW)
        $date   = if ($h.Modified -gt [datetime]::MinValue) { $h.Modified.ToString('yyyy-MM-dd HH:mm') } else { '' }
        $folderText = $h.Folder
        if ($relRoot -and $folderText.StartsWith($relRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $folderText = '.' + $folderText.Substring($relRoot.Length)
            if ($folderText -eq '.') { $folderText = '.\' }
        }
        $folder = Get-Link $h.Folder (Limit-Middle $folderText $folderW) $links

        $null = $sb.AppendLine($nameC + $shown + $R + $pad + $gap + $SizeC + $size + $R + $gap + $DateC + $date.PadRight($dateW) + $R + $gap + $Dim + $folder + $R)
    }
    Write-Host $sb.ToString() -NoNewline
}

function Show-SearchHelp {
    $help = @"

  search - fast file name search

  USAGE
    search "<text>" [folder] [options]

  MATCHING
    search "invoice"            name contains "invoice" (case-insensitive)
    search "*.pdf"              wildcards * and ? match the whole name
    search "report??.xlsx"

  WHERE  (default: current folder + all subfolders)
    search "invoice" D:\Docs    search a specific folder
    search "invoice" -All       search every fixed drive

  OPTIONS
    -Dirs                 also match folder names
    -DirsOnly             only match folder names
    -Exclude a,b          skip folders with these names (e.g. node_modules,.git)
    -Limit N              stop after N matches (default 1000, 0 = no limit)
    -PassThru             output objects instead of a table (for piping)
    -h, --help            show this help

  EXAMPLES
    search "budget" -All -Exclude node_modules
    search "*.log" C:\Projects -Limit 0
    search "photo" -PassThru | Where-Object Size -gt 5MB

  Results of the last search are kept in `$SearchResults (e.g. ii `$SearchResults[0].FullName).
  In Windows Terminal, Ctrl+Click a name or folder to open it.

"@
    Write-Host $help
}

# --- main command --------------------------------------------------------------
function Search-File {
    <#
    .SYNOPSIS
        Fast recursive file name search. Prints a table of matching files and their folders.
    .PARAMETER Name
        Text the file name must contain (case-insensitive). Wildcards * and ? switch to full-name matching, e.g. "*.pdf" or "report??.xlsx".
    .PARAMETER Path
        Folder(s) to search. Defaults to the current folder.
    .PARAMETER All
        Search every fixed drive (C:\, D:\, ...).
    .PARAMETER Dirs
        Also match folder names.
    .PARAMETER DirsOnly
        Only match folder names.
    .PARAMETER Exclude
        Folder names to skip entirely, e.g. -Exclude node_modules,.git
    .PARAMETER Limit
        Stop after this many matches (default 1000). 0 = no limit.
    .PARAMETER PassThru
        Return objects (Name, Folder, FullName, IsFolder, Size, Modified) instead of printing a table.
    .EXAMPLE
        search "invoice"
    .EXAMPLE
        search "*.log" C:\Projects -Exclude node_modules
    .EXAMPLE
        search "budget" -All -PassThru | Where-Object Size -gt 1MB
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Name,
        [Parameter(Position = 1)][Alias('In')][string[]]$Path,
        [switch]$All,
        [switch]$Dirs,
        [switch]$DirsOnly,
        [string[]]$Exclude,
        [int]$Limit = 1000,
        [switch]$PassThru,
        [Alias('h')][switch]$Help
    )

    if ($Help -or -not $Name -or $Name -in '--help', 'help', '/?', '/h') {
        Show-SearchHelp
        return
    }

    # resolve where to search
    if ($All) {
        $roots = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { $_.RootDirectory.FullName })
    } elseif ($Path) {
        $roots = @(foreach ($p in $Path) {
            $full = [IO.Path]::GetFullPath($PSCmdlet.GetUnresolvedProviderPathFromPSPath($p))
            if (-not [IO.Directory]::Exists($full)) { Write-Error "Folder not found: $p"; return }
            $full
        })
    } else {
        $loc = Get-Location
        $roots = @(if ($loc.Provider.Name -eq 'FileSystem') { $loc.ProviderPath } else { $HOME })
    }

    $finder = New-Object WinSearch.Finder -ArgumentList $roots, $Name, (-not $DirsOnly), ([bool]($Dirs -or $DirsOnly)), $Limit, $Exclude, 0
    $hits   = New-Object 'System.Collections.Generic.List[WinSearch.Hit]'
    $color  = -not $PassThru -and -not [Console]::IsOutputRedirected
    $sw     = [Diagnostics.Stopwatch]::StartNew()
    $status = $false

    $finder.Start()
    try {
        $h = $null
        while ($true) {
            $done = $finder.IsDone
            while ($finder.TryTake([ref]$h)) { $hits.Add($h) }
            if ($done) { break }
            if ($color -and $sw.ElapsedMilliseconds -gt 400) {
                $msg = " searching$Ellipsis {0:N0} folders, {1:N0} matches" -f $finder.DirsScanned, $hits.Count
                [Console]::Write("`r$E[90m$msg$E[0m$E[K")
                $status = $true
            }
            Start-Sleep -Milliseconds 25
        }
    } finally {
        $finder.Cancel()   # also stops the worker threads on Ctrl+C
        if ($status) { [Console]::Write("`r$E[K") }
    }
    $sw.Stop()

    [WinSearch.Finder]::Sort($hits)
    $global:SearchResults = $hits

    if ($PassThru) { return $hits }

    $where = $roots -join ', '
    if ($hits.Count -eq 0) {
        Write-Host "No matches for '$Name' in $where" -ForegroundColor Yellow
    } else {
        Write-SearchTable $hits $Name $color $roots
    }

    $what = if ($DirsOnly) { 'folders' } elseif ($Dirs) { 'matches' } else { 'files' }
    $summary = "{0:N0} {1} $Dot {2:N0} folders scanned $Dot {3:N2}s $Dot {4}" -f $hits.Count, $what, $finder.DirsScanned, $sw.Elapsed.TotalSeconds, $where
    Write-Host ''
    Write-Host $summary -ForegroundColor DarkGray
    if ($finder.DirsDenied -gt 0) {
        Write-Host ("{0:N0} folders skipped (access denied)" -f $finder.DirsDenied) -ForegroundColor DarkGray
    }
    if ($finder.LimitReached) {
        Write-Host "Stopped at $Limit matches - narrow the search or use -Limit 0 to show all." -ForegroundColor Yellow
    }
}

Set-Alias -Name search -Value Search-File
Export-ModuleMember -Function Search-File -Alias search
