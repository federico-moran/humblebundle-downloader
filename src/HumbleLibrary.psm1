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
                    if ($fmt -in 'supplement', 'download') { $fmt = 'supplement' }  # zips of code, disc contents, extras
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

Export-ModuleMember -Function Get-DownloadPlan
