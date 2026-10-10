BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\HumbleLibrary.psm1') -Force
    $helloMd5 = '5d41402abc4b2a76b9719d911017c592'  # MD5 of the 5 bytes "hello"
}

Describe 'Test-Library' {
    It 'reports each manifest file as ok, changed or missing, and lists unfinished .part files' {
        $folder = Join-Path $TestDrive 'library'
        $null = New-Item -ItemType Directory -Path $folder
        [IO.File]::WriteAllText((Join-Path $folder 'good.pdf'), 'hello')
        [IO.File]::WriteAllText((Join-Path $folder 'damaged.pdf'), 'hellp')   # same size, different content
        [IO.File]::WriteAllText((Join-Path $folder 'next.epub.part'), 'hel')
        $manifest = @(
            [pscustomobject]@{ file = 'good.pdf'; md5 = $helloMd5; bytes = '5'; status = 'present' }
            [pscustomobject]@{ file = 'damaged.pdf'; md5 = $helloMd5; bytes = '5'; status = 'present' }
            [pscustomobject]@{ file = 'lost.pdf'; md5 = $helloMd5; bytes = '5'; status = 'present' })

        $result = @(Test-Library -Folder $folder -Manifest $manifest)

        ($result | Where-Object File -eq 'good.pdf').Status | Should -Be 'ok'
        ($result | Where-Object File -eq 'damaged.pdf').Status | Should -Be 'changed'
        ($result | Where-Object File -eq 'lost.pdf').Status | Should -Be 'missing'
        ($result | Where-Object File -eq 'next.epub.part').Status | Should -Be 'unfinished'
        $result.Count | Should -Be 4
    }

    It 'checks a file accepted despite a wrong Humble MD5 against its own size and MD5' {
        $folder = Join-Path $TestDrive 'accepted'
        $null = New-Item -ItemType Directory -Path $folder
        [IO.File]::WriteAllText((Join-Path $folder 'book.pdf'), 'hello')
        $manifest = @([pscustomobject]@{ file = 'book.pdf'; md5 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; file_md5 = $helloMd5
            bytes = '5'; check = 'humble-md5-wrong'; status = 'present' })

        (Test-Library -Folder $folder -Manifest $manifest).Status | Should -Be 'ok'
    }
}
