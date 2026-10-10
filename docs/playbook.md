# Playbook: downloading your Humble Bundle library

A checklist for each run. For what the tool does, see the [README](../README.md).

> **Where I left off (2026-10-10):** done. **1,227 files (about 44 GB), all passing `-VerifyOnly`.** Humble's MD5 was wrong for 149 of them (complete files, kept as `format-only`; the script now handles this itself). The *Malware Analyst's Cookbook* DVD, which Defender blocks, is stored as `malwareanalyst_dvd.7z` (password `infected`), with `malwareanalyst_dvd.README.md` beside it; open it only in an isolated VM. The old `Humble Bundle eBooks` folder was compared (step 6) and deleted: 158 of its 161 files were covered, and the other 3 PDFs (two books Humble now offers only as EPUB, plus a 1st edition) are in `extras\`, with a README. Still failing: *How to Survive Anything*'s supplement, whose link on Humble's side is literally `<FILE_NAME>`. Possible next steps: Calibre and the Kindle; `-CompareWith` against the PacktPub library.

> **If antivirus blocks a download:** download it by hand with protection briefly off, pack it with `7z a -t7z -mx=0 -mhe=on -pinfected <name>.7z <file>`, delete the original, turn protection back on, and record it in `manifest.csv` with Humble's `md5`, the `.7z`'s `bytes` and `file_md5`, and `check = encrypted-7z`.

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

OneDrive downloads the old files first if they're online-only. Anything listed as **only-there** isn't in the new library: look at those before deleting the old folder. **similar-title** files are probably the same book in a different printing.

To see which books you also have from PacktPub:

```powershell
.\Get-HumbleLibrary.ps1 -CompareWith "$env:USERPROFILE\OneDrive\Documents\PacktPub"
```

## Next time (new purchases)

Run step 4 again. Only new files are downloaded; add `-Update` to take new versions of books you have.
