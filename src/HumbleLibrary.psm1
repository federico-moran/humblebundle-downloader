# Logic for Get-HumbleLibrary.ps1, kept free of network calls so it can be tested.

# What to do with each file in the orders: one item per file, with the action to take.
# A file offered in several bundles (same MD5) is planned once, with every bundle recorded.
function Get-DownloadPlan {
    [CmdletBinding()]
    param(
        [object[]]$Orders,
        [string[]]$Format = @('pdf', 'epub', 'cbz', 'supplement'),
        [string[]]$Platform = @('ebook'),
        [object[]]$Manifest = @(),  # rows of manifest.csv from earlier runs
        [switch]$Update             # download new versions of books already downloaded
    )
    $have = @{}    # md5 -> manifest row of a file already downloaded
    $byItem = @{}  # "item|format" -> the same, to recognise a new version of a book
    foreach ($row in $Manifest) {
        if ($row.status -ne 'present' -or -not $row.md5) { continue }
        $have[$row.md5.ToLowerInvariant()] = $row
        if ($row.item) { $byItem["$($row.item)|$($row.format)"] = $row }
    }
    $taken = @{}  # file name -> key of the file using it
    foreach ($row in $have.Values) { $taken[$row.file] = $row.md5.ToLowerInvariant() }
    $offered = @{}  # md5 and "item|format" of every file in the orders
    $plan = [ordered]@{}  # md5 (or file name and size, when Humble gives no MD5) -> item
    foreach ($order in $Orders) {
        foreach ($sub in $order.subproducts) {
            foreach ($dl in $sub.downloads) {
                foreach ($f in $dl.download_struct) {
                    $fmt = $f.name.ToLowerInvariant()
                    if ($fmt -in 'supplement', 'download', 'zip', '.zip') { $fmt = 'supplement' }  # zips of code, videos, disc contents
                    # Everything Humble offers, whatever this run downloads, so nothing is wrongly marked removed.
                    if ($f.md5) { $offered[$f.md5.ToLowerInvariant()] = $true }
                    $offered["$($sub.machine_name)|$fmt"] = $true
                    if ($dl.platform -notin $Platform -or $fmt -notin $Format -or -not $f.url.web) { continue }  # no link: hosted elsewhere
                    $file = [IO.Path]::GetFileName(([uri]$f.url.web).AbsolutePath)
                    $key = if ($f.md5) { $f.md5.ToLowerInvariant() } else { "$file|$($f.file_size)" }
                    if ($plan.Contains($key)) {
                        $plan[$key].Bundles += $order.product.human_name
                        continue
                    }
                    $action = 'download'
                    $older = $byItem["$($sub.machine_name)|$fmt"]
                    if ($have[$key]) {
                        $action = 'skip'
                        $file = $have[$key].file
                    } elseif ($older) {
                        $action = if ($Update) { 'update' } else { 'update-available' }
                        $file = $older.file
                    } elseif ($taken[$file] -and $taken[$file] -ne $key) {
                        # A different file with the same name: keep both, telling them apart by MD5.
                        $file = '{0}.{1}{2}' -f [IO.Path]::GetFileNameWithoutExtension($file), $key.Substring(0, [Math]::Min(6, $key.Length)), [IO.Path]::GetExtension($file)
                    }
                    $taken[$file] = $key
                    $plan[$key] = [pscustomobject]@{
                        Action  = $action
                        File    = $file
                        Item    = $sub.machine_name
                        Format  = $fmt
                        Title   = $sub.human_name
                        Bundles = @($order.product.human_name)
                        Md5     = $f.md5
                        Bytes   = [long]$f.file_size
                        Url     = $f.url.web
                    }
                }
            }
        }
    }
    $plan.Values
    # Downloaded files Humble no longer offers (not even as a newer version) are kept, and reported.
    foreach ($row in $have.Values) {
        if ($offered[$row.md5.ToLowerInvariant()] -or $offered["$($row.item)|$($row.format)"]) { continue }
        [pscustomobject]@{ Action = 'removed'; File = $row.file; Item = $row.item; Format = $row.format; Md5 = $row.md5 }
    }
}

