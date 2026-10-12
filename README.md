# Humble Bundle Downloader

Downloads the ebooks (and, if you ask, other files) you own on [Humble Bundle](https://www.humblebundle.com/home/library), checking every file against the size and MD5 that Humble publishes for it.

A PowerShell 7 script using your own logged-in session. It's a sibling of [packtpub-downloader](https://github.com/federico-moran/packtpub-downloader), which had to run inside the browser because PacktPub blocks scripts; Humble doesn't (as of 2026), so this one runs on its own. See [docs/design.md](docs/design.md) for why, and for the fallback if that changes.

## What it does

- Reads all your orders through the same API the library page uses, and saves them as `humble-library.json`.
- Downloads one file at a time, smallest first, 5 seconds apart, to `<name>.part`. An interrupted download resumes.
- Checks each file's size and MD5 against Humble's, and only then gives it its real name. A file that fails is downloaded once more, then recorded as failed.
- Keeps `manifest.csv` in the folder: every file with its title, bundles, size, MD5 and status. Re-runs skip what's there.
- A book in several bundles is downloaded once. Two different files with the same name are both kept (the second gets part of its MD5 in its name).
- A new version of a book you have is reported; `-Update` downloads it and keeps the old copy, renamed with the date. Files Humble stops offering are kept and marked `removed`.

## Setup

1. PowerShell 7 (`pwsh`).
2. Your session cookie. Log in at humblebundle.com, press **F12** → **Application** → **Cookies** → `https://www.humblebundle.com`, and copy the value of `_simpleauth_sess`. The script asks for it the first time (it isn't shown as you paste) and saves it encrypted for your Windows account in `%LOCALAPPDATA%\humblebundle-downloader`. When it expires, you're asked again.

**The cookie is your login.** Never paste it anywhere else, and don't commit it. The library folder holds your order keys, which open your download pages: keep it private too.

## Usage

```powershell
.\Get-HumbleLibrary.ps1 -WhatIf          # read your orders and show what would be downloaded
.\Get-HumbleLibrary.ps1 -MaxDownloads 1  # download one file, to check everything works
.\Get-HumbleLibrary.ps1                  # download everything
```

| Option | Default | |
| --- | --- | --- |
| `-Folder` | `OneDrive\Documents\HumbleBundle` | Where the files, `manifest.csv` and `humble-library.json` go |
| `-Platform` | `ebook` | Also `audio`, `video`, `windows`, `mac`, `linux`, `android`, ... |
| `-Format` | `pdf, epub, cbz, supplement` | Also `mobi`, `pdf (hd)`, `mp3`, ...; `supplement` is code and extras zips |
| `-Update` | off | Download new versions of books you already have |
| `-MaxDownloads` | all | Stop after this many files |
| `-DelaySeconds` | 5 | Pause between downloads |
| `-VerifyOnly` | | Check the folder against `manifest.csv`, offline |
| `-CompareWith <folder>` | | List which files in another folder are also here (same MD5, same ISBN, or exactly the same title), and which are only there |
| `-ResetSession` | | Forget the saved cookie |

For the full run checklist, see the [playbook](docs/playbook.md).

### Calibre

```powershell
.\Update-Calibre.ps1 -WhatIf  # preview
.\Update-Calibre.ps1          # add the EPUBs to Calibre
```

Adds every EPUB in the library that isn't in Calibre yet, tagged `Humble Bundle` and with the name of each bundle it came in (commas dropped, since Calibre separates tags with them). Books are recognised by their EPUB's MD5, so a re-run adds only new books, and gives books already there any tags they lack. PDFs and supplements are left out. Close Calibre first; the script backs up its database before changing anything. `-MaxBooks 1` adds one book, for a first test.

## Development

```powershell
Invoke-Pester ./tests
```

The logic is in [`src/HumbleLibrary.psm1`](src/HumbleLibrary.psm1) and tested with Pester 5+ using made-up order data; [`Get-HumbleLibrary.ps1`](Get-HumbleLibrary.ps1) handles the session, the network and the output, and [`Update-Calibre.ps1`](Update-Calibre.ps1) the calls to `calibredb`.

Only use this for things you've bought, at the gentle default pace: Humble's terms forbid automated access faster than a person could manage.
