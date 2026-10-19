# Calibre Organizer for KOReader

Sorts the books that **Calibre** put on your e-reader into folders, using the
same naming rule Calibre itself uses — **without** losing your notes,
highlights and reading progress, and without re-sending anything from Calibre.

Example: you put *Our Oriental Heritage* into the series *The Story of
Civilization* in Calibre. The book on your device still sits at
`documents/Our Oriental Heritage - Will Durant.epub`. Run the plugin and it
becomes `documents/The Story of Civilization/1 Our Oriental Heritage - Will Durant.epub`,
with your notes and progress still attached.

What gets moved together with each book:

- its `.sdr` folder (KOReader notes, highlights, bookmarks, reading position)
- its entry in KOReader's reading history and collections
- its entry in Calibre's device list (`metadata.calibre`), so Calibre still
  recognises the book in its new place — over USB and over wireless

> Türkçe anlatım aşağıda: [Türkçe](#türkçe)

---

## Before you start

The plugin only works with books that **Calibre sent to the device** (over USB
or over KOReader's wireless connection). Calibre keeps a list of those books in
a file called `metadata.calibre` on the device; the plugin reads and updates
that list. Books you copied by hand with a file manager are not in that list
and are left alone.

## 1. Install

1. Download this repository (green **Code** button → **Download ZIP**) and unzip it.
2. Make sure the folder is named exactly `calibreorganizer.koplugin`
   (GitHub's ZIP names it `calibreorganizer.koplugin-main` — rename it).
3. Connect the device by USB and copy that folder into `koreader/plugins/`.
   - Kindle: `koreader/plugins/` at the top of the Kindle drive
   - Kobo: `.adds/koreader/plugins/`
4. Restart KOReader. The plugin is in the top menu under
   **Tools (wrench icon) → Calibre organizer**.

## 2. Copy your save template from Calibre (once)

The plugin does not invent a folder layout. It uses **your Calibre save
template** — the rule Calibre uses to name files on the device. Calibre never
sends this rule to the device, so you copy it over once by hand.

**In Calibre on your computer:**

1. Open **Preferences** (Ctrl+P) → **Plugins** (under *Advanced*).
2. Open **Device interface** and select the driver **you use to send books**:
   - wireless (KOReader's *Calibre* wireless connection):
     **Smart Device App Interface**
   - Kindle over USB:
     **Kindle 2/3/4/Touch/PaperWhite/Voyage and Oasis Device Interface**
   - Kobo over USB: **Kobo Reader Device Interface**
3. Click **Customize plugin**.
4. Find the field called **Save template** and copy its **entire** text.
   It looks something like this:

   ```
   {author_sort}/{title} - {authors}
   ```
   or
   ```
   {series:| | }/{series_index} {title} - {author}
   ```

   Copy it exactly as it is — every brace, colon, pipe `|` and space. Do not add
   quotes.

**In KOReader on the device:**

5. **Tools → Calibre organizer → Folder template** → paste (or type) the text
   → **Save**. The menu now shows the template.

If you send books both over USB and wireless, both Calibre drivers should have
the **same** save template — otherwise Calibre itself puts books in different
places depending on how you connect.

Until a template is set, the plugin refuses to do anything.

## 3. Use it

1. In Calibre, change what you want (series, series number, title, …).
2. Push the new information to the device: connect, select the books, then
   **Send to device → Update cached metadata on device** (the small arrow next
   to the *Send to device* button).
3. **Disconnect** Calibre's wireless connection in KOReader (or eject the USB
   drive). See [Wireless connection](#wireless-connection) for why.
4. In KOReader: **Tools → Calibre organizer → Preview**. Nothing is changed;
   you get a list of what would move where, and which books are skipped and why.
5. If the list looks right: **Organize now** → confirm.
6. Changed your mind? **Undo last organize** puts everything back.

## Menu

| Entry | What it does |
| --- | --- |
| Preview | Shows every planned move, books already in place, and skipped books with the reason. Changes nothing. |
| Organize now | Asks for confirmation, then moves the books. |
| Undo last organize | Moves the books of the last run (and their notes) back. |
| Folder template | The save template copied from Calibre. Empty until you set it. |
| Base folder | Folder the template is relative to. Default `documents` (what Calibre uses on a Kindle). Leave empty to use the folder that holds `metadata.calibre`. |
| Calibre library folder | Folder that holds `metadata.calibre`. *Automatic* by default. Long-press to go back to automatic. |
| Remove empty folders after moving | Deletes folders that are left empty. On by default. |

## Your notes are safe

- A book is always moved **together with** its `.sdr` folder.
- If a `.sdr` folder already exists at the new place, the book is **not**
  moved — your notes are never overwritten. The result screen tells you which
  book and why.
- If a book moved but its `.sdr` folder could not, this is reported as an
  error and the old `.sdr` stays where it was. Nothing is ever deleted.
- Books you never opened have no `.sdr` folder; they are simply moved, this is
  not an error.
- The book that is currently open is skipped.
- Before writing, the plugin saves a copy of Calibre's list as
  `metadata.calibre.bak`.

Still, the first time, copy your `.sdr` folders of important books to your
computer. It costs nothing.

## Wireless connection

Do **not** run the plugin while Calibre's wireless connection is active. During
a connection, KOReader's Calibre plugin keeps the book list in memory and may
write that old list back to `metadata.calibre`, undoing the plugin's changes
to it (your books and notes are not affected, but Calibre would look for them
in the old places). Disconnect first, organize, then reconnect.

## Troubleshooting

**"No Calibre metadata file found"**

The plugin looks for `metadata.calibre` (or `.metadata.calibre`) in, in this
order: KOReader's Calibre inbox folder, the KOReader home folder, the root of
a Kindle (`/mnt/us`) or Kobo (`/mnt/onboard`).

- Books sent over **USB** keep this file at the **top of the device drive**
  (e.g. `E:\metadata.calibre`).
- Books sent over **wireless** keep it in KOReader's **inbox folder**.

If you use both, set KOReader's inbox folder to the top of the drive, so both
use the same file: **Network tab → Calibre → Wireless settings → Inbox folder**.
Or tell the plugin directly: **Calibre organizer → Calibre library folder**.

**Books end up one folder too deep / not in `documents`**

Check **Base folder**. On a Kindle, Calibre puts books under `documents`, and
your template is relative to that. If `metadata.calibre` sits inside
`documents` itself (inbox folder = `documents`), set Base folder to empty.

**"Template error"**

Template functions such as `{title:'uppercase($)'}` and template programs
(`program:` …) are not supported. Use a plain template.

**A book is listed as "file not found"**

The file is in Calibre's list but not on the device (deleted or moved by
hand). Connect to Calibre once so it refreshes its list.

## Supported template syntax

```
{field}                       the value
{field:format}                format, e.g. {series_index:0>2s} → 01, 02, … 10
{field:format|prefix|suffix}  prefix/suffix are only added when the field is not empty
{field:|prefix|suffix}        same, without format
```

Fields: `title`, `authors` (or `author`), `author_sort`, `series`,
`series_index`, `publisher`, `tags`, `id` (Calibre book id), any other key in
`metadata.calibre`, and custom columns as `{#column}`. `series_index` is empty
for books without a series, as in Calibre. The file extension is always kept.
Characters not allowed on FAT32 (`<>:"/\|?*`) become `_`.

Tip: if your template has `{series_index}` without padding, set KOReader's file
browser to *sort by name (natural sorting)* so 10 comes after 9.

## Development

The template and planning logic is in `organizer_core.lua` and has no KOReader
dependencies. Tests:

```
luajit spec/core_spec.lua
```

---

## Türkçe

Calibre'nin cihaza gönderdiği kitapları, **Calibre'nin kendi adlandırma
kuralına göre** klasörlere taşır. Notlar, işaretlemeler ve okuma ilerlemesi
kaybolmaz, Calibre'den hiçbir şeyi yeniden göndermen gerekmez.

Sadece **Calibre'nin gönderdiği** kitaplarla çalışır (USB ya da KOReader
kablosuz bağlantısı). Elle kopyalanan kitaplara dokunmaz.

### Kurulum

1. Bu repoyu indir (**Code → Download ZIP**) ve aç.
2. Klasörün adı tam olarak `calibreorganizer.koplugin` olmalı. GitHub'ın
   zip'i `-main` ekler, onu sil.
3. Cihazı USB ile bağla, klasörü `koreader/plugins/` içine kopyala
   (Kindle: sürücünün kökündeki `koreader/plugins/`; Kobo: `.adds/koreader/plugins/`).
4. KOReader'ı yeniden başlat. Menü: **Araçlar (anahtar simgesi) → Calibre organizer**.

### Calibre'den şablonu kopyala (bir kere)

Eklenti klasör düzenini kendi uydurmaz, **senin Calibre şablonunu** kullanır.
Calibre bu şablonu cihaza göndermediği için bir kere elle kopyalaman gerekiyor.

**Bilgisayarda, Calibre'de:**

1. **Tercihler** (Ctrl+P) → **Eklentiler** (*Gelişmiş* altında).
2. **Device interface** (Aygıt arayüzü) bölümünü aç, **kitap gönderirken
   kullandığın** sürücüyü seç:
   - kablosuz (KOReader Calibre bağlantısı): **Smart Device App Interface**
   - Kindle, USB: **Kindle 2/3/4/Touch/PaperWhite/Voyage and Oasis Device Interface**
   - Kobo, USB: **Kobo Reader Device Interface**
3. **Customize plugin** (Eklentiyi özelleştir) düğmesine tıkla.
4. **Save template** (Kaydetme şablonu) alanındaki yazının **tamamını** kopyala.
   Şuna benzer bir şeydir:
   ```
   {series:| | }/{series_index} {title} - {author}
   ```
   Süslü parantezler, iki nokta, `|` işaretleri ve boşluklar dahil, olduğu
   gibi kopyala. Tırnak ekleme.

**Cihazda, KOReader'da:**

5. **Araçlar → Calibre organizer → Folder template** → yapıştır ya da yaz →
   **Save**.

Hem USB hem kablosuz kullanıyorsan iki Calibre sürücüsünde de **aynı** şablon
olmalı. Şablon girilmeden eklenti hiçbir şey yapmaz.

### Kullanım

1. Calibre'de seriyi, seri numarasını vs. değiştir.
2. Kitapları seç → **Cihaza gönder** yanındaki ok → **Update cached metadata on device**.
3. KOReader'da Calibre kablosuz bağlantısını **kes** (ya da USB'yi çıkar).
4. **Calibre organizer → Preview**: hiçbir şeyi değiştirmeden neyin nereye
   taşınacağını gösterir.
5. Liste doğruysa **Organize now** → onayla.
6. Beğenmezsen **Undo last organize** her şeyi geri alır.

### Notların güvende

- Kitap her zaman `.sdr` klasörüyle (notlar, ilerleme) birlikte taşınır.
- Hedefte zaten bir `.sdr` varsa kitap **taşınmaz**, notların üzerine asla yazılmaz.
- Hiç açılmamış kitapların `.sdr`'si yoktur, onlar normal taşınır, hata sayılmaz.
- Açık olan kitap atlanır. Yazmadan önce Calibre listesinin yedeği
  `metadata.calibre.bak` olarak alınır.

### Sorun çıkarsa

- **"No Calibre metadata file found"**: USB ile gönderilen kitapların listesi
  sürücünün kökünde (`E:\metadata.calibre`), kablosuzla gönderilenlerinki
  KOReader'ın inbox klasöründe durur. İkisini birlikte kullanıyorsan KOReader'da
  **Ağ → Calibre → Wireless settings → Inbox folder**'ı sürücünün köküne
  ayarla. Ya da eklentide **Calibre library folder**'dan klasörü elle seç.
- **Kablosuz bağlantı açıkken çalıştırma.** KOReader bağlantı sırasında eski
  listeyi geri yazabilir. Önce bağlantıyı kes.
