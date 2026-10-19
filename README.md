# Calibre Organizer for KOReader

A KOReader plugin that moves the books Calibre put on your device into folders
built from their Calibre metadata — series, series index, custom columns — and
keeps everything else intact:

- **Notes, highlights and reading progress** (the `.sdr` sidecar) move with the book.
- **Reading history and collections** are updated to the new paths.
- **Calibre stays in sync**: the `lpath` of each moved book is rewritten in
  `metadata.calibre`, so Calibre (USB or wireless) still recognises every book
  and does not send it again.

The folder layout comes from **Calibre's own Save template**, which you copy
into the plugin once, so books end up exactly where Calibre would put them.

Typical use: change a book's series in Calibre, run *Update cached metadata on
device*, then tap *Organize now* in KOReader. No deleting and re-sending.

## Setup: copy the template from Calibre

Calibre never sends its save template to the device (it only sends finished
paths when it sends a book), so the plugin cannot ask for it. Copy it once:

1. In Calibre: *Preferences → Plugins → Device interface*, pick the driver you
   use — **Smart Device App Interface** for KOReader's wireless connection, or
   the **Kindle / Kobo** driver for USB — and click *Customize plugin*.
2. Copy the **Save template** field.
3. In KOReader: *Tools → Calibre organizer → Folder template*, paste, *Save*.

If you use both USB and wireless, set the same template in both Calibre
drivers. Until a template is set, the plugin does nothing.

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
| Folder template | The Save template copied from Calibre (see above). Empty by default. |
| Base folder | Folder the template is relative to. Default: `documents`. |
| Calibre library folder | Where `metadata.calibre` lives. Automatic by default (KOReader's Calibre inbox folder, home folder, `/mnt/us`, `/mnt/onboard`). Long-press to reset to automatic. |
| Remove empty folders | Deletes folders left empty after a move. |

## Supported template syntax

The plugin understands the usual Calibre save-template syntax:

```
{field}                     plain value
{field:format}              format spec, e.g. 0>2s pads to 2 characters with zeros
{field:format|prefix|suffix} prefix/suffix only added when the field is not empty
{field||suffix}             same, without a format
```

Fields: any key from the Calibre metadata (`title`, `authors`, `author_sort`,
`series`, `series_index`, `publisher`, `tags`, …) and custom columns as
`{#column}`; `{id}` is Calibre's book id. `series_index` is empty for books
without a series, just like in Calibre. Format types `s`, `d` and `f` are
supported. The file extension is always kept.

Not supported: template functions (`{title:'uppercase($)'}`) and template
programs (`program:` / `python:`). The plugin refuses such a template instead
of guessing.

Examples:

| Calibre template | Result |
| --- | --- |
| `{series:\|\|/}{series_index:0>2s\|\| - }{title} - {authors}` | `The Horus Heresy/01 - Horus Rising - Dan Abnett.epub` |
| `{#folder:\|\|/}{series:\|\|/}{series_index:0>2s\|\| - }{title}` | `Warhammer 40k/The Horus Heresy/01 - Horus Rising.epub` |
| `{author_sort}/{title} - {authors}` | `Abnett, Dan/Horus Rising - Dan Abnett.epub` |

## Safety of notes and progress

- A book is only moved together with its `.sdr` folder. If a `.sdr` folder
  already exists at the target, the book is **not** moved and the preview /
  result lists why.
- If a book moved but its `.sdr` could not be moved, this is reported; the old
  `.sdr` stays where it was, nothing is deleted.
- *Undo last organize* moves books and their `.sdr` folders back.

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

Klasör düzenini Calibre'nin kendi şablonu belirler: Calibre'de *Tercihler →
Eklentiler → Device interface → Smart Device App Interface* (kablosuz) ya da
Kindle sürücüsü (USB) → *Customize plugin* → **Save template** alanını kopyala,
eklentide *Folder template*'e yapıştır. Şablon girilmeden eklenti çalışmaz.

Önce *Preview* ile ne yapılacağına bak, sonra *Organize now* de. Beğenmezsen
*Undo last organize* ile geri alabilirsin. Hedefte zaten bir `.sdr` varsa kitap
taşınmaz, notların üzerine asla yazılmaz.
