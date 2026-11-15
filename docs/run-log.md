# Run log: my own library

Notes from running the tool on my own Humble Bundle library, oldest first. For the steps themselves, see the [playbook](playbook.md).

## 2026-10-10: downloading finished

Done. **1,227 files (about 44 GB), all passing `-VerifyOnly`.**

- Humble's MD5 was wrong for 149 of them (complete files, kept as `format-only`; the script now handles this itself).
- The *Malware Analyst's Cookbook* DVD, which Defender blocks, is stored as `malwareanalyst_dvd.7z` (password `infected`, the usual convention for malware samples), with `malwareanalyst_dvd.README.md` beside it; open it only in an isolated VM. I recorded it in the manifest by hand, with `check = encrypted-7z` (see [design.md](design.md#the-manifests-check-column)).
- The old `Humble Bundle eBooks` folder was compared ([playbook step 6](playbook.md#6-retire-the-old-folder)) and deleted: 158 of its 161 files were covered, and the other 3 PDFs (two books Humble now offers only as EPUB, plus a 1st edition) are in `extras\`, with a README.
- Still failing: *How to Survive Anything*'s supplement, whose link on Humble's side is literally `<FILE_NAME>`.

## 2026-10-10: compared with the PacktPub library, and into Calibre

Compared with the PacktPub library: **no book is in both.** `-CompareWith` reported 91 "similar-title" matches, all wrong (short titles such as No Starch's *Penetration Testing* are contained in many Packt titles); checked instead by the ISBNs inside the EPUBs and by exact titles. The 21 Humble books from "Packt" are Excel and Power BI titles that aren't in the Packt account.

**All 585 EPUBs are in Calibre** (now 1,132 books with the Packt ones), added by [playbook step 7](playbook.md#7-calibre), tagged `Humble Bundle` and with their bundles.

## 2026-10-11: `-CompareWith` matches by ISBN

`-CompareWith` now matches by MD5, then by ISBN (read from the EPUBs on both sides), then by exact title, reported as `same-title` to check by hand. The "one title contains the other" rule behind the 91 wrong matches above is gone.
