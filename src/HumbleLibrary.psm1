# Logic for Get-HumbleLibrary.ps1, kept free of network calls so it can be tested.

# What to do with each file in the orders: one item per file, with the action to take.
# A file offered in several bundles (same MD5) is planned once, with every bundle recorded.
function Get-DownloadPlan {
    [CmdletBinding()]
    param(
        [object[]]$Orders,
        [string[]]$Format = @('pdf', 'epub', 'cbz', 'supplement'),
        [string[]]$Platform = @('ebook')
    )
    $plan = [ordered]@{}  # md5 (or file name and size, when Humble gives no MD5) -> item
    foreach ($order in $Orders) {
        foreach ($sub in $order.subproducts) {
            foreach ($dl in $sub.downloads) {
                if ($dl.platform -notin $Platform) { continue }
                foreach ($f in $dl.download_struct) {
                    $fmt = $f.name.ToLowerInvariant()
                    if ($fmt -in 'supplement', 'download') { $fmt = 'supplement' }  # zips of code, disc contents, extras
                    if ($fmt -notin $Format -or -not $f.url.web) { continue }  # no link: hosted elsewhere
                    $file = [IO.Path]::GetFileName(([uri]$f.url.web).AbsolutePath)
                    $key = if ($f.md5) { $f.md5.ToLowerInvariant() } else { "$file|$($f.file_size)" }
                    if ($plan.Contains($key)) {
                        $plan[$key].Bundles += $order.product.human_name
                        continue
                    }
                    $plan[$key] = [pscustomobject]@{
                        Action  = 'download'
                        File    = $file
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
}

Export-ModuleMember -Function Get-DownloadPlan
