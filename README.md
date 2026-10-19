# Calibre Organizer for KOReader

A KOReader plugin that moves the books Calibre put on your device into folders
built from their Calibre metadata — series, series index, custom columns — and
keeps everything else intact:

- **Notes, highlights and reading progress** (the `.sdr` sidecar) move with the book.
- **Reading history and collections** are updated to the new paths.
- **Calibre stays in sync**: the `lpath` of each moved book is rewritten in
  `metadata.calibre`, so Calibre (USB or wireless) still recognises every book
  and does not send it again.

Typical use: change a book's series in Calibre, run *Update cached metadata on
device*, then tap *Organize now* in KOReader. No deleting and re-sending.

## Install

Copy the `calibreorganizer.koplugin` folder into `koreader/plugins/` on the
device (on a Kindle: `koreader/plugins/` at the root of the USB drive) and
restart KOReader. The menu entry appears under **Tools → Calibre organizer**.

## Menu

| Entry | What it does |
| --- | --- |
| Preview | Lists every planned move, books already in place, and skipped books with the reason. Changes nothing. |
| Organize now | Asks for confirmation, then moves the books. |
| Undo last organize | Moves the books of the last run back where they were. |
| Folder template | Calibre-style template for the folder and file name (see below). |
| Base folder | Folder the template is relative to. Default: `documents`. |
| Calibre library folder | Where `metadata.calibre` lives. Automatic by default (KOReader's Calibre inbox folder, home folder, `/mnt/us`, `/mnt/onboard`). Long-press to reset to automatic. |
| Remove empty folders | Deletes folders left empty after a move. |

## Templates

The syntax is a subset of Calibre's save templates:

```
{field}                     plain value
{field:format}              format spec, e.g. 0>2s pads to 2 characters with zeros
{field:format|prefix|suffix} prefix/suffix only added when the field is not empty
{field||suffix}             same, without a format
```

Fields: any key from the Calibre metadata (`title`, `authors`, `author_sort`,
`series`, `series_index`, `publisher`, `tags`, …) and custom columns as
`{#column}`. `series_index` is empty for books without a series, just like in
Calibre. Format types `s`, `d` and `f` are supported. The file extension is
always kept.

Examples:

| Template | Result |
| --- | --- |
| `{series:\|\|/}{series_index:0>2s\|\| - }{title} - {authors}` (default) | `The Horus Heresy/01 - Horus Rising - Dan Abnett.epub` |
| `{#folder:\|\|/}{series:\|\|/}{series_index:0>2s\|\| - }{title}` | `Warhammer 40k/The Horus Heresy/01 - Horus Rising.epub` |
| `{author_sort}/{title}` | `Abnett, Dan/Horus Rising.epub` |

Tip: use the same template in Calibre's device driver settings (*Save
template*), so books Calibre sends later land in the same place.

## Notes

- Run it while Calibre's wireless connection is **not** active.
- Before writing, the plugin saves a copy of the metadata file as
  `metadata.calibre.bak`.
- A book that is currently open, a book whose target already exists, and two
  books that would get the same name are skipped and listed in the preview.
- Illegal characters for FAT32 (`<>:"/\|?*`) are replaced with `_`; names are
  cut to 120 bytes.

## Development

The template and planning logic lives in `organizer_core.lua` and has no
KOReader dependencies. Run the tests with LuaJIT:

```
luajit spec/core_spec.lua
```

---

## Türkçe özet

Calibre'nin cihaza gönderdiği kitapları Calibre bilgilerine (seri, seri
numarası, özel sütunlar) göre klasörlere taşır. Notlar, işaretlemeler ve okuma
ilerlemesi kitapla birlikte taşınır; Calibre'deki cihaz listesi de güncel
kalır, yani kitapları silip yeniden göndermeye gerek yoktur.

Kurulum: `calibreorganizer.koplugin` klasörünü cihazdaki `koreader/plugins/`
içine kopyala ve KOReader'ı yeniden başlat. Menü: **Araçlar → Calibre organizer**.
Önce *Preview* ile ne yapılacağına bak, sonra *Organize now* de. Beğenmezsen
*Undo last organize* ile geri alabilirsin.
