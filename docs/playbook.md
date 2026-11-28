# Playbook: downloading your Humble Bundle library

A checklist for each run. For what the tool does, see the [README](../README.md).

For how the run on my own library went, problems included, see the [run log](run-log.md).

## 1. Get your session cookie

1. Log in at <https://www.humblebundle.com>.
2. **F12** → **Application** → **Cookies** → `https://www.humblebundle.com` → find the cookie whose name starts with `ory_session_`. You'll need its **name** and its **value**.
3. Keep the browser tab; you don't need it open during the run.

The cookie changed when Humble rebuilt its site in November 2026; the old `_simpleauth_sess` no longer works, and the script asks for the new one.

## 2. Preview

In a PowerShell 7 terminal in the repo folder:

```powershell
.\Get-HumbleLibrary.ps1 -WhatIf
```

When asked, type the cookie's name, then paste its value (it isn't shown). It reads every purchase page (about one a second), saves `humble-library.json` in `OneDrive\Documents\HumbleBundle`, and prints the plan: how many files, and the total size. Check there's enough disk space, and that OneDrive won't fill up.

If it says Humble's site has changed, or names a page it couldn't read, Humble has changed its pages again: see [design.md](design.md#how-it-talks-to-humble).

If it says Humble refused the request (403), Humble has started blocking scripts: see [design.md](design.md#fallback-a-browser-console-script).

## 3. One-file test

```powershell
.\Get-HumbleLibrary.ps1 -MaxDownloads 1
```

It downloads the smallest file. Check that it opens, and that `manifest.csv` has a row for it with `check = ok`.

## 4. Full run

```powershell
.\Get-HumbleLibrary.ps1
```

Leave the terminal open. To stop, press **Ctrl+C**; run the same command again to carry on (an unfinished `.part` file resumes). If the cookie expires during the run, you're asked for a new one.

At the end it lists files that failed (run again to retry), files checked by size only (Humble gave no MD5), books with a new version, and files Humble no longer offers. A file your antivirus blocks fails on every run: that's the antivirus, not Humble, so running again won't help.

**Removal limit.** If more than 10 files, or every file of a bundle, are no longer offered, none is marked `removed`; they're listed instead. Humble may still be moving old orders to its new site (it said so in November 2026), so run again later. If you're sure they're gone, run with `-AcceptRemovals`.

**Deadlines.** Purchases made since November 2026 can be downloaded for a year after purchase (`available_until` in `manifest.csv`); older purchases have no deadline, so their column stays empty. The run ends by listing books you haven't downloaded that are due within 60 days, or already past: download those first.

## 5. Verify

```powershell
.\Get-HumbleLibrary.ps1 -VerifyOnly
```

Re-checks every file against the manifest without contacting Humble. Use it on backups too (`-Folder E:\Backup\HumbleBundle`).

## 6. Retire the old folder

```powershell
.\Get-HumbleLibrary.ps1 -CompareWith "$env:USERPROFILE\OneDrive\Documents\Humble Bundle eBooks"
```

OneDrive downloads the old files first if they're online-only. Anything listed as **only-there** isn't in the new library: look at those before deleting the old folder. **same-isbn** files are the same book (a different printing or edition file), matched by an ISBN inside the EPUBs, in a manifest, or in the file name. **same-title** files have exactly the same title: check them by hand, since different books can share a title (O'Reilly's and Packt's *Bash Cookbook*). Titles that only partly match aren't reported, so a reworded title shows as only-there.

To see which books you also have from PacktPub:

```powershell
.\Get-HumbleLibrary.ps1 -CompareWith "$env:USERPROFILE\OneDrive\Documents\PacktPub"
```

The PacktPub library names its files by ISBN, so its books match by ISBN wherever our EPUB has one.

## 7. Calibre

Close Calibre, then in a PowerShell 7 terminal:

```powershell
.\Update-Calibre.ps1 -WhatIf      # what would be added
.\Update-Calibre.ps1 -MaxBooks 1  # first time: add one book and check it in Calibre
.\Update-Calibre.ps1
```

It ends with `Now N of N EPUBs are in Calibre with their tags`. While it runs, calibredb may print a `MaintainPageCounts ... TimeoutExpired` traceback or `qt.gui` warnings about cover images: they're harmless (a page-count worker slow to stop; damaged color profiles or JPEG data in a few covers).

## Next time (new purchases)

Run step 4 again. Only new files are downloaded; add `-Update` to take new versions of books you have. Then run step 7 to add the new EPUBs to Calibre.
