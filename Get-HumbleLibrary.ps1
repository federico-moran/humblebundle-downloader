<#
.SYNOPSIS
    Downloads the files you own on Humble Bundle, checking each one against Humble's own size and MD5.

.DESCRIPTION
    Uses your Humble session cookie (_simpleauth_sess). The first time, paste it when asked; it is saved
    encrypted for your Windows account (DPAPI) under %LOCALAPPDATA%\humblebundle-downloader, never in the
    repo. When it expires, you are asked again. -ResetSession forgets it.

    Every run saves humble-library.json (all your orders as Humble returns them) in the folder. Files are
    downloaded one at a time, smallest first, to <name>.part (an interrupted download resumes), checked
    against Humble's size and MD5, and only then given their real name and recorded in manifest.csv.
    A file that fails the check is downloaded once more, then recorded as failed so the next run retries it.

    Files already in the manifest are skipped. A new version of a book you have is reported, and downloaded
    only with -Update (the old copy is kept, renamed with the date). Files Humble no longer offers are kept
    and marked removed. Use -WhatIf to see the plan without downloading.

    The folder and humble-library.json contain your order keys, which open your download pages: don't share them.

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
    [switch]$ResetSession         # forget the saved session cookie and ask for a new one
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src\HumbleLibrary.psm1') -Force

$manifestPath = Join-Path $Folder 'manifest.csv'
# md5 is Humble's, which identifies the file in its orders. When Humble's turns out wrong for the file it
# serves, file_md5 and bytes record what is really on disk (check = humble-md5-wrong).
$columns = 'file', 'title', 'format', 'bundles', 'item', 'bytes', 'md5', 'file_md5', 'check', 'status', 'added', 'modified'
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
    $result = @(Compare-Library -Manifest $manifest -Folder $CompareWith)
    Write-Host ('{0} files in {1}: {2}' -f $result.Count, $CompareWith, (($result | Group-Object Status | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', '))
    foreach ($s in 'only-there', 'similar-title', 'identical') {
        $rows = @($result | Where-Object Status -eq $s)
        if ($rows) { Write-Host "`n$s"; Write-Table $rows Other, Ours }
    }
    return
}

# ---- Session cookie ---------------------------------------------------------------------------------
$sessionPath = Join-Path $env:LOCALAPPDATA 'humblebundle-downloader\session.xml'
if ($ResetSession -and (Test-Path -LiteralPath $sessionPath)) { Remove-Item -LiteralPath $sessionPath -WhatIf:$false }

function Get-SessionCookie([switch]$Ask) {
    if (-not $Ask -and (Test-Path -LiteralPath $sessionPath)) {
        $secure = Import-Clixml -LiteralPath $sessionPath
    } else {
        Write-Host 'Paste the value of the _simpleauth_sess cookie: in your browser, logged in to humblebundle.com,'
        Write-Host 'press F12 > Application > Cookies > https://www.humblebundle.com. It is not shown as you paste.'
        $secure = Read-Host -AsSecureString 'Session cookie'
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $sessionPath) -WhatIf:$false
        $secure | Export-Clixml -LiteralPath $sessionPath -WhatIf:$false  # encrypted for this Windows account (DPAPI)
    }
    [Net.NetworkCredential]::new('', $secure).Password.Trim() -replace '^_simpleauth_sess=', ''
}
$script:cookie = Get-SessionCookie

# Calls Humble's API as you. Asks for the cookie again if Humble no longer accepts it.
function Invoke-Humble([string]$Path) {
    for ($attempt = 1; ; $attempt++) {
        try {
            return Invoke-RestMethod -Uri "https://www.humblebundle.com$Path" -Headers @{ Cookie = "_simpleauth_sess=$script:cookie" }
        } catch {
            $code = [int]$_.Exception.Response.StatusCode
            if ($code -eq 401 -and $attempt -eq 1) {
                Write-Warning 'Humble did not accept the session cookie (it has expired, or you logged out).'
                $script:cookie = Get-SessionCookie -Ask
                continue
            }
            if ($code -eq 403) { throw "Humble refused the request (403), probably a bot check. See docs/design.md for the browser fallback." }
            if ($code -in 429, 500, 502, 503, 504 -and $attempt -le $Retries) { Start-Sleep -Seconds (10 * $attempt); continue }
            throw
        }
    }
}

# ---- Orders -----------------------------------------------------------------------------------------
$null = New-Item -ItemType Directory -Force -Path $Folder -WhatIf:$false
$keys = @((Invoke-Humble '/api/v1/user/order').gamekey)
$orders = New-Object Collections.Generic.List[object]
$fetchedAt = @{}  # gamekey -> when its download links were signed
for ($i = 0; $i -lt $keys.Count; $i++) {
    Write-Progress -Activity 'Reading your Humble orders' -Status "$($i + 1) of $($keys.Count)" -PercentComplete (100 * $i / $keys.Count)
    $orders.Add((Invoke-Humble "/api/v1/order/$($keys[$i])?all_tpkds=true"))
    $fetchedAt[$keys[$i]] = Get-Date
    Start-Sleep -Seconds 1
}
Write-Progress -Activity 'Reading your Humble orders' -Completed
ConvertTo-Json -InputObject $orders.ToArray() -Depth 30 |  # not @($orders): ConvertTo-Json fails on that
    Set-Content -LiteralPath (Join-Path $Folder 'humble-library.json') -Encoding utf8NoBOM -WhatIf:$false
Write-Host "$($orders.Count) orders read; saved humble-library.json."

