BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\HumbleLibrary.psm1') -Force
    Add-Type -AssemblyName System.IO.Compression

    function New-TestFile([string]$Name, [string]$Text) {
        $path = Join-Path $TestDrive $Name
        [IO.File]::WriteAllText($path, $Text)
        $path
    }
    # A zip whose entries are written in the given order (an EPUB's first entry is "mimetype").
    function New-TestZip([string]$Name, [hashtable[]]$Entries) {
        $path = Join-Path $TestDrive $Name
        $zip = [IO.Compression.ZipFile]::Open($path, 'Create')
        foreach ($e in $Entries) {
            $w = New-Object IO.StreamWriter($zip.CreateEntry($e.Name).Open())
            $w.Write($e.Text); $w.Dispose()
        }
        $zip.Dispose()
        $path
    }
}

Describe 'Get-BookFileType' {
    It 'recognises a complete PDF' {
        $path = New-TestFile 'whole.pdf' "%PDF-1.7`n1 0 obj`n<<>>`nendobj`ntrailer`n<<>>`n%%EOF`n"
        Get-BookFileType -Path $path | Should -Be 'pdf'
    }

    It 'returns nothing for a PDF that was cut off before its end marker' {
        $path = New-TestFile 'cut.pdf' "%PDF-1.7`n1 0 obj`n<<>>`nendo"
        Get-BookFileType -Path $path | Should -BeNullOrEmpty
    }

    It 'recognises an EPUB by its first entry, whatever the file is called' {
        $path = New-TestZip 'served_as.pdf' @(
            @{ Name = 'mimetype'; Text = 'application/epub+zip' }
            @{ Name = 'OEBPS/content.opf'; Text = '<package/>' })
        Get-BookFileType -Path $path | Should -Be 'epub'
    }

    It 'recognises any other complete zip as a zip' {
        $path = New-TestZip 'code.zip' @(@{ Name = 'chapter1/example.py'; Text = 'print("hi")' })
        Get-BookFileType -Path $path | Should -Be 'zip'
    }

    It 'returns nothing for a zip that was cut off (its index at the end is missing)' {
        $whole = New-TestZip 'whole.zip' @(@{ Name = 'a.txt'; Text = ('x' * 5000) })
        $bytes = [IO.File]::ReadAllBytes($whole)
        $path = Join-Path $TestDrive 'cut.zip'
        [IO.File]::WriteAllBytes($path, $bytes[0..($bytes.Length - 40)])
        Get-BookFileType -Path $path | Should -BeNullOrEmpty
    }
}
