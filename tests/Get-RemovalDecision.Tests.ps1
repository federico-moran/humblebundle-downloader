BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\HumbleLibrary.psm1') -Force

    # Manifest rows of downloaded files, in a made-up bundle, and the plan items marking some removed.
    function New-Rows([string]$Bundle, [int]$Count, [string]$Prefix = 'book') {
        1..$Count | ForEach-Object { [pscustomobject]@{ file = "$Prefix$_.pdf"; md5 = "md5$Prefix$_"; bundles = $Bundle; status = 'present' } }
    }
    function New-Removed([object[]]$Rows) {
        $Rows | ForEach-Object { [pscustomobject]@{ Action = 'removed'; File = $_.file; Md5 = $_.md5 } }
    }
}

Describe 'Get-RemovalDecision' {
    It 'records up to 10 removals' {
        $manifest = @(New-Rows 'Big Fake Bundle' 30)
        $plan = @(
            [pscustomobject]@{ Action = 'skip'; File = 'book30.pdf' }
            New-Removed $manifest[0..9])

        $decision = Get-RemovalDecision -Plan $plan -Manifest $manifest

        $decision.Record.File | Should -Be @(1..10 | ForEach-Object { "book$_.pdf" })
        $decision.HeldBack | Should -BeNullOrEmpty
    }

    It 'holds back all of them when there are more than 10' {
        $manifest = @(New-Rows 'Big Fake Bundle' 30)

        $decision = Get-RemovalDecision -Plan (New-Removed $manifest[0..10]) -Manifest $manifest

        $decision.Record | Should -BeNullOrEmpty
        $decision.HeldBack.Count | Should -Be 11
    }

    It 'holds back all of them when they are every file of a bundle' {
        $manifest = @(
            New-Rows 'Big Fake Bundle' 30
            New-Rows 'Small Fake Bundle' 2 -Prefix 'small'
            [pscustomobject]@{ file = 'shared.pdf'; md5 = 'md5shared'; bundles = 'Small Fake Bundle; Big Fake Bundle'; status = 'present' })
        $gone = @($manifest | Where-Object { $_.file -in 'book1.pdf', 'small1.pdf', 'small2.pdf', 'shared.pdf' })

        $decision = Get-RemovalDecision -Plan (New-Removed $gone) -Manifest $manifest

        $decision.Record | Should -BeNullOrEmpty
        $decision.HeldBack.File | Should -Be @('book1.pdf', 'small1.pdf', 'small2.pdf', 'shared.pdf')
    }

    It 'ignores files already marked removed when judging a whole bundle' {
        $manifest = @(
            New-Rows 'Fake Bundle' 2
            [pscustomobject]@{ file = 'old.pdf'; md5 = 'md5old'; bundles = 'Fake Bundle'; status = 'removed' })

        $decision = Get-RemovalDecision -Plan (New-Removed $manifest[0]) -Manifest $manifest

        $decision.Record.File | Should -Be @('book1.pdf')
    }

    It 'records every removal with -AcceptRemovals' {
        $manifest = @(New-Rows 'Big Fake Bundle' 30)

        $decision = Get-RemovalDecision -Plan (New-Removed $manifest) -Manifest $manifest -AcceptRemovals

        $decision.Record.Count | Should -Be 30
        $decision.HeldBack | Should -BeNullOrEmpty
    }
}
