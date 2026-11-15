# Design

Decisions made before building (2026-10-10), and why. The research behind them was done from public sources; see [Sources](#sources).

## How it talks to Humble

| Purpose | Endpoint |
| --- | --- |
| List orders | `GET /api/v1/user/order` → `[{ gamekey }]` |
| One order | `GET /api/v1/order/<gamekey>?all_tpkds=true` → `product`, `subproducts[].downloads[].download_struct[]` |
| A file | `download_struct[].url.web`: a signed, expiring CDN link that needs no cookie |

Each `download_struct` has `name` (the format: "PDF", "EPUB", "MOBI", "CBZ", "Supplement", ...), `md5`, usually `sha1`, and `file_size`. Requests carry the `_simpleauth_sess` cookie; without it the API answers 401.

**A standalone script, not a browser script.** PacktPub's downloader had to run in the browser console because a Cloudflare bot check blocks everything else. Humble is behind Cloudflare too, but as of 2026 cookie-based tools work (one user reported downloading 846 GB with one in May 2026). A standalone script can choose file names, check every file against Humble's MD5 as it goes, resume downloads, and run without a browser tab, none of which a console script can do.

### Fallback: a browser-console script

If Humble starts challenging scripts (the API answers 403 with a check page), the fallback is a console script like PacktPub's: same-origin `fetch()` to the API (the cookie is sent automatically), then each file opened by navigation, since the CDN probably blocks `fetch()` from the page. It loses the in-run MD5 check and the file naming; `-VerifyOnly` could still check the files afterwards if the console script saves `humble-library.json`. Not built.

## Decisions

| Area | Decision | Why |
| --- | --- | --- |
| Language | PowerShell 7 | Matches the PacktPub tools; nothing to install |
| Cookie | Pasted once, saved with DPAPI under `%LOCALAPPDATA%`; asked again on 401; `-ResetSession` | Rarely re-pasted, never in the repo |
| Scope | `-Platform`, default `ebook`; keys ignored; Vault and Choice out of scope | The goal is the ebook library; Vault downloads use a different, unconfirmed system |
| Formats | `-Format`, default PDF, EPUB, CBZ and supplements | Supplements are often the only copy of code or disc contents; Humble labels them "Supplement", "Download", "ZIP" or ".zip" (all seen in a real library, 2026-10-10). "PDF (HD)" is its own format, `pdf (hd)`, not downloaded by default |
| Folder | `OneDrive\Documents\HumbleBundle`, flat, Humble's file names | A book in two bundles is stored once; Calibre-friendly. Bundles are recorded in the manifest |
| Name clashes | Second file gets the first 6 characters of its MD5 | Nothing lost, no prompts |
| Default action | Downloads; `-WhatIf` previews; `humble-library.json` saved every run | PowerShell convention |
| Pace | One file at a time, 5 s apart, 1 s between order reads, 3 retries with growing waits | Humble's terms forbid going faster than a person could |
| Checking | Download to `.part` (resumable), check size and MD5, then rename. On a mismatch, two fresh downloads: if they are identical and a complete PDF, EPUB or zip, keep it (`check = humble-md5-wrong`, its own MD5 in `file_md5`); otherwise `failed` | A file under its real name is always a verified copy. Changed 2026-10-10: Humble's size and MD5 turned out wrong for 149 of 1,228 files (about 1 in 8), mostly No Starch, Pragmatic, O'Reilly, Make: and Wiley books, all complete files |
| Real file type | Saved with the extension of what the file is | Humble serves some Make: EPUBs under `.pdf` links |
| Updates | New MD5 for the same item and format: reported; downloaded with `-Update`, old copy kept with a date | Re-runs never change files already on devices |
| Removed | Kept, marked `removed` (never from this run's filters alone) | Humble may withdraw products |
| Expiring links | Each order is read again once its links are 30 minutes old, or after a 403/410 | The links' lifetime isn't documented |
| Tools | One script: `-VerifyOnly` (offline check) and `-CompareWith <folder>` (old folder, PacktPub library) | One thing to remember |
| Calibre | Added after v1 (2026-10-10): `Update-Calibre.ps1` adds EPUBs only, tagged `Humble Bundle` and with each bundle's name; matched by MD5; `calibredb add --duplicates` | EPUBs suit the Kindle; Calibre's own duplicate check goes by title, which different books share (O'Reilly's and Packt's *Bash Cookbook*) |
| Repo | Private at first; public from 2026-11, MIT license | |

## Code layout

- [`src/HumbleLibrary.psm1`](../src/HumbleLibrary.psm1): the logic, with no network calls. Tested at four seams: `Get-DownloadPlan`, `Test-DownloadedFile`, `Test-Library`, `Compare-Library` (and `Get-EpubIsbn`, which it uses).
- [`Get-HumbleLibrary.ps1`](../Get-HumbleLibrary.ps1): session, HTTP, downloading, writing the manifest, output. Not unit tested; checked by a real `-WhatIf` and a one-file run.

## The manifest's check column

| `check` | Meaning |
| --- | --- |
| `ok` | Matches Humble's size and MD5 |
| `size-only` | Humble gave no MD5; the size matches |
| `humble-md5-wrong` | Humble's MD5 is wrong for what it serves; two downloads were identical and complete. `bytes` and `file_md5` are the file's own |
| `format-only` | Accepted from the first run's leftovers (2026-10-10): complete, but not compared with a second download. `bytes` and `file_md5` are the file's own |
| `encrypted-7z` | Repacked by hand into a password-protected `.7z`, because antivirus blocks the original (the *Malware Analyst's Cookbook* DVD, 2026-10-10; a README next to it explains). `md5` is still Humble's, so runs skip it; `bytes` and `file_md5` are the `.7z`'s |
| `mismatch` | With `status = failed`: no good copy yet |

`md5` is always Humble's, since that is how the plan recognises a file it has already downloaded.

## Open questions

- How long signed links last, and whether the CDN host has changed (`dl.humble.com` redirected to a name that didn't resolve in October 2026). The script uses whatever `url.web` says.
- How long a logged-in session cookie lasts.

## Sources

- smbl64/humble-cli (Go, active 2026): endpoints, models, resumable downloads. <https://github.com/smbl64/humble-cli>
- xtream1101/humblebundle-downloader (archived 2025): endpoints, issues about files without links. <https://github.com/xtream1101/humblebundle-downloader>
- MayeulC/hb-downloader: `download_struct` fields. <https://github.com/MayeulC/hb-downloader>
- kjmikkel/Humble-Catalog (2026): order JSON fixtures, pacing. <https://github.com/kjmikkel/Humble-Catalog>
- Humble Bundle Terms of Service (2024-12-24), section (b)(ii) on automated access. <https://www.humblebundle.com/terms>
