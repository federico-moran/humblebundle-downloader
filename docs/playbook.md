# Playbook: downloading your Humble Bundle library

A checklist for each run. For what the tool does, see the [README](../README.md).

> **Where I left off (2026-10-10):** done. **1,227 files (about 44 GB), all passing `-VerifyOnly`.** Humble's MD5 was wrong for 149 of them (complete files, kept as `format-only`; the script now handles this itself). The *Malware Analyst's Cookbook* DVD, which Defender blocks, is stored as `malwareanalyst_dvd.7z` (password `infected`), with `malwareanalyst_dvd.README.md` beside it; open it only in an isolated VM. The old `Humble Bundle eBooks` folder was compared (step 6) and deleted: 158 of its 161 files were covered, and the other 3 PDFs (two books Humble now offers only as EPUB, plus a 1st edition) are in `extras\`, with a README. Still failing: *How to Survive Anything*'s supplement, whose link on Humble's side is literally `<FILE_NAME>`.
>
> **Update (2026-10-11):** `-CompareWith` now matches by MD5, then by ISBN (read from the EPUBs on both sides), then by exact title, reported as `same-title` to check by hand. The "one title contains the other" rule behind the 91 wrong matches below is gone.
>
> **Update (2026-10-10):** compared with the PacktPub library: **no book is in both.** `-CompareWith` reported 91 "similar-title" matches, all wrong (short titles such as No Starch's *Penetration Testing* are contained in many Packt titles); checked instead by the ISBNs inside the EPUBs and by exact titles. The 21 Humble books from "Packt" are Excel and Power BI titles that aren't in the Packt account. **All 585 EPUBs are in Calibre** (now 1,132 books with the Packt ones), added by [step 7](#7-calibre), tagged `Humble Bundle` and with their bundles.

> **If antivirus blocks a download:** download it by hand with protection briefly off, pack it with `7z a -t7z -mx=0 -mhe=on -pinfected <name>.7z <file>`, delete the original, turn protection back on, and record it in `manifest.csv` with Humble's `md5`, the `.7z`'s `bytes` and `file_md5`, and `check = encrypted-7z`.
>
> Do this only for a file from a source you trust, such as a book's companion disc flagged for the attack code it teaches with. While protection is off, nothing scans what reaches your PC, so keep that window short and download nothing else. The password `infected` is the usual convention for sharing malware samples: it stops the file being opened or scanned by accident, not on purpose. Open the archive only in an isolated virtual machine.

## 1. Get your session cookie

1. Log in at <https://www.humblebundle.com>.
2. **F12** → **Application** → **Cookies** → `https://www.humblebundle.com` → copy the value of `_simpleauth_sess`.
3. Keep the browser tab; you don't need it open during the run.

## 2. Preview

In a PowerShell 7 terminal in the repo folder:

```powershell
.\Get-HumbleLibrary.ps1 -WhatIf
```

Paste the cookie when asked. It reads every order (about one a second), saves `humble-library.json` in `OneDrive\Documents\HumbleBundle`, and prints the plan: how many files, and the total size. Check there's enough disk space, and that OneDrive won't fill up.

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

At the end it lists files that failed (run again to retry), files checked by size only (Humble gave no MD5), books with a new version, and files Humble no longer offers.

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

It ends with `Now N of N EPUBs are in Calibre with their tags`. While it runs, calibredb may print a `MaintainPageCounts ... TimeoutExpired` traceback or `qt.gui` warnings about cover images: they're harmless (a page-count worker slow to stop; damaged colour profiles or JPEG data in a few covers).

## Next time (new purchases)

Run step 4 again. Only new files are downloaded; add `-Update` to take new versions of books you have. Then run step 7 to add the new EPUBs to Calibre.
