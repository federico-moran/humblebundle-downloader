# Design

Decisions made before building (2026-10-10), and why. The research behind them was done from public sources; see [Sources](#sources).

## How it talks to Humble

Humble rebuilt its site in November 2026 (Next.js, a new login). This is the new site's flow, worked out by hand on 2026-11-26 (issue #1); the old API is described under [History](#history-the-old-api-until-2026-11).

| Purpose | Request |
| --- | --- |
| List purchases | `GET /home/library`: the page's payload holds one `{"id","title","itemType":"content-entitlement","href"}` per purchase. The link's ID, not `id`, is the purchase page's |
| One purchase | `GET /home/library/<purchase id>`: the payload holds `productEntitlementId` and `userLibraryItem.entitlements.downloads[]`, one content entitlement per book |
| A book's links | `POST /home/library/<purchase id>` with headers `Next-Action: <action id>` and `Accept: text/x-component`, body `[["<entitlement id>"]]`. The reply's `1:{"ok":true,"data":{"signedUrls":{machine:{key:{file:link}}},"expiresAt"}}` gives signed `cdn.humble.com` links that last about 24 hours and need no cookie |
| The action ID | Found by name in the purchase page's public scripts (`/_next/static/chunks/*.js`, fetched without the cookie): `createServerReference("<hex>", …, "getSignedUrlsForEntitlements")`. It changes when Humble redeploys |

**The payload.** Pages carry their data as React Server Components rows, inside the HTML as `self.__next_f.push([1,"..."])` string chunks. `Get-PagePayload` joins and decodes them; the readers look for objects of the right shape anywhere in the rows, not at fixed positions, so layout changes don't break them.

**Each book** is `{"id","title","type":"download_drm_free","downloads":[{"key":"<machine>_<platform>","platform","downloadStruct":[{"name","fileSize","md5","sha1","url":{"web":"<bare file name>"}}]}],"unavailableAfter"}`. These are the old `download_struct` fields in camelCase, except that `url.web` is now a bare file name. The machine name (the download key without `_<platform>`) is the same as on the old site, so files downloaded then are still recognized by item as well as by MD5.

**The session** is an Ory cookie whose name starts with `ory_session_` (the full name is in your browser, not in this repo). A script sending only that cookie gets the pages. A dead session shows as `"logged_in":false` on the page, or a redirect to `auth.humblebundle.com`.

**A standalone script, not a browser script.** PacktPub's downloader had to run in the browser console because a Cloudflare bot check blocks everything else. Humble is behind Cloudflare too, but as of 2026-11 it doesn't challenge a script sending the session cookie. A standalone script can choose file names, check every file against Humble's MD5 as it goes, resume downloads, and run without a browser tab, none of which a console script can do.

### Fallback: a browser-console script

If Humble starts challenging scripts (pages answer 403 with a check page), the fallback is a console script like PacktPub's, run on a purchase page: read the payload from `self.__next_f` (already decoded in the page), call the download action with same-origin `fetch()` (the cookie is sent automatically; the action ID is in the page's scripts), and open each signed link by navigation, since the CDN probably blocks `fetch()` from the page. It loses the in-run MD5 check and the file naming; `-VerifyOnly` could still check the files afterwards if the console script saves `humble-library.json`. Not built.

### History: the old API (until 2026-11)

Until November 2026 the tool used the JSON API behind the old library page: `GET /api/v1/user/order` for the order keys (gamekeys), then `GET /api/v1/order/<gamekey>?all_tpkds=true` for each order's `product`, `subproducts[].downloads[].download_struct[]`, with ready-signed links in `url.web`. Requests carried the `_simpleauth_sess` cookie. Both endpoints now answer 404 for everyone. The tool still uses that order shape internally (see the adapter decision below), and an old-format `humble-library.json` is kept as `humble-library.<date>.json` on the first run of the new code.

## Decisions

