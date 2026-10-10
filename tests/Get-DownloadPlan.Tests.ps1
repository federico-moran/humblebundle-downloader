BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\HumbleLibrary.psm1') -Force

    # Builds order data shaped like Humble's /api/v1/order/<gamekey> response. All keys and links are made up.
    function New-Order([string]$Bundle, [object[]]$Items, [string]$Gamekey = 'FAKEKEY1') {
        [pscustomobject]@{
            gamekey     = $Gamekey
            product     = [pscustomobject]@{ human_name = $Bundle; machine_name = ($Bundle -replace '\W', '').ToLower() }
            subproducts = @($Items)
        }
    }
    function New-Subproduct([string]$Title, [object[]]$Files, [string]$Platform = 'ebook') {
        [pscustomobject]@{
            machine_name = ($Title -replace '\W', '').ToLower()
            human_name   = $Title
            downloads    = @([pscustomobject]@{ platform = $Platform; download_struct = @($Files) })
        }
    }
    function New-File([string]$Name, [string]$FileName, [string]$Md5 = 'aaaa1111', [long]$Bytes = 1000) {
        [pscustomobject]@{
            name      = $Name
            url       = [pscustomobject]@{ web = "https://dl.example.test/$FileName`?gamekey=FAKE&ttl=1&t=sig" }
            md5       = $Md5
            file_size = $Bytes
        }
    }
}

Describe 'Get-DownloadPlan' {
    It 'plans one download for an order with one PDF, named after the file in its link' {
        $order = New-Order 'Linux Bundle' @(New-Subproduct 'The Linux Command Line' @(New-File 'PDF' 'linuxcommandline.pdf' 'abc123' 4242))

        $plan = @(Get-DownloadPlan -Orders $order)

        $plan.Count | Should -Be 1
        $plan[0].Action | Should -Be 'download'
        $plan[0].File | Should -Be 'linuxcommandline.pdf'
        $plan[0].Format | Should -Be 'pdf'
        $plan[0].Title | Should -Be 'The Linux Command Line'
        $plan[0].Bundles | Should -Be @('Linux Bundle')
        $plan[0].Md5 | Should -Be 'abc123'
        $plan[0].Bytes | Should -Be 4242
        $plan[0].Url | Should -Be 'https://dl.example.test/linuxcommandline.pdf?gamekey=FAKE&ttl=1&t=sig'
    }

    It 'plans PDF and EPUB but not MOBI by default' {
        $order = New-Order 'Bundle' @(New-Subproduct 'Book' @(
            New-File 'PDF' 'book.pdf' 'm1'
            New-File 'EPUB' 'book.epub' 'm2'
            New-File 'MOBI' 'book.mobi' 'm3'))

        (Get-DownloadPlan -Orders $order).File | Should -Be @('book.pdf', 'book.epub')
    }

    It 'plans only the formats asked for with -Format' {
        $order = New-Order 'Bundle' @(New-Subproduct 'Book' @(
            New-File 'PDF' 'book.pdf' 'm1'
            New-File 'MOBI' 'book.mobi' 'm3'))

        (Get-DownloadPlan -Orders $order -Format mobi).File | Should -Be @('book.mobi')
    }

    It 'treats files labelled Supplement or Download as the supplement format, planned by default' {
        $order = New-Order 'Bundle' @(New-Subproduct 'Book' @(
            New-File 'Supplement' 'book_code.zip' 'm1'
            New-File 'Download' 'book_dvd.zip' 'm2'))

        $plan = @(Get-DownloadPlan -Orders $order)

        $plan.File | Should -Be @('book_code.zip', 'book_dvd.zip')
        $plan.Format | Should -Be @('supplement', 'supplement')
    }

    It 'plans only ebooks by default, and other platforms when asked for with -Platform' {
        $order = New-Order 'Bundle' @(
            New-Subproduct 'Book' @(New-File 'PDF' 'book.pdf' 'm1')
            New-Subproduct 'Audiobook' @(New-File 'MP3' 'audiobook.zip' 'm2') -Platform audio)

        (Get-DownloadPlan -Orders $order -Format pdf, mp3).File | Should -Be @('book.pdf')
        (Get-DownloadPlan -Orders $order -Platform audio -Format mp3).File | Should -Be @('audiobook.zip')
    }

    It 'leaves out files that have no download link (external links only)' {
        $external = [pscustomobject]@{ name = 'PDF'; external_link = 'https://publisher.example.test/claim' }
        $order = New-Order 'Bundle' @(
            New-Subproduct 'Hosted elsewhere' @($external)
            New-Subproduct 'Book' @(New-File 'PDF' 'book.pdf' 'm1'))

        (Get-DownloadPlan -Orders $order).File | Should -Be @('book.pdf')
    }

    It 'plans a book bought in two bundles once, recording both bundles' {
        $orders = @(
            New-Order 'Python Bundle' @(New-Subproduct 'Python Crash Course' @(New-File 'PDF' 'pcc.pdf' 'same')) 'KEY1'
            New-Order 'Coding Bundle' @(New-Subproduct 'Python Crash Course' @(New-File 'PDF' 'pcc.pdf' 'same')) 'KEY2')

        $plan = @(Get-DownloadPlan -Orders $orders)

        $plan.Count | Should -Be 1
        $plan[0].Bundles | Should -Be @('Python Bundle', 'Coding Bundle')
    }
}
