# Logic for Get-HumbleLibrary.ps1, kept free of network calls so it can be tested.

# What to do with each file in the orders: one item per file, with the action to take.
function Get-DownloadPlan {
    param(
        [object[]]$Orders,
        [string[]]$Format = @('pdf', 'epub', 'cbz', 'supplement')
    )
    foreach ($order in $Orders) {
        foreach ($sub in $order.subproducts) {
            foreach ($dl in $sub.downloads) {
                foreach ($f in $dl.download_struct) {
                    $fmt = $f.name.ToLowerInvariant()
                    if ($fmt -in 'supplement', 'download') { $fmt = 'supplement' }  # zips of code, disc contents, extras
                    if ($fmt -notin $Format) { continue }
                    [pscustomobject]@{
                        Action  = 'download'
                        File    = [IO.Path]::GetFileName(([uri]$f.url.web).AbsolutePath)
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
}

Export-ModuleMember -Function Get-DownloadPlan
