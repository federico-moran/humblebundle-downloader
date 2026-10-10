BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\HumbleLibrary.psm1') -Force
    $helloMd5 = '5d41402abc4b2a76b9719d911017c592'  # MD5 of the 5 bytes "hello"
}

Describe 'Compare-Library' {
    BeforeEach {
        $other = Join-Path $TestDrive ([guid]::NewGuid())  # TestDrive is shared by the tests in a Describe
        $null = New-Item -ItemType Directory -Path $other
    }

    It 'reports a file in the other folder with the same content as identical, whatever its name' {
        $null = New-Item -ItemType Directory -Path (Join-Path $other 'HACKING 101')
        [IO.File]::WriteAllText((Join-Path $other 'HACKING 101\shellcoders_handbook.pdf'), 'hello')
        $manifest = @([pscustomobject]@{ file = 'shellcoder.pdf'; md5 = $helloMd5; title = "The Shellcoder's Handbook"; status = 'present' })

        $result = @(Compare-Library -Manifest $manifest -Folder $other)

        $result.Count | Should -Be 1
        $result[0].Other | Should -Be 'HACKING 101\shellcoders_handbook.pdf'
        $result[0].Status | Should -Be 'identical'
        $result[0].Ours | Should -Be 'shellcoder.pdf'
    }

    It 'reports a file that matches nothing here as only there' {
        [IO.File]::WriteAllText((Join-Path $other 'unique.pdf'), 'something else')
        $manifest = @([pscustomobject]@{ file = 'book.pdf'; md5 = $helloMd5; title = 'Book'; status = 'present' })

        $result = @(Compare-Library -Manifest $manifest -Folder $other)

        $result.Status | Should -Be @('only-there')
        $result.Ours | Should -Be @($null)
    }

    It 'reports a different file whose name matches one of our titles as a similar title' {
        [IO.File]::WriteAllText((Join-Path $other 'shellcoders_handbook_discovering_and_exploiting_security_holes.pdf'), 'an older printing')
        $manifest = @([pscustomobject]@{ file = 'shellcoder.pdf'; md5 = $helloMd5; status = 'present'
            title = "The Shellcoder's Handbook: Discovering and Exploiting Security Holes" })

        $result = @(Compare-Library -Manifest $manifest -Folder $other)

        $result.Status | Should -Be @('similar-title')
        $result.Ours | Should -Be @('shellcoder.pdf')
    }

    It 'takes titles from the other folder''s own manifest (the PacktPub library), and ignores its data files' {
        [IO.File]::WriteAllText((Join-Path $other '9781789951134.epub'), 'packt copy')
        [IO.File]::WriteAllText((Join-Path $other 'packt-library.json'), '{}')
        [IO.File]::WriteAllText((Join-Path $other 'skip.txt'), '')
        @([pscustomobject]@{ isbn = '9781789951134'; format = 'epub'; file = '9781789951134.epub'; title = 'Mastering Linux Security and Hardening' }) |
            Export-Csv -LiteralPath (Join-Path $other 'manifest.csv') -NoTypeInformation
        $manifest = @([pscustomobject]@{ file = 'mastering_linux_security.epub'; md5 = $helloMd5; status = 'present'
            title = 'Mastering Linux Security and Hardening' })

        $result = @(Compare-Library -Manifest $manifest -Folder $other)

        $result.Other | Should -Be @('9781789951134.epub')
        $result.Status | Should -Be @('similar-title')
    }
}