# Checks a downloaded file against the size and MD5 Humble gives for it.
function Test-DownloadedFile {
    [CmdletBinding()]
    param([string]$Path, [long]$Bytes, [string]$Md5)
    if ((Get-Item -LiteralPath $Path).Length -ne $Bytes) { return 'mismatch' }  # cut off, or an error page
    if (-not $Md5) { return 'size-only' }  # Humble gave no MD5 for this file
    if ((Get-FileHash -LiteralPath $Path -Algorithm MD5).Hash -ne $Md5) { return 'mismatch' }
    return 'ok'
}

# Checks the folder against the manifest without contacting Humble (-VerifyOnly), e.g. for a backup copy.
function Test-Library {
    [CmdletBinding()]
    param([string]$Folder, [object[]]$Manifest)
    foreach ($row in $Manifest | Where-Object status -eq 'present') {
        $path = Join-Path $Folder $row.file
        $status = if (-not (Test-Path -LiteralPath $path)) { 'missing' }
            elseif ((Test-DownloadedFile -Path $path -Bytes $row.bytes -Md5 $row.md5) -eq 'mismatch') { 'changed' }
            else { 'ok' }
        [pscustomobject]@{ File = $row.file; Status = $status }
    }
    foreach ($part in Get-ChildItem -LiteralPath $Folder -Filter '*.part' -File) {
        [pscustomobject]@{ File = $part.Name; Status = 'unfinished' }
    }
}

# Compares another folder (an old download folder, the PacktPub library) with this library (-CompareWith).
# Each file there is reported with the file here it matches. Subfolders are included.
function Compare-Library {
    [CmdletBinding()]
    param([object[]]$Manifest, [string]$Folder)
    # Titles and file names compared as letters and digits only, without a leading "The".
    $key = { param($s) ([string]$s).ToLowerInvariant() -replace '^the\W+', '' -replace '[^\p{L}\p{N}]', '' }
    $byMd5 = @{}
    $present = @($Manifest | Where-Object status -eq 'present')
    foreach ($row in $present) { $byMd5[$row.md5.ToLowerInvariant()] = $row }
    $root = (Resolve-Path -LiteralPath $Folder).Path.TrimEnd('\') + '\'
    # A folder with its own manifest (the PacktPub library names files by ISBN) gives the titles.
    $titles = @{}
    $otherManifest = Join-Path $Folder 'manifest.csv'
    if (Test-Path -LiteralPath $otherManifest) {
        foreach ($r in Import-Csv -LiteralPath $otherManifest) { if ($r.file -and $r.title) { $titles[$r.file] = $r.title } }
    }
    $books = Get-ChildItem -LiteralPath $Folder -File -Recurse | Where-Object Extension -notin '.csv', '.json', '.txt'
    foreach ($f in $books) {
        $match = $byMd5[(Get-FileHash -LiteralPath $f.FullName -Algorithm MD5).Hash.ToLowerInvariant()]
        $status = 'identical'
        if (-not $match) {
            # Similar when one name contains the other, ignoring short names that would match too much.
            $name = & $key $(if ($titles[$f.Name]) { $titles[$f.Name] } else { $f.BaseName })
            $match = $present | Where-Object {
                $t = & $key $_.title
                [Math]::Min($t.Length, $name.Length) -ge 10 -and ($t.Contains($name) -or $name.Contains($t))
            } | Select-Object -First 1
            $status = if ($match) { 'similar-title' } else { 'only-there' }
        }
        [pscustomobject]@{ Other = $f.FullName.Substring($root.Length); Status = $status; Ours = $match.file }
    }
}

Export-ModuleMember -Function Get-DownloadPlan, Test-DownloadedFile, Test-Library, Compare-Library