| Area | Decision | Why |
| --- | --- | --- |
| Language | PowerShell 7 | Matches the PacktPub tools; nothing to install |
| Language version | `#Requires -Version 7` in both scripts (2026-11) | Under 5.1 the break showed as "The connection was closed unexpectedly" |
| Cookie | Two prompts, the `ory_session_` cookie's name, then its value (`name=value` accepted); both saved with DPAPI under `%LOCALAPPDATA%`; asked again once when a page shows `logged_in:false` or redirects to the login site, then the run stops; `-ResetSession`. The full cookie name is never written in the repo (2026-11) | Rarely re-pasted, never in the repo; the name may differ between accounts or change |
| Scope | `-Platform`, default `ebook`; keys ignored; Vault and Choice out of scope | The goal is the ebook library; Vault downloads use a different, unconfirmed system |
| Formats | `-Format`, default PDF, EPUB, CBZ and supplements | Supplements are often the only copy of code or disc contents; Humble labels them "Supplement", "Download", "ZIP" or ".zip" (all seen in a real library, 2026-10-10). "PDF (HD)" is its own format, `pdf (hd)`, not downloaded by default |
| Folder | `OneDrive\Documents\HumbleBundle`, flat, Humble's file names | A book in two bundles is stored once; Calibre-friendly. Bundles are recorded in the manifest |
| Name clashes | Second file gets the first 6 characters of its MD5 | Nothing lost, no prompts |
| Default action | Downloads; `-WhatIf` previews; `humble-library.json` saved every run (since 2026-11: the adapted purchases, with each purchase's ID and each book's entitlement ID and `unavailableAfter`) | PowerShell convention |
| Pace | One file at a time, 5 s apart, 1 s between purchase pages, 3 retries with growing waits on 429 and 5xx; the scripts that name the download action are fetched once per run, back to back | Humble's terms forbid going faster than a person could |
| Checking | Download to `.part` (resumable), check size and MD5, then rename. On a mismatch, two fresh downloads: if they are identical and a complete PDF, EPUB or zip, keep it (`check = humble-md5-wrong`, its own MD5 in `file_md5`); otherwise `failed` | A file under its real name is always a verified copy. Changed 2026-10-10: Humble's size and MD5 turned out wrong for 149 of 1,228 files (about 1 in 8), mostly No Starch, Pragmatic, O'Reilly, Make: and Wiley books, all complete files |
| Real file type | Saved with the extension of what the file is | Humble serves some Make: EPUBs under `.pdf` links |
| Updates | New MD5 for the same item and format: reported; downloaded with `-Update`, old copy kept with a date | Re-runs never change files already on devices |
| Removed | Kept, marked `removed` (never from this run's filters alone). Since 2026-11, none is marked if a run would mark more than 10 files, or every file of a bundle; they're listed instead, and `-AcceptRemovals` records them | Humble may withdraw products; but in 2026-11 it said older orders were still being moved to the new site, and a half-moved library would look like mass removal |
| Reading the new site (2026-11) | An adapter (`ConvertFrom-PurchasePage`) turns each purchase page into the old order shape, so `Get-DownloadPlan`, the checks, the manifest and Calibre are unchanged. The old API code is removed | The new pages carry the same files, sizes and MD5s; one tested seam absorbs the change |
| Signing links (2026-11) | Each book's links are signed just before its first file is downloaded, by the same action the download button calls, and reused for its other files; signed again before they expire, or after a 403/410. Not `recordDownload` (it only logs a click) nor `getBulkDownloadManifest` (one large bundled download, which would bypass the per-file checks) | Links last about 24 hours; a long run would outlive links signed up front |
| Action ID (2026-11) | Found by name in the site's scripts once per run, `-WhatIf` included, kept in memory only; looked up once more if signing fails as if it were stale, then the run stops with "Humble's site has changed" | It's a build hash that changes on every redeploy |
| Deadlines (2026-11) | `available_until` in `manifest.csv`, from Humble's `unavailableAfter`; books not downloaded and due within 60 days (or past) are listed at the end | New purchases can be downloaded for a year. In the first real run (2026-11-26) only the new bundle's 25 books had a date; the 816 books of the 45 older purchases had none, and their column stays empty |
| Failures (2026-11) | A page that is missing (404), isn't the expected data, or has no payload gives one line naming the page and pointing here; HTML is never printed | The old script printed the whole 404 page as its error |
| Tools | One script: `-VerifyOnly` (offline check) and `-CompareWith <folder>` (old folder, PacktPub library) | One thing to remember |
| Calibre | Added after v1 (2026-10-10): `Update-Calibre.ps1` adds EPUBs only, tagged `Humble Bundle` and with each bundle's name; matched by MD5; `calibredb add --duplicates` | EPUBs suit the Kindle; Calibre's own duplicate check goes by title, which different books share (O'Reilly's and Packt's *Bash Cookbook*) |
| Repo | Private at first; public from 2026-11, MIT license | |

## Code layout

- [`src/HumbleLibrary.psm1`](../src/HumbleLibrary.psm1): the logic, with no network calls. Tested at these seams: `Get-DownloadPlan`, `Test-DownloadedFile`, `Test-Library`, `Compare-Library` (and `Get-EpubIsbn`, which it uses), `Get-CalibrePlan`; and, for the new site, `Get-PagePayload`, `ConvertFrom-LibraryPage`, `ConvertFrom-PurchasePage` (fed through `Get-DownloadPlan`), `Find-ServerActionId`, `ConvertFrom-SignedUrlReply`, `Get-DownloadDeadline` and `Get-RemovalDecision`. The tests use hand-written pages shaped like Humble's, never real data.
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

`md5` is always Humble's, since that is how the plan recognizes a file it has already downloaded.

## Open questions

- How long a logged-in session cookie lasts.
- Whether `/home/library` ever pages or lazy-loads for very large libraries (all 46 purchases were on one page in 2026-11).
- Whether old orders, once Humble has moved them, carry the same MD5s (the removal limit covers the time until then).

## Sources

- smbl64/humble-cli (Go, active 2026): endpoints, models, resumable downloads. <https://github.com/smbl64/humble-cli>
- xtream1101/humblebundle-downloader (archived 2025): endpoints, issues about files without links. <https://github.com/xtream1101/humblebundle-downloader>
- MayeulC/hb-downloader: `download_struct` fields. <https://github.com/MayeulC/hb-downloader>
- kjmikkel/Humble-Catalog (2026): order JSON fixtures, pacing. <https://github.com/kjmikkel/Humble-Catalog>
- Humble Bundle Terms of Service (2024-12-24), section (b)(ii) on automated access. <https://www.humblebundle.com/terms>
