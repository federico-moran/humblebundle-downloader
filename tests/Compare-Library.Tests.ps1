BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\HumbleLibrary.psm1') -Force
    Add-Type -AssemblyName System.IO.Compression
    $helloMd5 = '5d41402abc4b2a76b9719d911017c592'  # MD5 of the 5 bytes "hello"

    # An EPUB with the given ISBNs in its package file. $Text makes copies of the same book differ in content.
    function New-TestEpub([string]$Path, [string[]]$Isbn, [string]$Text = '') {
        $zip = [IO.Compression.ZipFile]::Open($Path, 'Create')
        $ids = ($Isbn | ForEach-Object { "<dc:identifier>urn:isbn:$_</dc:identifier>" }) -join ''
        $entries = [ordered]@{
            'mimetype'               = 'application/epub+zip'
            'META-INF/container.xml' = '<container><rootfiles><rootfile full-path="content.opf"/></rootfiles></container>'
            'content.opf'            = "<package><metadata>$ids</metadata></package>"
            'text.html'              = $Text
        }
        foreach ($e in $entries.GetEnumerator()) {
            $w = New-Object IO.StreamWriter($zip.CreateEntry($e.Key).Open())
            $w.Write($e.Value); $w.Dispose()
        }
        $zip.Dispose()
    }
}

