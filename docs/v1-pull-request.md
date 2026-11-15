# Pull request #1: the first working version

The text of the pull request that merged the first working version into `main` on 2026-10-10 (branch `v1`), kept here as a record. The test count is the one at the time; see the [README](../README.md) for where the tool stands now.

---

## First working version: download, verify and compare a Humble Bundle library

First working version of the Humble Bundle downloader.

### What it does

`Get-HumbleLibrary.ps1` reads your orders through Humble's API, using your session cookie (saved encrypted with DPAPI under `%LOCALAPPDATA%`). It then downloads one file at a time, smallest first:

- Each file goes to `.part`, so an interrupted download resumes.
- Each file is checked against Humble's size and MD5, then given its real name and recorded in `manifest.csv`.
- `-WhatIf` previews the plan without downloading anything.
- `-VerifyOnly` re-checks the folder offline.
- `-CompareWith <folder>` reports overlap with another folder.

### Real-world fixes

These come from the first full run, on a 45-order library (1,228 files, about 44 GB):

- **Humble's MD5 was wrong for about 1 file in 8.** On a mismatch the script now downloads the file twice more. If both copies are identical and a complete PDF, EPUB or ZIP, it keeps the file and records the file's own MD5 (`check = humble-md5-wrong`).
- **Some EPUBs are served under `.pdf` links.** They're now saved with their real extension.
- **Companion ZIPs** labelled `ZIP` or `.zip` now count as supplements.
- **Antivirus-blocked downloads** can be kept as encrypted `.7z` archives (`check = encrypted-7z`). This is documented in the playbook.

### Tests

30 Pester tests, all passing (`Invoke-Pester ./tests`), covering the four seams in `src/HumbleLibrary.psm1`: `Get-DownloadPlan`, `Test-DownloadedFile` (plus `Get-BookFileType`), `Test-Library` and `Compare-Library`.

The script itself isn't unit tested. It was smoke-tested against a fake Humble, then run for real on the full library, which now passes `-VerifyOnly` (1,227 of 1,227 files).

See `docs/design.md` for the decisions and `docs/playbook.md` for the run checklist.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
