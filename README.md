# windows-search

**Fast file search for Windows, right in your terminal.**

Windows Explorer search is painfully slow. `search` finds files by name in seconds and shows them in a clean, colored table with their size, date and folder.

```
PS> search "invoice"

Name                            Size  Modified          Folder  (.\ = C:\Users\me)
─────────────────────────  ─────────  ────────────────  ──────────────────────────
invoice_2026_03.pdf         182.4 KB  2026-03-14 10:21  .\Documents\Finance
Invoices.xlsx                28.3 KB  2026-10-08 10:20  .\Documents\Finance\2026
old-invoice-template.docx    41.0 KB  2025-11-02 18:05  .\Desktop

3 files · 48,846 folders scanned · 1.66s · C:\Users\me
```

## How fast?

The same search over a home folder with ~49,000 subfolders:

| Tool                     | Time       |
|--------------------------|------------|
| **`search`**             | **1.7 s**  |
| `cmd /c dir /s /b`       | 13.1 s     |
| `Get-ChildItem -Recurse` | 11.5 s     |

A whole C: drive (~113,000 folders) takes about 2–7 s.

It is fast because it talks to Windows directly (`FindFirstFileEx` with large fetch), scans many folders in parallel, and skips the Explorer shell and search indexer completely.

## Install

Requirements: Windows 10 or 11. Nothing to install. It uses the PowerShell that comes with Windows (PowerShell 7 works too).

1. Get the code, either with git:
   ```powershell
   git clone https://github.com/Shevik11/windows-search.git "$HOME\tools\windows-search"
   ```
   or with **Code → Download ZIP** on GitHub, then unzip it somewhere permanent (for example `C:\Users\<you>\tools\windows-search`).

2. Run the installer from that folder:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME\tools\windows-search\install.ps1"
   ```

3. Open a **new** PowerShell window and try `search "something"`.

The installer:
- adds one `Import-Module` line to your PowerShell profile (5.1, plus 7 if you have it),
- replaces any old or broken `search` lines already in your profile (for example from an earlier manual attempt),
- unblocks the files if you downloaded them as a ZIP,
- offers to allow local scripts for your user (`RemoteSigned`) if scripts are currently blocked. It asks before changing anything.

> If you move the folder, run `install.ps1` again from the new location. It replaces the old line. Until you do, `search` simply isn't loaded; new windows don't show errors.

### Troubleshooting

**Red `Import-Module ... no valid module file was found` error when opening PowerShell**

Your profile has a broken `search` line, often a path like `C:\Users\you\C:\Users\you\...` from adding it by hand. Update and re-run the installer, which removes the broken line:
```powershell
git -C "$HOME\tools\windows-search" pull
powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME\tools\windows-search\install.ps1"
```

## Usage

```powershell
search "invoice"                         # name contains "invoice" (case-insensitive), current folder + subfolders
search "*.pdf"                           # wildcards * and ? match the whole name
search "report??.xlsx"
search "invoice" D:\Docs                 # search a specific folder
search "invoice" -All                    # search every drive
search "config" -Dirs                    # also match folder names
search "photos" -DirsOnly                # only folders
search "app" -Exclude node_modules,.git  # skip folders by name
search "log" -Limit 0                    # show all matches (default stops at 1000)
search --help                            # help
```

### Opening results
- In **Windows Terminal**, **Ctrl+Click** a file name to open it, or a folder to open it in Explorer.
- The last results are saved in `$SearchResults`:
  ```powershell
  ii $SearchResults[0].FullName           # open the first file
  ```

### Using results in scripts
`-PassThru` returns objects instead of a table (`Name`, `Folder`, `FullName`, `IsFolder`, `Size`, `Modified`):
```powershell
search "photo" -All -PassThru | Where-Object Size -gt 5MB | Sort-Object Size -Descending
search "*.tmp" -PassThru | Remove-Item -WhatIf
```

## Notes

- Folders you don't have permission to open are skipped and counted in the summary line.
- Junctions and symlinks are not followed, to avoid scanning folders twice or getting stuck in loops.
- Press **Ctrl+C** to stop a search at any time.
- On first run the C# engine (`FastFind.cs`) is compiled into `bin\`. This takes about a second and happens only once.
- Some locked-down work PCs block PowerShell from compiling code. `search` can't run there.

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME\tools\windows-search\uninstall.ps1"
```
Then delete the folder.

## Files

| File            | What it is                                                 |
|-----------------|------------------------------------------------------------|
| `Search.psm1`   | The `search` command: options, progress, table output      |
| `FastFind.cs`   | The multi-threaded search engine (compiled on first use)   |
| `install.ps1`   | Adds `search` to your PowerShell profile (and repairs old lines) |
| `profile-helpers.ps1` | Profile read/write helpers shared by the installer and uninstaller |
| `uninstall.ps1` | Removes it again                                           |
