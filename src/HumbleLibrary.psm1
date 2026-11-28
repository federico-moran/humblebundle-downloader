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
    $byItem = @{}  # "item|format" -> the same, to recognize a new version of a book
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
                    $link = [uri]::new($f.url.web, [UriKind]::RelativeOrAbsolute)  # since 2026-11, a bare file name
                    $file = [IO.Path]::GetFileName($(if ($link.IsAbsoluteUri) { $link.AbsolutePath } else { $f.url.web }))
                    $key = if ($f.md5) { $f.md5.ToLowerInvariant() } else { "$file|$($f.file_size)" }
                    if ($plan.Contains($key)) {
                        $plan[$key].Bundles += $order.product.human_name
                        if ("$($sub.available_until)" -gt "$($plan[$key].AvailableUntil)") { $plan[$key].AvailableUntil = $sub.available_until }  # ISO dates
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
                        # From ConvertFrom-PurchasePage: where to sign the link, and Humble's deadline
                        PurchaseId     = $order.purchase_id
                        EntitlementId  = $sub.entitlement_id
                        AvailableUntil = $sub.available_until
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

# A string as an ISBN-13 (an ISBN-10 is converted), or nothing when it isn't a valid ISBN.
function ConvertTo-Isbn13([string]$Text) {
    $s = ($Text -replace '^\s*(urn:)?(isbn)?\W*', '' -replace '[\s-]', '').ToUpperInvariant()
    if ($s -match '^\d{9}[\dX]$') {
        $sum = 0
        for ($i = 0; $i -lt 10; $i++) { $sum += (10 - $i) * $(if ($s[$i] -eq 'X') { 10 } else { [int][string]$s[$i] }) }
        if ($sum % 11) { return }
        $s = '978' + $s.Substring(0, 9)
    } elseif ($s -notmatch '^97[89]\d{10}$') { return }
    $sum = 0
    for ($i = 0; $i -lt 12; $i++) { $sum += [int][string]$s[$i] * (1 + 2 * ($i % 2)) }
    $check = (10 - $sum % 10) % 10
    if ($s.Length -eq 13 -and [int][string]$s[12] -ne $check) { return }
    $s.Substring(0, 12) + $check
}

# The ISBNs an EPUB gives for itself (the identifiers in its package file), as ISBN-13s.
# Often both the print and the ebook ISBN.
function Get-EpubIsbn {
    [CmdletBinding()]
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try { $zip = [IO.Compression.ZipFile]::OpenRead($Path) } catch { return }  # missing, not a zip, or cut off
    try {
        $read = { param($entry) $r = New-Object IO.StreamReader($entry.Open()); try { $r.ReadToEnd() } finally { $r.Dispose() } }
        $opf = $null
        $container = $zip.GetEntry('META-INF/container.xml')
        if ($container -and (& $read $container) -match 'full-path="([^"]+)"') { $opf = $zip.GetEntry($Matches[1]) }
        if (-not $opf) { $opf = $zip.Entries | Where-Object FullName -like '*.opf' | Select-Object -First 1 }
        if (-not $opf) { return }
        [regex]::Matches((& $read $opf), '<(?:dc:)?identifier[^>]*>([^<]+)<') |
            ForEach-Object { ConvertTo-Isbn13 $_.Groups[1].Value } | Select-Object -Unique
    } finally { $zip.Dispose() }
}

# Compares another folder (an old download folder, the PacktPub library) with this library (-CompareWith).
# Each file there is reported with the file here it matches: 'identical' (same MD5), 'same-isbn' (an ISBN in
# common), 'same-title' (exactly the same title, to check by hand: different books can share a title), or
# 'only-there'. Subfolders are included.
function Compare-Library {
    [CmdletBinding()]
    param(
        [object[]]$Manifest,
        [string]$Library,  # this library's folder, to read the ISBNs in its EPUBs
        [string]$Folder
    )
    # Titles and file names compared as letters and digits only, without a leading "The".
    $key = { param($s) ([string]$s).ToLowerInvariant() -replace '^the\W+', '' -replace '[^\p{L}\p{N}]', '' }
    $byMd5 = @{}
    $byItem = @{}   # item -> its files here (a book's PDF and EPUB share an item)
    $byIsbn = @{}   # ISBN -> item, from the item's EPUB
    $byTitle = @{}  # normalized title -> item
    foreach ($row in $Manifest | Where-Object status -eq 'present') {
        $byMd5[$row.md5.ToLowerInvariant()] = $row
        if ($row.file_md5) { $byMd5[$row.file_md5.ToLowerInvariant()] = $row }  # the file's own, when Humble's was wrong
        $item = if ($row.item) { $row.item } else { $row.file }
        $byItem[$item] = @($byItem[$item]) + $row | Where-Object { $_ }
        $title = & $key $row.title
        if ($title -and -not $byTitle.Contains($title)) { $byTitle[$title] = $item }
        if ($row.format -eq 'epub') {
            foreach ($isbn in Get-EpubIsbn -Path (Join-Path $Library $row.file)) { $byIsbn[$isbn] = $item }
        }
    }
    $root = (Resolve-Path -LiteralPath $Folder).Path.TrimEnd('\') + '\'
    # A folder with its own manifest (the PacktPub library names files by ISBN) gives titles and ISBNs.
    $titles = @{}
    $isbns = @{}
    $otherManifest = Join-Path $Folder 'manifest.csv'
    if (Test-Path -LiteralPath $otherManifest) {
        foreach ($r in Import-Csv -LiteralPath $otherManifest) {
            if ($r.file -and $r.title) { $titles[$r.file] = $r.title }
            if ($r.file -and $r.isbn) { $isbns[$r.file] = $r.isbn }
        }
    }
    $books = @(Get-ChildItem -LiteralPath $Folder -File -Recurse | Where-Object Extension -notin '.csv', '.json', '.txt')
    # An EPUB's ISBNs also count for the files beside it with the same name (its PDF, say).
    $epubIsbns = @{}
    foreach ($f in $books | Where-Object Extension -eq '.epub') {
        $epubIsbns[(Join-Path $f.DirectoryName $f.BaseName)] = @(Get-EpubIsbn -Path $f.FullName)
    }
    foreach ($f in $books) {
        $match = $byMd5[(Get-FileHash -LiteralPath $f.FullName -Algorithm MD5).Hash.ToLowerInvariant()]
        $status = 'identical'
        if (-not $match) {
            $found = @($epubIsbns[(Join-Path $f.DirectoryName $f.BaseName)]) + (ConvertTo-Isbn13 $isbns[$f.Name]) + (ConvertTo-Isbn13 $f.BaseName) |
                Where-Object { $_ -and $byIsbn[$_] } | Select-Object -First 1
            $item = $byIsbn["$found"]
            $status = 'same-isbn'
            if (-not $item) {
                $item = $byTitle[(& $key $(if ($titles[$f.Name]) { $titles[$f.Name] } else { $f.BaseName }))]
                $status = if ($item) { 'same-title' } else { 'only-there' }
            }
            if ($item) {
                # Our copy in the same format, if we have one.
                $mine = @($byItem[$item])
                $match = $mine | Where-Object { [IO.Path]::GetExtension($_.file) -eq $f.Extension } | Select-Object -First 1
                if (-not $match) { $match = $mine[0] }
            }
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
# already there that lacks some of its bundle tags, or 'skip' it. Calibre books are recognized by the MD5
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

# ---- Reading Humble's pages (the site rebuilt in 2026-11) ---------------------------------------------
# Humble's pages are Next.js: their data is a React Server Components payload, sent as JavaScript string
# chunks, self.__next_f.push([1,"..."]). This joins and decodes them; nothing when the page has none.
function Get-PagePayload {
    [CmdletBinding()]
    param([string]$Html)
    $chunks = [regex]::Matches($Html, 'self\.__next_f\.push\(\[1,("(?:[^"\\]|\\.)*")\]\)')
    if (-not $chunks.Count) { return }
    # Each chunk is a JSON string literal.
    -join ($chunks | ForEach-Object { ConvertFrom-Json $_.Groups[1].Value })
}

# The objects in a page's payload for which $Where is true, wherever they sit in it. The payload is rows of
# "<hex id>:<value>"; only rows holding a JSON object or array are read (others are text or references).
function Find-PayloadObject([string]$Payload, [scriptblock]$Where) {
    $found = New-Object Collections.Generic.List[object]
    $visit = {
        param($node)
        if ($node -is [Collections.IDictionary]) {
            if (& $Where $node) { $found.Add($node) }
            foreach ($v in @($node.Values)) { & $visit $v }
        } elseif ($node -is [Collections.IList]) {
            foreach ($v in $node) { & $visit $v }
        }
    }
    foreach ($line in $Payload -split "`n") {
        if ($line.TrimEnd("`r") -notmatch '^[0-9a-f]+:([\[{].*)$') { continue }
        try { $value = ConvertFrom-Json $Matches[1] -AsHashtable -Depth 1024 } catch { continue }  # text that only looks like JSON
        & $visit $value
    }
    $found
}

# The purchases on the library page (/home/library), each once: Id and Path of its page, and Title.
function ConvertFrom-LibraryPage {
    [CmdletBinding()]
    param([string]$Html)
    $payload = Get-PagePayload -Html $Html
    if (-not $payload) { return }
    $seen = @{}
    foreach ($item in Find-PayloadObject $payload { param($o) $o.itemType -eq 'content-entitlement' -and $o.id -and $o.title }) {
        # The page's link names the purchase's own ID, which can differ from the item's.
        $path = if ($item.href -match '^/home/library/[^/?#]+') { $Matches[0] } else { "/home/library/$($item.id)" }
        if ($seen[$path]) { continue }
        $seen[$path] = $true
        [pscustomobject]@{ Id = $path.Split('/')[-1]; Title = $item.title; Path = $path }
    }
}

# The ID of a Next.js server action, found by its name in the site's public JS chunks, which declare each
# one as createServerReference("<hex id>", ..., "<name>"). The ID changes whenever Humble redeploys.
function Find-ServerActionId {
    [CmdletBinding()]
    param([string[]]$Script, [string]$Name)
    foreach ($s in $Script) {
        foreach ($m in [regex]::Matches("$s", 'createServerReference\)?\(\s*"([0-9a-f]{40,})"\s*,[^"]*"([\w$]+)"\s*\)')) {
            if ($m.Groups[2].Value -ceq $Name) { return $m.Groups[1].Value }
        }
    }
}

# The reply to getSignedUrlsForEntitlements: Urls (file name -> signed link, torrents left out) and
# ExpiresAt (UTC). Throws when Humble signed nothing; the message never repeats the reply.
function ConvertFrom-SignedUrlReply {
    [CmdletBinding()]
    param([string]$Text)
    $result = Find-PayloadObject $Text { param($o) $o.Contains('ok') } | Select-Object -First 1
    if (-not $result) { throw 'Humble''s answer was not the reply of the download action getSignedUrlsForEntitlements.' }
    if ($result.ok -ne $true) {
        $why = if ($result.error -is [string]) { ': ' + ($result.error -replace '<[^>]*>', '').Substring(0, [Math]::Min(200, $result.error.Length)) }
        throw "Humble did not sign the download links$why"
    }
    $urls = @{}
    $collect = {
        param($node)
        foreach ($k in @($node.Keys)) {
            $v = $node[$k]
            if ($v -is [Collections.IDictionary]) { & $collect $v }  # grouped by machine name, then download key
            elseif ($v -is [string] -and $v -match '^https://' -and $k -notlike '*.torrent') { $urls[$k] = $v }
        }
    }
    if ($result.data.signedUrls -is [Collections.IDictionary]) { & $collect $result.data.signedUrls }
    if (-not $urls.Count) { throw 'Humble signed no links for this book.' }
    $expires = $result.data.expiresAt
    if ($expires -is [datetime]) { $expires = $expires.ToUniversalTime() }
    elseif ($expires) { $expires = [datetime]::Parse($expires, [cultureinfo]::InvariantCulture, 'AdjustToUniversal') }
    [pscustomobject]@{ Urls = $urls; ExpiresAt = $expires }
}

# Books with a file not yet downloaded that Humble stops offering within $Days days, or already stopped
# (Humble's unavailableAfter, a year after purchase): one row per book, soonest first.
function Get-DownloadDeadline {
    [CmdletBinding()]
    param(
        [object[]]$Plan,
        [object[]]$Manifest = @(),  # manifest.csv as it is now, including this run's downloads
        [datetime]$Now = [datetime]::UtcNow,
        [int]$Days = 60
    )
    $present = @{}
    foreach ($row in $Manifest) { if ($row.status -eq 'present') { $present[$row.file] = $true } }
    $Plan | Where-Object { $_.AvailableUntil -and $_.Action -notin 'skip', 'removed' -and -not $present[$_.File] } |
        Group-Object Item | ForEach-Object {
            $p = $_.Group[0]
            $until = [datetime]::Parse($p.AvailableUntil, [cultureinfo]::InvariantCulture, 'AdjustToUniversal')
            $left = [int][Math]::Truncate(($until - $Now.ToUniversalTime()).TotalDays)
            if ($left -le $Days) {
                [pscustomobject]@{ Item = $p.Item; Title = $p.Title; AvailableUntil = $p.AvailableUntil; DaysLeft = $left }
            }
        } | Sort-Object AvailableUntil
}

# Which of the plan's removals to record in the manifest. More than $Limit, or every downloaded file of a
# bundle, looks like Humble still migrating old orders rather than withdrawing books: then none is recorded
# (all are HeldBack), unless -AcceptRemovals.
function Get-RemovalDecision {
    [CmdletBinding()]
    param(
        [object[]]$Plan,
        [object[]]$Manifest,
        [switch]$AcceptRemovals,
        [int]$Limit = 10
    )
    $removed = @($Plan | Where-Object Action -eq 'removed')
    $gone = @{}
    foreach ($r in $removed) { $gone[$r.File] = $true }
    $wholeBundle = $false
    if ($removed.Count -and $removed.Count -le $Limit) {
        $files = @{}  # bundle -> its downloaded files
        foreach ($row in $Manifest | Where-Object status -eq 'present') {
            foreach ($b in "$($row.bundles)" -split '; ' | Where-Object { $_ }) { $files[$b] = @($files[$b]) + $row.file | Where-Object { $_ } }
        }
        $wholeBundle = [bool]($files.Values | Where-Object { @($_ | Where-Object { -not $gone[$_] }).Count -eq 0 })
    }
    if ($AcceptRemovals -or ($removed.Count -le $Limit -and -not $wholeBundle)) {
        [pscustomobject]@{ Record = $removed; HeldBack = @() }
    } else {
        [pscustomobject]@{ Record = @(); HeldBack = $removed }
    }
}

# A date from a payload as an ISO 8601 UTC string. PowerShell 7 reads ISO strings in JSON as dates.
function ConvertTo-IsoDate($Value) {
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
    if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
    if ($Value) { [string]$Value }
}

# A purchase page (/home/library/<id>) as an order of the old site's shape, so Get-DownloadPlan and the
# rest work unchanged: product.human_name, subproducts[] (one per book) with machine_name, human_name and
# downloads[].download_struct[] (name, file_size, md5, url.web, which is now a bare file name). Added:
# purchase_id, and per book entitlement_id (to sign its links) and available_until (when Humble stops
# offering it). Nothing when the page holds no purchase.
function ConvertFrom-PurchasePage {
    [CmdletBinding()]
    param([string]$Html)
    $payload = Get-PagePayload -Html $Html
    if (-not $payload) { return }
    $page = Find-PayloadObject $payload { param($o) $o.Contains('userLibraryItem') -and $o.Contains('productEntitlementId') } |
        Select-Object -First 1
    if (-not $page) { return }
    $item = $page.userLibraryItem
    [pscustomobject]@{
        purchase_id = $page.productEntitlementId
        product     = [pscustomobject]@{ human_name = $item.title }
        subproducts = @(foreach ($book in @($item.entitlements.downloads)) {
            if (-not $book) { continue }
            $downloads = @(foreach ($dl in @($book.downloads)) {
                if (-not $dl) { continue }
                # The key is "<machine name>_<platform>"; the machine name is the item in manifest.csv.
                $machine = if ($dl.key) { $dl.key -replace "_$([regex]::Escape([string]$dl.platform))$", '' }
                [pscustomobject]@{
                    platform        = $dl.platform
                    machine_name    = $machine
                    download_struct = @(foreach ($f in @($dl.downloadStruct)) {
                        if (-not $f) { continue }
                        [pscustomobject]@{
                            name = $f.name; file_size = $f.fileSize; md5 = $f.md5; sha1 = $f.sha1
                            url  = [pscustomobject]@{ web = $f.url.web }
                        }
                    })
                }
            })
            $machine = @($downloads.machine_name | Where-Object { $_ })[0]
            if (-not $machine) { $machine = ([string]$book.title).ToLowerInvariant() -replace '[^a-z0-9]', '' }
            [pscustomobject]@{
                machine_name      = $machine
                human_name        = $book.title
                entitlement_id    = $book.id
                available_until   = ConvertTo-IsoDate $book.unavailableAfter
                downloads         = $downloads
            }
        })
    }
}

Export-ModuleMember -Function Get-DownloadDeadline, Get-RemovalDecision, Find-ServerActionId, ConvertFrom-SignedUrlReply, Get-PagePayload, ConvertFrom-LibraryPage, ConvertFrom-PurchasePage, Get-DownloadPlan, Test-DownloadedFile, Get-BookFileType, Test-Library, Get-EpubIsbn, Compare-Library, ConvertTo-CalibreTag, Get-CalibrePlan
