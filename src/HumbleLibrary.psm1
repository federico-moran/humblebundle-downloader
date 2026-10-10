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

# What a downloaded file really is, judged by its content: 'pdf', 'epub' or 'zip' when it is complete,
# otherwise nothing. Humble sometimes serves an EPUB under a .pdf link.
function Get-BookFileType {
    [CmdletBinding()]
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        # A zip's index is at its end, so a cut-off zip can't be opened.
        $zip = [IO.Compression.ZipFile]::OpenRead($Path)
        try {
            $first = $zip.Entries | Select-Object -First 1
            if ($first.FullName -eq 'mimetype') {
                $r = New-Object IO.StreamReader($first.Open())
                try { if ($r.ReadToEnd().Trim() -eq 'application/epub+zip') { return 'epub' } } finally { $r.Dispose() }
            }
            return 'zip'
        } finally { $zip.Dispose() }
    } catch [IO.InvalidDataException] { }  # not a zip, or a cut-off one
    $s = [IO.File]::OpenRead($Path)
    try {
        $head = New-Object byte[] 5
        $null = $s.Read($head, 0, 5)
        if ([Text.Encoding]::ASCII.GetString($head) -eq '%PDF-') {
            $n = [int][Math]::Min(2048, $s.Length)
            $null = $s.Seek(-$n, 'End')
            $tail = New-Object byte[] $n
            $null = $s.Read($tail, 0, $n)
            if ([Text.Encoding]::ASCII.GetString($tail).Contains('%%EOF')) { return 'pdf' }  # no end marker: cut off
        }
    } finally { $s.Dispose() }
}

# Checks the folder against the manifest without contacting Humble (-VerifyOnly), e.g. for a backup copy.
function Test-Library {
    [CmdletBinding()]
    param([string]$Folder, [object[]]$Manifest)
    foreach ($row in $Manifest | Where-Object status -eq 'present') {
        $path = Join-Path $Folder $row.file
        $status = if (-not (Test-Path -LiteralPath $path)) { 'missing' }
            # file_md5: the file's own MD5, recorded when Humble's MD5 for it turned out wrong
            elseif ((Test-DownloadedFile -Path $path -Bytes $row.bytes -Md5 $(if ($row.file_md5) { $row.file_md5 } else { $row.md5 })) -eq 'mismatch') { 'changed' }
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
    foreach ($row in $present) {
        $byMd5[$row.md5.ToLowerInvariant()] = $row
        if ($row.file_md5) { $byMd5[$row.file_md5.ToLowerInvariant()] = $row }  # the file's own, when Humble's was wrong
    }
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

# A bundle's name as a Calibre tag. Calibre separates tags with commas, so commas in the name are dropped.
function ConvertTo-CalibreTag {
    [CmdletBinding()]
    param([string]$Bundle)
    ($Bundle -replace ',', '' -replace '\s+', ' ').Trim()
}

# What to do in Calibre for each EPUB in the library: 'add' it (tagged with its source and bundles), 'tag' a book
# already there that lacks some of its bundle tags, or 'skip' it. Calibre books are recognised by the MD5
# of their EPUB, since Calibre stores the file unchanged.
function Get-CalibrePlan {
    [CmdletBinding()]
    param(
        [object[]]$Manifest,
        [hashtable]$InCalibre = @{},  # MD5 of an EPUB in Calibre -> @{ id; tags }
        [string]$SourceTag = 'Humble Bundle'  # where the book came from, added to every book's tags
    )
    foreach ($row in $Manifest | Where-Object { $_.status -eq 'present' -and $_.format -eq 'epub' }) {
        $tags = @(@($SourceTag) + @($row.bundles -split '; ' | ForEach-Object { ConvertTo-CalibreTag $_ }) | Where-Object { $_ })
        # file_md5: the file's own, when Humble's MD5 for it was wrong
        $md5 = $(if ($row.file_md5) { $row.file_md5 } else { $row.md5 }).ToLowerInvariant()
        $book = $InCalibre[$md5]
        $item = [pscustomobject]@{ Action = 'add'; File = $row.file; Title = $row.title; Tags = $tags; Id = $null }
        if ($book) {
            $item.Id = $book.id
            $missing = @($tags | Where-Object { @($book.tags) -notcontains $_ })
            if ($missing) {
                $item.Action = 'tag'
                $item.Tags = @(@($book.tags) + $missing | Where-Object { $_ })  # keeps the tags already there
            } else {
                $item.Action = 'skip'
            }
        }
        $item
    }
}

Export-ModuleMember -Function Get-DownloadPlan, Test-DownloadedFile, Get-BookFileType, Test-Library, Compare-Library, ConvertTo-CalibreTag, Get-CalibrePlan
