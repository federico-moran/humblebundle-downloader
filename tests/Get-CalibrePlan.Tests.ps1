BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\HumbleLibrary.psm1') -Force

    function New-Row([string]$File, [string]$Md5, [string]$Bundles, [string]$Format = 'epub', [string]$Status = 'present', [string]$FileMd5 = '') {
        [pscustomobject]@{ file = $File; title = $File; format = $Format; bundles = $Bundles; md5 = $Md5; file_md5 = $FileMd5; status = $Status }
    }
}

Describe 'ConvertTo-CalibreTag' {
    It 'drops commas, which Calibre uses to separate tags' {
        ConvertTo-CalibreTag 'Humble Book Bundle: Game Dev, Design & Graphics by Mercury' |
            Should -Be 'Humble Book Bundle: Game Dev Design & Graphics by Mercury'
    }
}

Describe 'Get-CalibrePlan' {
    It 'adds EPUBs not in Calibre, tagged with the source and every bundle' {
        $plan = @(Get-CalibrePlan -Manifest @(New-Row 'a.epub' 'AAA' 'Bundle One; Bundle, Two'))

        $plan.Action | Should -Be 'add'
        $plan[0].Tags | Should -Be @('Humble Bundle', 'Bundle One', 'Bundle Two')
    }

    It 'leaves out PDFs, supplements and files that are not present' {
        $manifest = @(
            New-Row 'a.pdf' 'AAA' 'B' -Format 'pdf'
            New-Row 'a.zip' 'BBB' 'B' -Format 'supplement'
            New-Row 'gone.epub' 'CCC' 'B' -Status 'failed')

        @(Get-CalibrePlan -Manifest $manifest).Count | Should -Be 0
    }

    It 'skips a book already in Calibre with its tags, matched by MD5 in any case' {
        $in = @{ 'aaa' = @{ id = 7; tags = @('Humble Bundle', 'B', 'My own tag') } }

        $plan = Get-CalibrePlan -Manifest @(New-Row 'a.epub' 'AAA' 'B') -InCalibre $in

        $plan.Action | Should -Be 'skip'
        $plan.Id | Should -Be 7
    }

    It 'adds missing tags to a book already in Calibre, keeping its other tags' {
        $in = @{ 'aaa' = @{ id = 7; tags = @('My own tag') } }

        $plan = Get-CalibrePlan -Manifest @(New-Row 'a.epub' 'AAA' 'B') -InCalibre $in

        $plan.Action | Should -Be 'tag'
        $plan.Tags | Should -Be @('My own tag', 'Humble Bundle', 'B')
    }

    It 'recognises a file by its own MD5 when Humble''s was wrong' {
        $in = @{ 'fff' = @{ id = 3; tags = @('Humble Bundle', 'B') } }

        (Get-CalibrePlan -Manifest @(New-Row 'a.epub' 'AAA' 'B' -FileMd5 'FFF') -InCalibre $in).Action | Should -Be 'skip'
    }
}