Describe 'Compare-Library' {
    BeforeEach {
        # TestDrive is shared by the tests in a Describe
        $ours = Join-Path $TestDrive ([guid]::NewGuid())
        $other = Join-Path $TestDrive ([guid]::NewGuid())
        $null = New-Item -ItemType Directory -Path $ours, $other
    }

    It 'reports a file in the other folder with the same content as identical, whatever its name' {
        $null = New-Item -ItemType Directory -Path (Join-Path $other 'HACKING 101')
        [IO.File]::WriteAllText((Join-Path $other 'HACKING 101\shellcoders_handbook.pdf'), 'hello')
        $manifest = @([pscustomobject]@{ file = 'shellcoder.pdf'; md5 = $helloMd5; title = "The Shellcoder's Handbook"; status = 'present' })

        $result = @(Compare-Library -Manifest $manifest -Library $ours -Folder $other)

        $result.Count | Should -Be 1
        $result[0].Other | Should -Be 'HACKING 101\shellcoders_handbook.pdf'
        $result[0].Status | Should -Be 'identical'
        $result[0].Ours | Should -Be 'shellcoder.pdf'
    }

    It 'recognizes an identical file by its own MD5 when Humble''s MD5 for it was wrong' {
        [IO.File]::WriteAllText((Join-Path $other 'old_copy.pdf'), 'hello')
        $manifest = @([pscustomobject]@{ file = 'book.pdf'; md5 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; file_md5 = $helloMd5
            title = 'Book'; status = 'present' })

        (Compare-Library -Manifest $manifest -Library $ours -Folder $other).Status | Should -Be 'identical'
    }

    It 'reports a file that matches nothing here as only there' {
        [IO.File]::WriteAllText((Join-Path $other 'unique.pdf'), 'something else')
        $manifest = @([pscustomobject]@{ file = 'book.pdf'; md5 = $helloMd5; title = 'Book'; status = 'present' })

        $result = @(Compare-Library -Manifest $manifest -Library $ours -Folder $other)

        $result.Status | Should -Be @('only-there')
        $result.Ours | Should -Be @($null)
    }

    It 'reports a different EPUB with one of the ISBNs in ours as the same ISBN, whatever its title' {
        New-TestEpub (Join-Path $ours 'hacking.epub') '9781593271442', '9781593271459'
        New-TestEpub (Join-Path $other 'Hacking - 2nd ed.epub') '9781593271459' -Text 'another printing'
        $manifest = @([pscustomobject]@{ file = 'hacking.epub'; item = 'hacking'; format = 'epub'; md5 = $helloMd5; status = 'present'
            title = 'Hacking: The Art of Exploitation' })

        $result = @(Compare-Library -Manifest $manifest -Library $ours -Folder $other)

        $result.Status | Should -Be @('same-isbn')
        $result.Ours | Should -Be @('hacking.epub')
    }

    It 'takes ISBNs from the other folder''s own manifest (the PacktPub library), and ignores its data files' {
        New-TestEpub (Join-Path $ours 'mastering_linux.epub') '9781789951134'
        [IO.File]::WriteAllText((Join-Path $other '9781789951134.pdf'), 'packt pdf')
        [IO.File]::WriteAllText((Join-Path $other 'packt-library.json'), '{}')
        [IO.File]::WriteAllText((Join-Path $other 'skip.txt'), '')
        @([pscustomobject]@{ isbn = '9781789951134'; format = 'pdf'; file = '9781789951134.pdf'; title = 'Linux Security' }) |
            Export-Csv -LiteralPath (Join-Path $other 'manifest.csv') -NoTypeInformation
        $manifest = @(
            [pscustomobject]@{ file = 'mastering_linux.epub'; item = 'mastering_linux'; format = 'epub'; md5 = 'a' * 32; status = 'present'
                title = 'Mastering Linux Security and Hardening' }
            [pscustomobject]@{ file = 'mastering_linux.pdf'; item = 'mastering_linux'; format = 'pdf'; md5 = 'b' * 32; status = 'present'
                title = 'Mastering Linux Security and Hardening' })

        $result = @(Compare-Library -Manifest $manifest -Library $ours -Folder $other)

        $result.Other | Should -Be @('9781789951134.pdf')
        $result.Status | Should -Be @('same-isbn')
        $result.Ours | Should -Be @('mastering_linux.pdf')  # our copy in the same format, found through its EPUB
    }

    It 'takes the ISBN of a file named by its ISBN, or of the EPUB beside it with the same name' {
        New-TestEpub (Join-Path $ours 'gns3.epub') '9781782160809'
        [IO.File]::WriteAllText((Join-Path $other '978-1-78216-080-9.pdf'), 'named by isbn')
        [IO.File]::WriteAllText((Join-Path $other 'gns3_guide.pdf'), 'old pdf')
        New-TestEpub (Join-Path $other 'gns3_guide.epub') '9781782160809' -Text 'old epub'
        $manifest = @([pscustomobject]@{ file = 'gns3.epub'; item = 'gns3'; format = 'epub'; md5 = $helloMd5; status = 'present'
            title = 'GNS3 Network Simulation Guide' })

        $result = @(Compare-Library -Manifest $manifest -Library $ours -Folder $other | Sort-Object Other)

        $result.Other | Should -Be @('978-1-78216-080-9.pdf', 'gns3_guide.epub', 'gns3_guide.pdf')
        $result.Status | Should -Be @('same-isbn', 'same-isbn', 'same-isbn')
    }

    It 'reports a different file whose name is exactly one of our titles as the same title, to check by hand' {
        [IO.File]::WriteAllText((Join-Path $other 'shellcoders_handbook_discovering_and_exploiting_security_holes.pdf'), 'an older printing')
        $manifest = @([pscustomobject]@{ file = 'shellcoder.pdf'; md5 = $helloMd5; status = 'present'
            title = "The Shellcoder's Handbook: Discovering and Exploiting Security Holes" })

        $result = @(Compare-Library -Manifest $manifest -Library $ours -Folder $other)

        $result.Status | Should -Be @('same-title')
        $result.Ours | Should -Be @('shellcoder.pdf')
    }

    It 'does not match a short title that is only part of a longer one' {
        # No Starch's "Penetration Testing" once matched 40 Packt titles this way.
        [IO.File]::WriteAllText((Join-Path $other 'Learning Penetration Testing with Python.pdf'), 'packt')
        $manifest = @([pscustomobject]@{ file = 'penetrationtesting.pdf'; md5 = $helloMd5; status = 'present'; title = 'Penetration Testing' })

        (Compare-Library -Manifest $manifest -Library $ours -Folder $other).Status | Should -Be 'only-there'
    }
}
