BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\HumbleLibrary.psm1') -Force
    . (Join-Path $PSScriptRoot 'FakePage.ps1')
}

Describe 'ConvertFrom-LibraryPage' {
    It 'lists each purchase on the library page once, with the ID and path of its page' {
        # Rows shaped like Humble's /home/library payload. All IDs and titles are made up.
        $payload = @'
1:"$Sreact.fragment"
4:I[100001,["$7","$8"],"LibraryGrid"]
6:T2c,Some page text that spans
two lines and is not JSON
5:["$","nav",null,{"children":[{"id":"nav-home","title":"Home","href":"/home"}]}]
9:["$","$L4",null,{"items":[{"id":"item-0001","title":"Fake Python Bundle","itemType":"content-entitlement","type":"bundle","href":"/home/library/00000000-0000-4000-8000-000000000001"},{"id":"item-0002","title":"Fake Single Ebook","itemType":"content-entitlement","type":"product","href":"/home/library/00000000-0000-4000-8000-000000000002"}]}]
a:["$","$L4",null,{"recent":[{"id":"item-0001","title":"Fake Python Bundle","itemType":"content-entitlement","type":"bundle","href":"/home/library/00000000-0000-4000-8000-000000000001"}]}]
'@

        $purchases = @(ConvertFrom-LibraryPage -Html (New-FakePage $payload))

        $purchases.Id | Should -Be @('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002')
        $purchases.Title | Should -Be @('Fake Python Bundle', 'Fake Single Ebook')
        $purchases.Path | Should -Be @('/home/library/00000000-0000-4000-8000-000000000001', '/home/library/00000000-0000-4000-8000-000000000002')
    }

    It 'uses the item''s own ID for the path when it has no link' {
        $payload = '3:{"items":[{"id":"00000000-0000-4000-8000-000000000003","title":"Fake Bundle","itemType":"content-entitlement","type":"bundle"}]}'

        $purchase = ConvertFrom-LibraryPage -Html (New-FakePage $payload)

        $purchase.Path | Should -Be '/home/library/00000000-0000-4000-8000-000000000003'
    }

    It 'returns nothing for a page with no purchases' {
        ConvertFrom-LibraryPage -Html (New-FakePage '1:"$Sreact.fragment"') | Should -BeNullOrEmpty
    }
}