# Where each file's link comes from, so an expired link can be signed again by reading its order again.
$source = @{}  # md5 (or file name) -> @{ gamekey; url }
function Update-Source($Order) {
    foreach ($sub in $Order.subproducts) { foreach ($dl in $sub.downloads) { foreach ($f in $dl.download_struct) {
        if (-not $f.url.web) { continue }
        $k = if ($f.md5) { $f.md5.ToLowerInvariant() } else { [IO.Path]::GetFileName(([uri]$f.url.web).AbsolutePath) }
        $source[$k] = @{ gamekey = $Order.gamekey; url = $f.url.web }
    } } }
}
foreach ($o in $orders) { Update-Source $o }

function Get-SourceKey($Item) {
    if ($Item.Md5) { $Item.Md5.ToLowerInvariant() } else { [IO.Path]::GetFileName(([uri]$Item.Url).AbsolutePath) }
}
function Get-FreshUrl($Item) {
    $k = Get-SourceKey $Item
    $s = $source[$k]
    if (((Get-Date) - $fetchedAt[$s.gamekey]).TotalMinutes -gt 30) {
        Update-Source (Invoke-Humble "/api/v1/order/$($s.gamekey)?all_tpkds=true")
        $fetchedAt[$s.gamekey] = Get-Date
    }
    $source[$k].url
}

# ---- Plan -------------------------------------------------------------------------------------------
foreach ($row in $manifest) {  # recorded but deleted since: download again
    if ($row.status -eq 'present' -and -not (Test-Path -LiteralPath (Join-Path $Folder $row.file))) { $row.status = 'missing' }
}
$plan = @(Get-DownloadPlan -Orders $orders -Format $Format -Platform $Platform -Manifest $manifest -Update:$Update)
$todo = @($plan | Where-Object Action -in 'download', 'update' | Sort-Object Bytes | Select-Object -First $MaxDownloads)
$totalBytes = ($todo | Measure-Object Bytes -Sum).Sum
Write-Host ('Plan: {0}. This run: {1} files, {2:N1} GB.' -f
    (($plan | Group-Object Action | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', '), $todo.Count, ($totalBytes / 1GB))

$rows = [ordered]@{}  # file -> manifest row
foreach ($r in $manifest) { $rows[$r.file] = $r }
function Save-Manifest {
    if ($WhatIfPreference) { return }
    $rows.Values | Select-Object $columns | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding utf8BOM -WhatIf:$false
}
function Set-Row($Item, [string]$Status, [string]$Check, [string]$File = $Item.File, [long]$Bytes = $Item.Bytes, [string]$FileMd5 = '') {
    $path = Join-Path $Folder $File
    $old = $rows[$Item.File]
    if ($File -ne $Item.File -and $old) { $rows.Remove($Item.File) }  # saved under another name (its real type)
    $rows[$File] = [pscustomobject]@{
        file = $File; title = $Item.Title; format = $Item.Format; bundles = ($Item.Bundles -join '; '); item = $Item.Item
        bytes = $Bytes; md5 = $Item.Md5; file_md5 = $FileMd5; check = $Check; status = $Status
        added = $(if ($old.added) { $old.added } else { (Get-Date).ToString('s') })
        modified = $(if (Test-Path -LiteralPath $path) { (Get-Item -LiteralPath $path).LastWriteTimeUtc.ToString('s') + 'Z' })
    }
}
foreach ($p in $plan) {
    if ($p.Action -eq 'skip') { $rows[$p.File].bundles = $p.Bundles -join '; '; $rows[$p.File].title = $p.Title }
    if ($p.Action -eq 'removed') { $rows[$p.File].status = 'removed' }
}
Save-Manifest

# ---- Download ---------------------------------------------------------------------------------------
# Downloads to the .part file, resuming what is there. Network errors are retried with growing waits;
# an expired link is signed again by reading its order again.
# -Fresh: the caller deleted the .part, so a retry after a network error resumes only this download.
function Receive-File($Item, [string]$Part, [switch]$Fresh) {
    for ($attempt = 1; ; $attempt++) {
        if (-not $Fresh -and (Test-Path -LiteralPath $Part) -and (Get-Item -LiteralPath $Part).Length -ge $Item.Bytes) { return }
        try {
            $null = Invoke-WebRequest -Uri (Get-FreshUrl $Item) -OutFile $Part -Resume
            return
        } catch {
            if ($attempt -gt $Retries) { throw }
            $code = [int]$_.Exception.Response.StatusCode
            if ($code -in 403, 410) { $fetchedAt[$source[(Get-SourceKey $Item)].gamekey] = [datetime]::MinValue }  # sign again
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
    if ($n -lt $todo.Count - 1) { Start-Sleep -Seconds $DelaySeconds }
}

# ---- Summary ----------------------------------------------------------------------------------------
Write-Host ''
$updates = @($plan | Where-Object Action -eq 'update-available')
$removed = @($plan | Where-Object Action -eq 'removed')
if ($updates) { Write-Host "$($updates.Count) books have a new version on Humble (run with -Update to download them):"; Write-Table $updates File, Title }
if ($removed) { Write-Host "$($removed.Count) files are no longer offered by Humble (kept, marked removed):"; Write-Table $removed File }
if ($sizeOnly) { Write-Host "$($sizeOnly.Count) files were checked by size only (Humble gives no MD5 for them):"; Write-Table $sizeOnly File, Title }
if ($md5Wrong) { Write-Host "$($md5Wrong.Count) files differ from Humble's MD5 but came down identical twice and complete (kept; humble-md5-wrong):"; Write-Table $md5Wrong File, Title }
if ($failed) { Write-Warning "$($failed.Count) files failed (recorded as failed; the next run retries them):"; Write-Table $failed File, Title }
if (-not $WhatIfPreference) { Write-Host "Done: $($todo.Count - $failed.Count) of $($todo.Count) downloaded and checked. Manifest: $manifestPath" }
