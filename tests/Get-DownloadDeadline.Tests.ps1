BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\HumbleLibrary.psm1') -Force

    # A planned file, as Get-DownloadPlan gives it. Titles and names are made up.
    function New-PlanItem([string]$Item, [string]$Format, [string]$Until, [string]$Action = 'download') {
        [pscustomobject]@{ Action = $Action; File = "$Item.$Format"; Item = $Item; Format = $Format; Title = "Title of $Item"; AvailableUntil = $Until }
    }
    $script:now = [datetime]::new(2027, 1, 1, 12, 0, 0, [DateTimeKind]::Utc)
}

Describe 'Get-DownloadDeadline' {
    It 'lists each book not yet downloaded that Humble stops offering within 60 days, or already stopped, soonest first' {
        $plan = @(
            New-PlanItem 'soonbook' 'pdf' '2027-02-15T00:00:00.000Z'
            New-PlanItem 'soonbook' 'epub' '2027-02-15T00:00:00.000Z'
            New-PlanItem 'pastbook' 'pdf' '2026-12-01T00:00:00.000Z'
            New-PlanItem 'farbook' 'pdf' '2027-11-26T00:00:00.000Z'
            New-PlanItem 'nodatebook' 'pdf' $null)

        $due = @(Get-DownloadDeadline -Plan $plan -Now $now)

        ($due | ForEach-Object Item) | Should -Be @('pastbook', 'soonbook')
        $due.Title | Should -Be @('Title of pastbook', 'Title of soonbook')
        $due.AvailableUntil | Should -Be @('2026-12-01T00:00:00.000Z', '2027-02-15T00:00:00.000Z')
        $due.DaysLeft | Should -Be @(-31, 44)
    }

    It 'leaves out books already downloaded, including ones downloaded in this run' {
        $plan = @(
            New-PlanItem 'havebook' 'pdf' '2027-01-10T00:00:00.000Z' -Action skip
            New-PlanItem 'oldversion' 'pdf' '2027-01-10T00:00:00.000Z' -Action update-available
            New-PlanItem 'justgot' 'pdf' '2027-01-10T00:00:00.000Z'
            New-PlanItem 'missing' 'pdf' '2027-01-10T00:00:00.000Z')
        $manifest = @(
            [pscustomobject]@{ file = 'havebook.pdf'; status = 'present' }
            [pscustomobject]@{ file = 'oldversion.pdf'; status = 'present' }
            [pscustomobject]@{ file = 'justgot.pdf'; status = 'present' }
            [pscustomobject]@{ file = 'missing.pdf'; status = 'failed' })

        $due = @(Get-DownloadDeadline -Plan $plan -Manifest $manifest -Now $now)

        ($due | ForEach-Object Item) | Should -Be @('missing')
    }

    It 'warns about a book when only some of its files are downloaded' {
        $plan = @(
            New-PlanItem 'halfbook' 'pdf' '2027-01-10T00:00:00.000Z' -Action skip
            New-PlanItem 'halfbook' 'epub' '2027-01-10T00:00:00.000Z')
        $manifest = @([pscustomobject]@{ file = 'halfbook.pdf'; status = 'present' })

        $due = @(Get-DownloadDeadline -Plan $plan -Manifest $manifest -Now $now)

        ($due | ForEach-Object Item) | Should -Be @('halfbook')
    }
}
