BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\HumbleLibrary.psm1') -Force
    . (Join-Path $PSScriptRoot 'FakePage.ps1')

    # A purchase page (/home/library/<id>) shaped like Humble's, holding the given books. All IDs, titles,
    # file names and MD5s are made up.
    function New-PurchasePage([string]$Id, [string]$Bundle, [object[]]$Books) {
        $props = [ordered]@{
            userLibraryItem      = [ordered]@{
                id = "item-$Id"; title = $Bundle; itemType = 'content-entitlement'; type = 'bundle'
                entitlements = [ordered]@{ keys = @(); downloads = @($Books); redemptionGroups = @() }
            }
            productEntitlementId = $Id
            showDisclaimer       = $true
        }
        $page = '1:"$Sreact.fragment"' + "`n" +
            '78:I[200002,["$7"],"LibraryItemDetail"]' + "`n" +
            '13:["$","main",null,{"children":["$","$L78",null,' + (ConvertTo-Json $props -Depth 30 -Compress) + ']}]' + "`n"
        New-FakePage $page
    }
    function New-Book([string]$Id, [string]$Title, [string]$Machine, [object[]]$Files, [string]$Platform = 'ebook',
        [string]$Until = '2027-11-26T21:49:19.448Z') {
        [ordered]@{
            id = $Id; title = $Title; type = 'download_drm_free'; redemptionData = @{}
            downloads = @([ordered]@{ id = "dl-$Id"; key = "${Machine}_$Platform"; platform = $Platform; downloadStruct = @($Files) })
            signedUrls = '$undefined'; unavailableBefore = $null; unavailableAfter = $Until; expired = $false
        }
    }
    function New-BookFile([string]$Name, [string]$FileName, [string]$Md5, [long]$Bytes = 1000) {
        [ordered]@{
            id = 'f0'; arch = $null; fileSize = $Bytes; md5 = $Md5; name = $Name; sha1 = 'fakesha1'
            url = [ordered]@{ bittorrent = "$FileName.torrent"; web = $FileName }
        }
    }
}

Describe 'ConvertFrom-PurchasePage' {
    It 'turns a purchase page into an order of the old shape that Get-DownloadPlan plans as before' {
        $html = New-PurchasePage 'p-0001' 'Fake Linux Bundle' @(
            New-Book 'e-0001' 'The Fake Command Line' 'fakecommandline' @(
                New-BookFile 'PDF' 'fakecommandline.pdf' 'aaaa0001' 4242
                New-BookFile 'EPUB' 'fakecommandline.epub' 'aaaa0002' 2121))

        $order = ConvertFrom-PurchasePage -Html $html
        $plan = @(Get-DownloadPlan -Orders $order)

        $order.purchase_id | Should -Be 'p-0001'
        $order.product.human_name | Should -Be 'Fake Linux Bundle'
        $plan.File | Should -Be @('fakecommandline.pdf', 'fakecommandline.epub')
        ($plan | ForEach-Object Item) | Should -Be @('fakecommandline', 'fakecommandline')
        $plan.Format | Should -Be @('pdf', 'epub')
        $plan.Title | Should -Be @('The Fake Command Line', 'The Fake Command Line')
        $plan.Md5 | Should -Be @('aaaa0001', 'aaaa0002')
        $plan.Bytes | Should -Be @(4242, 2121)
        $plan.Url | Should -Be @('fakecommandline.pdf', 'fakecommandline.epub')
    }

    It 'gives each planned file what is needed to sign its link, and the book''s download deadline' {
        $html = New-PurchasePage 'p-0001' 'Fake Bundle' @(
            New-Book 'e-0001' 'Fake Book' 'fakebook' @(New-BookFile 'PDF' 'fakebook.pdf' 'aaaa0001') -Until '2027-03-01T10:00:00.000Z')

        $plan = @(Get-DownloadPlan -Orders (ConvertFrom-PurchasePage -Html $html))

        $plan[0].PurchaseId | Should -Be 'p-0001'
        $plan[0].EntitlementId | Should -Be 'e-0001'
        $plan[0].AvailableUntil | Should -Be '2027-03-01T10:00:00.000Z'
    }

    It 'plans a book in two bundles once, with both bundles and the later deadline' {
        $orders = @(
            ConvertFrom-PurchasePage -Html (New-PurchasePage 'p-0001' 'Fake Python Bundle' @(
                New-Book 'e-0001' 'Fake Python' 'fakepython' @(New-BookFile 'PDF' 'fakepython.pdf' 'same0001') -Until '2027-01-01T00:00:00.000Z'))
            ConvertFrom-PurchasePage -Html (New-PurchasePage 'p-0002' 'Fake Coding Bundle' @(
                New-Book 'e-0009' 'Fake Python' 'fakepython' @(New-BookFile 'PDF' 'fakepython.pdf' 'same0001') -Until '2027-06-01T00:00:00.000Z')))

        $plan = @(Get-DownloadPlan -Orders $orders)

        $plan.Count | Should -Be 1
        $plan[0].Bundles | Should -Be @('Fake Python Bundle', 'Fake Coding Bundle')
        $plan[0].AvailableUntil | Should -Be '2027-06-01T00:00:00.000Z'
    }

    It 'plans a file without an MD5 by its name and size, and a ZIP as a supplement' {
        $html = New-PurchasePage 'p-0001' 'Fake Bundle' @(
            New-Book 'e-0001' 'Fake Book' 'fakebook' @(
                New-BookFile 'PDF' 'fakebook.pdf' $null 777
                New-BookFile 'ZIP' 'fakebook_code.zip' 'aaaa0003'))

        $plan = @(Get-DownloadPlan -Orders (ConvertFrom-PurchasePage -Html $html))

        $plan.File | Should -Be @('fakebook.pdf', 'fakebook_code.zip')
        $plan[0].Md5 | Should -BeNullOrEmpty
        $plan[0].Bytes | Should -Be 777
        $plan[1].Format | Should -Be 'supplement'
    }

    It 'keeps the platform, so other platforms are planned only when asked for' {
        $html = New-PurchasePage 'p-0001' 'Fake Bundle' @(
            New-Book 'e-0001' 'Fake Book' 'fakebook' @(New-BookFile 'PDF' 'fakebook.pdf' 'aaaa0001')
            New-Book 'e-0002' 'Fake Audiobook' 'fakeaudio' @(New-BookFile 'MP3' 'fakeaudio.zip' 'aaaa0004') -Platform audio)
        $order = ConvertFrom-PurchasePage -Html $html

        (Get-DownloadPlan -Orders $order -Format pdf, mp3).File | Should -Be @('fakebook.pdf')
        (Get-DownloadPlan -Orders $order -Platform audio -Format mp3 | ForEach-Object Item) | Should -Be @('fakeaudio')
    }

    It 'recognizes files already downloaded with the old site''s links, by MD5' {
        $html = New-PurchasePage 'p-0001' 'Fake Bundle' @(
            New-Book 'e-0001' 'Fake Book' 'fakebook' @(New-BookFile 'PDF' 'fakebook.pdf' 'AAAA0001'))
        $manifest = @([pscustomobject]@{ file = 'fakebook.pdf'; md5 = 'aaaa0001'; item = 'fakebook'; format = 'pdf'; status = 'present' })

        (Get-DownloadPlan -Orders (ConvertFrom-PurchasePage -Html $html) -Manifest $manifest).Action | Should -Be @('skip')
    }

    It 'returns nothing for a page that has no purchase on it' {
        ConvertFrom-PurchasePage -Html (New-FakePage '1:"$Sreact.fragment"') | Should -BeNullOrEmpty
    }
}
