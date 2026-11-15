# Humble Bundle Downloader

[![Tests](https://github.com/federico-moran/humblebundle-downloader/actions/workflows/tests.yml/badge.svg)](https://github.com/federico-moran/humblebundle-downloader/actions/workflows/tests.yml)

> Built by a non-developer, fully agentically, after taking Matt Pocock's course: [see how](#how-this-was-built).

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

1. Windows, with PowerShell 7 (`pwsh`).
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
| `-Folder` | `OneDrive\Documents\HumbleBundle` | Where the files, `manifest.csv` and `humble-library.json` go; created if it doesn't exist |
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

Adds every EPUB in the library that isn't in Calibre yet, tagged `Humble Bundle` and with the name of each bundle it came in (commas dropped, since Calibre separates tags with them). Books are recognized by their EPUB's MD5, so a re-run adds only new books, and gives books already there any tags they lack. PDFs and supplements are left out. Close Calibre first; the script backs up its database before changing anything. `-MaxBooks 1` adds one book, for a first test.

## Development

```powershell
Invoke-Pester ./tests
```

The logic is in [`src/HumbleLibrary.psm1`](src/HumbleLibrary.psm1) and tested with Pester 5+ using made-up order data; [`Get-HumbleLibrary.ps1`](Get-HumbleLibrary.ps1) handles the session, the network and the output, and [`Update-Calibre.ps1`](Update-Calibre.ps1) the calls to `calibredb`.

Only use this for things you've bought, at the gentle default pace: Humble's terms forbid automated access faster than a person could manage.

## How this was built

I'm not a developer. In June 2026 I took Matt Pocock's two-week [AI Coding for Real Engineers](https://www.aihero.dev/cohorts/ai-coding-for-real-engineers-m0k0w) course, and this tool and its two siblings were my first projects afterwards. They were built fully agentically: Claude Code wrote all the code and the docs. My part was choosing the problems, finding out how each store's site works, making the decisions (each design doc records them and why), and testing everything against my own libraries. I followed the course's process, with Matt's [skills](https://github.com/mattpocock/skills) installed in Claude Code.

I built the three between 2026-09-27 and 2026-10-12. Together they've downloaded and checked about 2,550 files, and the three have 127 automated tests between them (the Packt tool's were added in November 2026, before publishing).

This was the second, and the first built as a standalone script with tests. Humble publishes a size and MD5 for every file, so each download is checked as it arrives. That's how we found that Humble's own MD5 was wrong for 149 of 1,228 files, all of them complete. The design changed to match: when a file doesn't match, it's downloaded twice more, and kept if the two copies are identical and complete. 1,227 files came down, all passing. The pull request that merged the first working version is kept in [docs/v1-pull-request.md](docs/v1-pull-request.md).

The siblings: [packtpub-downloader](https://github.com/federico-moran/packtpub-downloader), my favorite, and [manning-downloader](https://github.com/federico-moran/manning-downloader).

A personal project: issues are welcome, but fixes aren't promised. Not affiliated with or endorsed by Matt Pocock, AI Hero, PacktPub, Humble Bundle or Manning.

## License

[MIT](LICENSE)
