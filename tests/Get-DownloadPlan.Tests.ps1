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

    It 'takes the file name from a bare file name in place of a link (the site rebuilt in 2026-11)' {
        $file = New-File 'PDF' 'unused.pdf' 'abc123'
        $file.url = [pscustomobject]@{ web = 'linuxcommandline.pdf' }
        $order = New-Order 'Linux Bundle' @(New-Subproduct 'The Linux Command Line' @($file))

        $plan = @(Get-DownloadPlan -Orders $order)

        $plan[0].File | Should -Be 'linuxcommandline.pdf'
        $plan[0].Url | Should -Be 'linuxcommandline.pdf'
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

    It 'treats files labeled Supplement or Download as the supplement format, planned by default' {
        $order = New-Order 'Bundle' @(New-Subproduct 'Book' @(
            New-File 'Supplement' 'book_code.zip' 'm1'
            New-File 'Download' 'book_dvd.zip' 'm2'))

        $plan = @(Get-DownloadPlan -Orders $order)

        $plan.File | Should -Be @('book_code.zip', 'book_dvd.zip')
        $plan.Format | Should -Be @('supplement', 'supplement')
    }

    It 'treats files labeled ZIP or .zip as supplements too (companion code, videos, disc contents)' {
        $order = New-Order 'Bundle' @(
            New-Subproduct 'Book' @(New-File 'ZIP' 'book_companion.zip' 'm1')
            New-Subproduct 'Book DVD' @(New-File '.zip' 'book_dvd.zip' 'm2'))

        (Get-DownloadPlan -Orders $order).Format | Should -Be @('supplement', 'supplement')
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

    It 'keeps both files when two different books share a file name, adding part of the MD5 to the second' {
        $orders = @(
            New-Order 'Bundle A' @(New-Subproduct 'Guide to X' @(New-File 'PDF' 'guide.pdf' '3f2a9c11')) 'KEY1'
            New-Order 'Bundle B' @(New-Subproduct 'Guide to Y' @(New-File 'PDF' 'guide.pdf' '7b8e0d22')) 'KEY2')

        (Get-DownloadPlan -Orders $orders).File | Should -Be @('guide.pdf', 'guide.7b8e0d.pdf')
    }

    Context 'with a manifest of earlier downloads' {
        It 'skips a file already downloaded with the same MD5' {
            $order = New-Order 'Bundle' @(New-Subproduct 'Book' @(New-File 'PDF' 'book.pdf' 'm1'))
            $manifest = @([pscustomobject]@{ file = 'book.pdf'; md5 = 'm1'; status = 'present' })

            $plan = @(Get-DownloadPlan -Orders $order -Manifest $manifest)

            $plan.Action | Should -Be @('skip')
        }

        It 'reports a new version of a downloaded book as an update, and plans it only with -Update' {
            $order = New-Order 'Bundle' @(New-Subproduct 'Book' @(New-File 'PDF' 'book.pdf' 'new5678'))
            $manifest = @([pscustomobject]@{ file = 'book.pdf'; md5 = 'old1234'; item = 'book'; format = 'pdf'; status = 'present' })

            $report = @(Get-DownloadPlan -Orders $order -Manifest $manifest)
            $update = @(Get-DownloadPlan -Orders $order -Manifest $manifest -Update)

            $report.Action | Should -Be @('update-available')
            $report.File | Should -Be @('book.pdf')
            $update.Action | Should -Be @('update')
        }

        It 'still adds an MD5 suffix when a different book uses a downloaded file''s name' {
            $order = New-Order 'Bundle' @(New-Subproduct 'Other Book' @(New-File 'PDF' 'book.pdf' 'new5678'))
            $manifest = @([pscustomobject]@{ file = 'book.pdf'; md5 = 'old1234'; item = 'book'; format = 'pdf'; status = 'present' })

            $plan = @(Get-DownloadPlan -Orders $order -Manifest $manifest | Where-Object Action -eq 'download')

            $plan.File | Should -Be @('book.new567.pdf')
        }

        It 'marks a downloaded file that Humble no longer offers as removed' {
            $order = New-Order 'Bundle' @(New-Subproduct 'Book' @(New-File 'PDF' 'book.pdf' 'm1'))
            $manifest = @(
                [pscustomobject]@{ file = 'book.pdf'; md5 = 'm1'; item = 'book'; format = 'pdf'; status = 'present' }
                [pscustomobject]@{ file = 'gone.pdf'; md5 = 'm9'; item = 'gone'; format = 'pdf'; status = 'present' })

            $plan = @(Get-DownloadPlan -Orders $order -Manifest $manifest)

            ($plan | Where-Object File -eq 'gone.pdf').Action | Should -Be 'removed'
        }

        It 'does not mark a file removed when this run''s -Format leaves it out' {
            $order = New-Order 'Bundle' @(New-Subproduct 'Book' @(
                New-File 'PDF' 'book.pdf' 'm1'
                New-File 'MOBI' 'book.mobi' 'm2'))
            $manifest = @([pscustomobject]@{ file = 'book.pdf'; md5 = 'm1'; item = 'book'; format = 'pdf'; status = 'present' })

            $plan = @(Get-DownloadPlan -Orders $order -Manifest $manifest -Format mobi)

            $plan.File | Should -Be @('book.mobi')
        }
    }
}
