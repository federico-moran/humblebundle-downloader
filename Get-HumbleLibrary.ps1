#Requires -Version 7
<#
.SYNOPSIS
    Downloads the files you own on Humble Bundle, checking each one against Humble's own size and MD5.

.DESCRIPTION
    Uses your Humble session cookie, the one whose name starts with ory_session_. The first time, you are
    asked for its name and its value; both are saved encrypted for your Windows account (DPAPI) under
    %LOCALAPPDATA%\humblebundle-downloader, never in the repo. When the session expires, you are asked
    again. -ResetSession forgets it.

    Every run reads your library pages and saves humble-library.json (your purchases, in the shape of
    Humble's old order API) in the folder. Files are downloaded one at a time, smallest first, to
    <name>.part (an interrupted download resumes), checked against Humble's size and MD5, and only then
    given their real name and recorded in manifest.csv. A file that fails the check is downloaded once
    more, then recorded as failed so the next run retries it. Each book's download links are signed just
    before its first file is downloaded.

    Files already in the manifest are skipped. A new version of a book you have is reported, and downloaded
    only with -Update (the old copy is kept, renamed with the date). Files Humble no longer offers are kept
    and marked removed; if that would be more than 10 files, or every file of a bundle, none is marked
    unless you add -AcceptRemovals. Books you have not downloaded that Humble stops offering within 60
    days are listed at the end. Use -WhatIf to see the plan without downloading.

.EXAMPLE
    .\Get-HumbleLibrary.ps1 -WhatIf

.EXAMPLE
    .\Get-HumbleLibrary.ps1 -MaxDownloads 1

.EXAMPLE
    .\Get-HumbleLibrary.ps1 -Platform ebook, audio -Format pdf, epub, mp3

.EXAMPLE
    .\Get-HumbleLibrary.ps1 -VerifyOnly

.EXAMPLE
    .\Get-HumbleLibrary.ps1 -CompareWith "$env:USERPROFILE\OneDrive\Documents\Humble Bundle eBooks"
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Folder = (Join-Path $env:USERPROFILE 'OneDrive\Documents\HumbleBundle'),
    [string[]]$Platform = @('ebook'),
    [string[]]$Format = @('pdf', 'epub', 'cbz', 'supplement'),
    [switch]$Update,              # download new versions of books already downloaded
    [int]$MaxDownloads = [int]::MaxValue,
    [int]$DelaySeconds = 5,       # pause between downloads, to stay at a human pace
    [int]$Retries = 3,
    [switch]$VerifyOnly,          # check the folder against manifest.csv, without contacting Humble
    [string]$CompareWith,         # report which files in another folder are also in this library
    [switch]$ResetSession,        # forget the saved session cookie and ask for a new one
    [switch]$AcceptRemovals       # record removals even when there are many (see the description)
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src\HumbleLibrary.psm1') -Force

$manifestPath = Join-Path $Folder 'manifest.csv'
# md5 is Humble's, which identifies the file in its orders. When Humble's turns out wrong for the file it
# serves, file_md5 and bytes record what is really on disk (check = humble-md5-wrong).
# available_until: when Humble stops offering the book (a year after purchase, since 2026-11).
$columns = 'file', 'title', 'format', 'bundles', 'item', 'bytes', 'md5', 'file_md5', 'check', 'status', 'available_until', 'added', 'modified'
$manifest = @(if (Test-Path -LiteralPath $manifestPath) { Import-Csv -LiteralPath $manifestPath })

function Write-Table($Rows, [string[]]$Property) {
    Write-Host ($Rows | Format-Table $Property -AutoSize | Out-String -Width 300).TrimEnd()
}

# ---- Offline modes ----------------------------------------------------------------------------------
if ($VerifyOnly) {
    if (-not $manifest) { throw "No manifest.csv in $Folder." }
    $result = @(Test-Library -Folder $Folder -Manifest $manifest)
    Write-Host ('{0} files: {1}' -f $result.Count, (($result | Group-Object Status | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', '))
    $bad = @($result | Where-Object Status -ne 'ok')
    if ($bad) { Write-Table $bad File, Status }
    return
}
if ($CompareWith) {
    if (-not $manifest) { throw "No manifest.csv in $Folder." }
    $result = @(Compare-Library -Manifest $manifest -Library $Folder -Folder $CompareWith)
    Write-Host ('{0} files in {1}: {2}' -f $result.Count, $CompareWith, (($result | Group-Object Status | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', '))
    foreach ($s in 'only-there', 'same-title', 'same-isbn', 'identical') {
        $rows = @($result | Where-Object Status -eq $s)
        $note = if ($s -eq 'same-title') { ' (check by hand: different books can share a title)' }
        if ($rows) { Write-Host "`n$s$note"; Write-Table $rows Other, Ours }
    }
    return
}

# ---- Session cookie ---------------------------------------------------------------------------------
$site = 'https://www.humblebundle.com'
$sessionPath = Join-Path $env:LOCALAPPDATA 'humblebundle-downloader\session.xml'
if ($ResetSession -and (Test-Path -LiteralPath $sessionPath)) { Remove-Item -LiteralPath $sessionPath -WhatIf:$false }

function ConvertFrom-Secure($Secure) { [Net.NetworkCredential]::new('', $Secure).Password.Trim() }

# The cookie's name and value, as "name=value" for the Cookie header. Asks for them when none is saved
# (or the saved one is the old site's _simpleauth_sess) or with -Ask.
function Get-SessionCookie([switch]$Ask) {
    if (-not $Ask -and (Test-Path -LiteralPath $sessionPath)) {
        $saved = Import-Clixml -LiteralPath $sessionPath
        if ($saved -is [hashtable] -and $saved.Name -and $saved.Value) {
            return '{0}={1}' -f (ConvertFrom-Secure $saved.Name), (ConvertFrom-Secure $saved.Value)
        }
    }
    Write-Host 'Humble''s session cookie is needed: in your browser, logged in to humblebundle.com, press F12 >'
    Write-Host 'Application > Cookies > https://www.humblebundle.com and find the cookie whose name starts with ory_session_.'
    $name = (Read-Host 'Name of the cookie that starts with ory_session_').Trim()
    $value = ConvertFrom-Secure (Read-Host -AsSecureString 'Its value (not shown as you paste)')
    if ($value -match '^(ory_session_\w+)=(.*)$') { $name = $Matches[1]; $value = $Matches[2] }  # pasted as name=value
    if ($name -notlike 'ory_session_*' -or -not $value) { throw 'The cookie''s name must start with ory_session_, and its value can''t be empty.' }
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $sessionPath) -WhatIf:$false
    # Both encrypted for this Windows account (DPAPI).
    @{ Name = (ConvertTo-SecureString $name -AsPlainText -Force); Value = (ConvertTo-SecureString $value -AsPlainText -Force) } |
        Export-Clixml -LiteralPath $sessionPath -WhatIf:$false
    "$name=$value"
}
$script:cookie = Get-SessionCookie
$script:sessionRenewed = $false
$script:fatal = $null  # set when the run must stop
$deadSession = 'Humble did not accept the session. Check the cookie''s name in F12 > Application > Cookies (it starts with ory_session_).'
$siteChanged = 'Humble''s site has changed: the download action getSignedUrlsForEntitlements was not found. See docs/design.md.'

# A page of Humble's site as you, as text. Asks once for a new session when Humble no longer accepts it;
# retries on 429 and 5xx with growing waits. Errors name the page, never repeat it.
function Invoke-Page([string]$Path, [string]$Method = 'GET', [hashtable]$Headers = @{}, [string]$Body) {
    for ($attempt = 1; ; $attempt++) {
        $request = @{ Uri = "$site$Path"; Method = $Method; Headers = @{ Cookie = $script:cookie } + $Headers; SkipHttpErrorCheck = $true }
        if ($Body) { $request.Body = $Body; $request.ContentType = 'text/plain;charset=UTF-8' }
        try {
            $r = Invoke-WebRequest @request
        } catch {
            if ($attempt -le $Retries) { Write-Warning "  $($_.Exception.Message) - retrying in $(10 * $attempt) s"; Start-Sleep -Seconds (10 * $attempt); continue }
            throw "Humble's page $Path could not be read: $($_.Exception.Message)"
        }
        $code = [int]$r.StatusCode
        $text = if ($r.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($r.Content) } else { [string]$r.Content }
        $landed = $r.BaseResponse.RequestMessage.RequestUri
        if ($code -eq 401 -or ($landed -and $landed.Host -eq 'auth.humblebundle.com') -or $text -match '\\?"logged_in\\?":false') {
            if ($script:sessionRenewed) { $script:fatal = $deadSession; throw $deadSession }
            Write-Warning 'Humble did not accept the session cookie (it has expired, or you logged out).'
            $script:cookie = Get-SessionCookie -Ask
            $script:sessionRenewed = $true
            continue
        }
        if ($code -in 429, 500, 502, 503, 504 -and $attempt -le $Retries) { Start-Sleep -Seconds (10 * $attempt); continue }
        if ($code -eq 404) { throw "Humble's page $Path was not found (404): the site may have changed. See docs/design.md." }
        if ($code -eq 403) { throw "Humble refused $Path (403), probably a bot check. See docs/design.md for the browser fallback." }
        if ($code -ge 300) { throw "Humble answered $code for $Path. See docs/design.md." }
        return $text
    }
}

# ---- Purchases --------------------------------------------------------------------------------------
$null = New-Item -ItemType Directory -Force -Path $Folder -WhatIf:$false
$libraryHtml = Invoke-Page '/home/library'
if (-not (Get-PagePayload -Html $libraryHtml)) { throw "Humble's page /home/library has no data this tool can read. See docs/design.md." }
$purchases = @(ConvertFrom-LibraryPage -Html $libraryHtml)
if (-not $purchases) { throw "Humble's page /home/library lists no purchases this tool can read. See docs/design.md." }

$orders = New-Object Collections.Generic.List[object]
$firstPage = $null  # HTML of a purchase page, whose scripts name the download action
for ($i = 0; $i -lt $purchases.Count; $i++) {
    $p = $purchases[$i]
    Write-Progress -Activity 'Reading your Humble purchases' -Status "$($i + 1) of $($purchases.Count)" -PercentComplete (100 * $i / $purchases.Count)
    $html = Invoke-Page $p.Path
    $order = ConvertFrom-PurchasePage -Html $html
    if ($order) {
        if (-not $order.purchase_id) { $order.purchase_id = $p.Id }
        $orders.Add($order)
        if (-not $firstPage) { $firstPage = $html }
    } else {
        Write-Warning "Humble's page $($p.Path) ($($p.Title)) has no data this tool can read; skipped. See docs/design.md."
    }
    if ($i -lt $purchases.Count - 1) { Start-Sleep -Seconds 1 }
}
Write-Progress -Activity 'Reading your Humble purchases' -Completed
if (-not $orders.Count) { throw "None of Humble's purchase pages has data this tool can read: the site has changed. See docs/design.md." }

# humble-library.json: an old site's file (orders with gamekeys) is kept under its date, not overwritten.
$libraryPath = Join-Path $Folder 'humble-library.json'
if ((Test-Path -LiteralPath $libraryPath) -and (Select-String -LiteralPath $libraryPath -Pattern '"gamekey"' -SimpleMatch -Quiet)) {
    $kept = 'humble-library.{0:yyyy-MM-dd}.json' -f (Get-Item -LiteralPath $libraryPath).LastWriteTime
    Rename-Item -LiteralPath $libraryPath -NewName $kept -WhatIf:$false
    Write-Host "Kept the old site's humble-library.json as $kept."
}
ConvertTo-Json -InputObject $orders.ToArray() -Depth 30 |  # not @($orders): ConvertTo-Json fails on that
    Set-Content -LiteralPath $libraryPath -Encoding utf8NoBOM -WhatIf:$false
Write-Host "$($orders.Count) purchases read; saved humble-library.json."

# ---- Download links ---------------------------------------------------------------------------------
# The ID of the action that signs links, found by name in the site's scripts once per run (they need no cookie).
function Find-DownloadAction {
    # (Not ForEach-Object Value: under -WhatIf it outputs nothing.)
    $paths = [regex]::Matches($firstPage, '/_next/static/chunks/[\w.~-]+\.js').Value | Select-Object -Unique
    $scripts = foreach ($path in $paths) {
        try {
            $r = Invoke-WebRequest -Uri "$site$path"
            if ($r.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($r.Content) } else { [string]$r.Content }
        } catch { }  # one missing script doesn't matter unless it is the one
    }
    Find-ServerActionId -Script $scripts -Name getSignedUrlsForEntitlements
}
$script:actionId = Find-DownloadAction
if (-not $script:actionId) { throw $siteChanged }
$script:actionRefreshed = $false

$signed = @{}  # entitlement ID -> @{ Urls; ExpiresAt }, one book's links
function Get-SignedUrl($Item) {
    $s = $signed[$Item.EntitlementId]
    if (-not $s -or ($s.ExpiresAt -and $s.ExpiresAt -lt [datetime]::UtcNow.AddMinutes(10))) {
        $s = Request-SignedUrl $Item
        $signed[$Item.EntitlementId] = $s
    }
    $url = $s.Urls[$Item.Url]  # Url is the bare file name the page gives
    if (-not $url) { throw "Humble signed no link for $($Item.Url)." }
    $url
}
# Signs every link of the item's book (not recordDownload, not the bulk manifest). A reply that suggests the
# action ID is stale (Humble redeployed) makes it look the ID up again, once per run.
function Request-SignedUrl($Item) {
    for (; ; ) {
        try {
            $reply = Invoke-Page "/home/library/$($Item.PurchaseId)" -Method POST -Body ('[["{0}"]]' -f $Item.EntitlementId) `
                -Headers @{ 'Next-Action' = $script:actionId; Accept = 'text/x-component' }
            return ConvertFrom-SignedUrlReply -Text $reply
        } catch {
            $message = $_.Exception.Message
            if ($message -notlike '*not the reply*' -and $message -notlike '*(404)*') { throw }
            if ($script:actionRefreshed) { $script:fatal = $siteChanged; throw $siteChanged }
            $script:actionRefreshed = $true
            $script:actionId = Find-DownloadAction
            if (-not $script:actionId) { $script:fatal = $siteChanged; throw $siteChanged }
        }
    }
}

# ---- Plan -------------------------------------------------------------------------------------------
foreach ($row in $manifest) {  # recorded but deleted since: download again
    if ($row.status -eq 'present' -and -not (Test-Path -LiteralPath (Join-Path $Folder $row.file))) { $row.status = 'missing' }
}
$plan = @(Get-DownloadPlan -Orders $orders -Format $Format -Platform $Platform -Manifest $manifest -Update:$Update)
$removals = Get-RemovalDecision -Plan $plan -Manifest $manifest -AcceptRemovals:$AcceptRemovals
$todo = @($plan | Where-Object Action -in 'download', 'update' | Sort-Object Bytes | Select-Object -First $MaxDownloads)
$totalBytes = ($todo | Measure-Object Bytes -Sum).Sum
Write-Host ('Plan: {0}. This run: {1} files, {2:N1} GB.' -f
    (($plan | Group-Object Action | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', '), $todo.Count, ($totalBytes / 1GB))

$rows = [ordered]@{}  # file -> manifest row
foreach ($r in $manifest) { $rows[$r.file] = $r }
function Save-Manifest {
    if ($WhatIfPreference) { return }
    $rows.Values | Select-Object $columns | Export-Csv -LiteralPath $manifestPath -Encoding utf8BOM -WhatIf:$false
}
function Set-Row($Item, [string]$Status, [string]$Check, [string]$File = $Item.File, [long]$Bytes = $Item.Bytes, [string]$FileMd5 = '') {
    $path = Join-Path $Folder $File
    $old = $rows[$Item.File]
    if ($File -ne $Item.File -and $old) { $rows.Remove($Item.File) }  # saved under another name (its real type)
    $rows[$File] = [pscustomobject]@{
        file = $File; title = $Item.Title; format = $Item.Format; bundles = ($Item.Bundles -join '; '); item = $Item.Item
        bytes = $Bytes; md5 = $Item.Md5; file_md5 = $FileMd5; check = $Check; status = $Status; available_until = $Item.AvailableUntil
        added = $(if ($old.added) { $old.added } else { (Get-Date).ToString('s') })
        modified = $(if (Test-Path -LiteralPath $path) { (Get-Item -LiteralPath $path).LastWriteTimeUtc.ToString('s') + 'Z' })
    }
}
foreach ($p in $plan | Where-Object Action -in 'skip', 'update-available') {
    $row = $rows[$p.File]
    if ($p.Action -eq 'skip') { $row.bundles = $p.Bundles -join '; '; $row.title = $p.Title }
    # Rows from manifests older than 2026-11 have no available_until column yet.
    $row | Add-Member -NotePropertyName available_until -NotePropertyValue $p.AvailableUntil -Force
}
foreach ($p in $removals.Record) { $rows[$p.File].status = 'removed' }
Save-Manifest

# ---- Download ---------------------------------------------------------------------------------------
# Downloads to the .part file, resuming what is there. Network errors are retried with growing waits;
# an expired link (403 or 410) makes the book's links be signed again.
# -Fresh: the caller deleted the .part, so a retry after a network error resumes only this download.
function Receive-File($Item, [string]$Part, [switch]$Fresh) {
    for ($attempt = 1; ; $attempt++) {
        if (-not $Fresh -and (Test-Path -LiteralPath $Part) -and (Get-Item -LiteralPath $Part).Length -ge $Item.Bytes) { return }
        try {
            $null = Invoke-WebRequest -Uri (Get-SignedUrl $Item) -OutFile $Part -Resume
            return
        } catch {
            if ($script:fatal -or $attempt -gt $Retries) { throw }
            $code = [int]$_.Exception.Response.StatusCode
            if ($code -in 403, 410) { $signed.Remove($Item.EntitlementId) }  # sign again
            Write-Warning "  $($_.Exception.Message) - retrying in $(10 * $attempt) s"
            Start-Sleep -Seconds (10 * $attempt)
        }
    }
}

$failed = New-Object Collections.Generic.List[object]
$sizeOnly = New-Object Collections.Generic.List[object]
$md5Wrong = New-Object Collections.Generic.List[object]
for ($n = 0; $n -lt $todo.Count; $n++) {
    $p = $todo[$n]
    if (-not $PSCmdlet.ShouldProcess(('{0} ({1:N1} MB, {2})' -f $p.File, ($p.Bytes / 1MB), $p.Title), $p.Action)) { continue }
    Write-Host ('({0}/{1}) {2}  {3:N1} MB' -f ($n + 1), $todo.Count, $p.File, ($p.Bytes / 1MB))
    $part = Join-Path $Folder "$($p.File).part"
    $check = ''; $fileMd5 = ''; $file = $p.File
    try {
        Receive-File $p $part  # resumes a .part left by an earlier run
        $check = Test-DownloadedFile -Path $part -Bytes $p.Bytes -Md5 $p.Md5
        if ($check -eq 'mismatch') {
            # Humble's size and MD5 are wrong for about 1 file in 8. Two fresh downloads that are identical and
            # complete show what the server really sends; two different ones mean a bad download.
            Write-Warning '  The file did not match Humble''s size and MD5; downloading it twice more to compare.'
            $hashes = foreach ($i in 1, 2) {
                Remove-Item -LiteralPath $part -ErrorAction SilentlyContinue
                Receive-File $p $part -Fresh
                if ((Test-DownloadedFile -Path $part -Bytes $p.Bytes -Md5 $p.Md5) -eq 'ok') { 'humble'; break }
                (Get-FileHash -LiteralPath $part -Algorithm MD5).Hash.ToLowerInvariant()
            }
            $type = Get-BookFileType -Path $part
            if ($hashes -contains 'humble') { $check = 'ok' }
            elseif ($hashes.Count -eq 2 -and $hashes[0] -eq $hashes[1] -and $type) {
                $check = 'humble-md5-wrong'; $fileMd5 = $hashes[1]
                # Saved with the extension of what it really is (Humble serves some EPUBs under .pdf links).
                $ext = [IO.Path]::GetExtension($p.File).TrimStart('.').ToLowerInvariant()
                if ($type -in 'pdf', 'epub' -and $ext -in 'pdf', 'epub' -and $type -ne $ext) {
                    $file = [IO.Path]::ChangeExtension($p.File, $type)
                    if ($rows[$file] -or (Test-Path -LiteralPath (Join-Path $Folder $file))) {
                        $file = [IO.Path]::ChangeExtension($p.File, "$($fileMd5.Substring(0, 6)).$type")
                    }
                    Write-Warning "  Humble serves this as .$ext but it is an $($type.ToUpper()): saved as $file"
                }
            } elseif (-not $type) { Write-Warning '  The downloads are incomplete or damaged.' }
            else { Write-Warning '  The two downloads differ.' }
        }
    } catch {
        Write-Warning "  $($_.Exception.Message)"
    }
    if ($check -notin 'ok', 'size-only', 'humble-md5-wrong') {
        $failed.Add($p)
        if (-not $rows[$p.File] -or $rows[$p.File].status -ne 'present') { Set-Row $p 'failed' 'mismatch' }
    } else {
        $target = Join-Path $Folder $file
        if ($p.Action -eq 'update' -and (Test-Path -LiteralPath $target)) {
            # Keep the old version, named with today's date.
            $kept = '{0}.{1}{2}' -f [IO.Path]::GetFileNameWithoutExtension($p.File), (Get-Date -Format 'yyyy-MM-dd'), [IO.Path]::GetExtension($p.File)
            Rename-Item -LiteralPath $target -NewName $kept
            $old = $rows[$p.File]; $old.file = $kept; $rows.Remove($p.File); $rows[$kept] = $old
        }
        Move-Item -LiteralPath $part -Destination $target -Force
        if ($fileMd5) { Set-Row $p 'present' $check -File $file -Bytes (Get-Item -LiteralPath $target).Length -FileMd5 $fileMd5 }
        else { Set-Row $p 'present' $check }
        if ($check -eq 'size-only') { $sizeOnly.Add($p) }
        if ($check -eq 'humble-md5-wrong') { $md5Wrong.Add($p) }
    }
    Save-Manifest
    if ($script:fatal) { break }
    if ($n -lt $todo.Count - 1) { Start-Sleep -Seconds $DelaySeconds }
}

# ---- Summary ----------------------------------------------------------------------------------------
Write-Host ''
$updates = @($plan | Where-Object Action -eq 'update-available')
$due = @(Get-DownloadDeadline -Plan $plan -Manifest @($rows.Values))
if ($updates) { Write-Host "$($updates.Count) books have a new version on Humble (run with -Update to download them):"; Write-Table $updates File, Title }
if ($removals.Record) { Write-Host "$(@($removals.Record).Count) files are no longer offered by Humble (kept, marked removed):"; Write-Table $removals.Record File }
if ($removals.HeldBack) {
    Write-Warning "$(@($removals.HeldBack).Count) files are no longer offered by Humble, too many to be sure (not marked removed):"
    Write-Table $removals.HeldBack File
    Write-Host 'Humble may still be migrating old orders; run again later, or add -AcceptRemovals to record them.'
}
if ($sizeOnly) { Write-Host "$($sizeOnly.Count) files were checked by size only (Humble gives no MD5 for them):"; Write-Table $sizeOnly File, Title }
if ($md5Wrong) { Write-Host "$($md5Wrong.Count) files differ from Humble's MD5 but came down identical twice and complete (kept; humble-md5-wrong):"; Write-Table $md5Wrong File, Title }
if ($failed) { Write-Warning "$($failed.Count) files failed (recorded as failed; the next run retries them):"; Write-Table $failed File, Title }
if ($due) {
    Write-Warning "$($due.Count) books are not downloaded yet and Humble stops offering them within 60 days (or already has):"
    Write-Table $due Title, AvailableUntil, DaysLeft
}
if ($script:fatal) { throw $script:fatal }
if (-not $WhatIfPreference) { Write-Host "Done: $($todo.Count - $failed.Count) of $($todo.Count) downloaded and checked. Manifest: $manifestPath" }
