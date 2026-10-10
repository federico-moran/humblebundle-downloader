BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\HumbleLibrary.psm1') -Force
    $helloMd5 = '5d41402abc4b2a76b9719d911017c592'  # MD5 of the 5 bytes "hello"
}

Describe 'Test-DownloadedFile' {
    BeforeEach {
        $path = Join-Path $TestDrive 'book.pdf.part'
        [IO.File]::WriteAllText($path, 'hello')
    }

    It 'is ok when the size and MD5 match' {
        Test-DownloadedFile -Path $path -Bytes 5 -Md5 $helloMd5 | Should -Be 'ok'
    }

    It 'is a mismatch when the size differs (a cut-off download)' {
        Test-DownloadedFile -Path $path -Bytes 6 -Md5 $helloMd5 | Should -Be 'mismatch'
    }

    It 'is a mismatch when the size matches but the MD5 does not' {
        Test-DownloadedFile -Path $path -Bytes 5 -Md5 '00000000000000000000000000000000' | Should -Be 'mismatch'
    }

    It 'is size-only when Humble gives no MD5 and the size matches' {
        Test-DownloadedFile -Path $path -Bytes 5 -Md5 '' | Should -Be 'size-only'
    }
}
