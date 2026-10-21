# Digital Pāḷi Dictionary for KOReader

[![Latest release](https://img.shields.io/github/v/release/digitalpalidictionary/dpd-koreader?label=release)](https://github.com/digitalpalidictionary/dpd-koreader/releases/latest)

**Understand a Pāḷi word or compound in one lookup and keep reading.**
A KOReader plugin for the
[Digital Pāḷi Dictionary](https://www.dpdict.net/) (DPD).
Long-press a word to see its meanings, grammar and compound parts without
leaving your book. Needs KOReader v2026.07 or newer.

<p><a href="docs/images/hero.png"><picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/hero-dark.png">
  <img src="docs/images/hero.png" alt="DPD in KOReader: compounds explained in one lookup, word senses, declension and conjugation tables, and typical 50 ms Kindle lookups">
</picture></a></p>

**[Install](#install)** · [Using it](#using-it) · [User guide](docs/USAGE.md)

## Highlights

- **Compounds, explained.** Brief meanings open for the first analysis that
  adds to the headwords, with alternatives a tap away. Expand a numbered
  sense in place or open its full entry.
- **Every sense in one view.** Explore meanings in DPD's order, with grammar,
  examples and notes a tap away.
- **Fast on Kindle.** About 50 ms for a typical lookup and 125 ms for a
  five-analysis compound on a Paperwhite 12th generation, excluding the
  e-ink refresh. [See the measurements](docs/TESTING.md#kindle-results).
- **Follow a word without losing your place.** Hold a word or select a phrase
  inside an entry to explore it; close the popup to return.
- **Recognise inflected forms.** See the selected form's grammar and headword,
  then explore its declension or conjugation table.
- **Keep your usual dictionary close.** Open it with one tap, or let KOReader
  use it automatically when DPD has no match.

### Find any word

<p><a href="docs/images/find.png"><picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/find-dark.png">
  <img src="docs/images/find.png" alt="English to Pāḷi for peace, similar forms and spelling suggestions, suggestions as you type, Velthuis input, and saṃ, saṁ and saŋ finding the same word">
</picture></a></p>

- **Suggestions as you type** in **Look up a word**, the most common first.
  Without diacritics, close matches are marked ≈, so `nana` offers ñāṇa.
- **English → Pāḷi.** Type an English word to list the Pāḷi words whose
  meaning has it.
- **Close spellings, never silent swaps.** When there is no exact match, DPD
  offers clearly labelled similar forms and attested manuscript readings, or
  words one letter away. It never swaps in a different word without telling
  you.
- **Velthuis input and recent lookups.** Type `sa.msaara` for saṃsāra without
  a Pāḷi keyboard (turn it on under **Display and input**), and look up any of
  your last 50 words again.

### Go deeper

<p><a href="docs/images/deeper.png"><picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/deeper-dark.png">
  <img src="docs/images/deeper.png" alt="Frequency of bhikkhu in the CST, BJT and SYA editions, sutta information, the root matrix of √gam, kāye in other dictionaries, the compound family of citta, and the thematic set of the five aggregates">
</picture></a></p>

- **Declension and conjugation tables.** Every inflected headword's full
  table, with the form you looked up marked and every form linked.
- **Frequency.** How often a headword and its forms occur in each book of
  the canon and its commentaries, by edition.
- **Related words.** Root and word families, compounds, idioms and thematic
  sets, a page at a time; tap a member to open its entry.
- **Roots and suttas.** A root's details and its matrix of every word built
  from it; for a sutta, its place in each edition, references and parallels.
- **Other dictionaries.** One tap looks the word up in up to nine other
  dictionaries bundled with DPD, such as the Critical Pali Dictionary, the
  PTS Pāḷi-English Dictionary, Nyanatiloka's Buddhist Dictionary, Edgerton
  and Monier-Williams. Choose
  which in the DPD menu, or search them directly for a Sanskrit word or a
  name with **Search other dictionaries**.

## Install

You need **KOReader v2026.07 or newer** and about **1.1 GB of free space** for
the dictionary database. KOReader runs on Kobo, PocketBook and Android
e-readers and on macOS and Linux computers, and technically minded users also
run it on a Kindle. The plugin is tested on a Kindle Paperwhite, an inkBOOK
Solaris (Android), and macOS and Linux desktops. On an older KOReader, DPD
stays off and its menu says why; your normal dictionary keeps working.

1. **Plugin.** Download `dpd-koplugin-<version>.zip` from the
   [latest plugin release](https://github.com/digitalpalidictionary/dpd-koreader/releases/latest)
   and extract it into `koreader/plugins/` on the device, so that this file
   exists:

   ```
   koreader/plugins/dpd.koplugin/main.lua
   ```

2. **Database.** Download `dpd-mobile-db.zip` from the
   [latest official DPD release](https://github.com/digitalpalidictionary/dpd-db/releases/latest)
   (about 200 MB). Extract it on your computer and copy `dpd-mobile.db` (about
   1 GB) to:

   ```
   koreader/data/dpd/dpd-mobile.db
   ```

   Create the `data/dpd` folder if it doesn't exist. The folder must be
   writable, wherever you keep the database (see **Read-only** under
   [Good to know](#good-to-know)). This version of the
   plugin was tested with DPD v0.4.20260926 (schema 7); newer releases work
   as long as **Database status** reports the core columns OK.

3. **Restart.** Eject the device and restart KOReader. If external plugins are
   disabled, enable them under Plugin management and restart again.

4. **Check.** Open **Search → Digital Pāḷi Dictionary → Database status**.
   It should report core columns OK. If you stored the
   database somewhere else, in a writable folder, use **Choose database file**
   and long-press the `.db` file.

### Updating

- **Plugin.** Exit KOReader, replace `koreader/plugins/dpd.koplugin` with the
  folder from the new zip (delete the old folder first), and restart. Your DPD
  settings and recent lookups are kept: they're stored in KOReader's own
  settings, not in the plugin folder.
- **Database.** Exit KOReader, replace `dpd-mobile.db` with the new one and
  delete any `dpd-mobile.db-wal` and `dpd-mobile.db-shm` files beside it, then
  restart. **Database status** shows the new release.

## Using it

- **Long-press a word.** If DPD has it, DPD opens immediately. If not, your
  normal dictionary opens instead, except for very long Pāḷi words: DPD
  first shows the beginning and ending parts it knows.
- **Tap to expand.** Tap a ▸ sense or compound analysis to see details in
  place; the popup stays on the page you tapped. Tap an underlined word to
  open it, and use Back to return with your place kept.
- **KOReader dictionary**, a button below the entry, closes DPD and opens the
  same word in KOReader's usual dictionary. **Other dictionaries** sits beside it.
- **Edit the lookup** with the pencil beside the title, as in KOReader's own
  dictionary: tap for the word you selected, hold for the form DPD matched.
- **Look up a word** in the DPD menu searches manually. Drag selections also
  get a DPD button.
- **Prefer your usual dictionary first?** Turn off **DPD on word long-press**.
  Your normal dictionary then opens first and has a **DPD** button.

Diacritics and capitals are optional when you type: `Buddha` finds `buddha`,
`nana` suggests ñāṇa, and `saṁ`/`saŋ`/`saṃ` all match.

## Good to know

- **English books.** **DPD on word long-press** doesn't check the book's
  language, and some short Pāḷi forms such as `to` are also English words. In
  an English book, turn off **DPD on long-press in this book** in the DPD menu;
  other books keep DPD.
- **Vocabulary builder.** KOReader's Vocabulary builder saves the words DPD
  looks up in a book, when its own setting is on.
- **Apostrophes and hyphens.** KOReader decides where a selected word starts
  and ends, so a long-press on `bhikkhave’ti` or `akaṭa-anudhammena` may
  select only one part, depending on the device. DPD recognises the whole
  form: drag across it, or type it in **Look up a word**.
- **Read-only.** The plugin never modifies the database. SQLite creates
  small `-wal` and `-shm` files next to it, which is normal, and won't open
  the database if it can't, so its folder must be writable.

## Troubleshooting

- **DPD never opens:** check **Search → Digital Pāḷi Dictionary → Database
  status**. If the database isn't found, use **Choose database file**. Make
  sure external plugins are enabled.
- **A long-press picks only part of the word:** use **Look up a word** in the
  DPD menu.
- **Something crashed or looks wrong:** turn on **Help → Diagnostics →
  Write diagnostic log** in the DPD menu and repeat what you did (restart
  KOReader first if the problem happens at startup). The log is
  `koreader/data/dpd/dpd-debug.log`, or open **Help → Diagnostics → Show
  diagnostic log**. It records the words you look up, links you tap, timings
  and errors, so turn it off afterwards.

More in the [user guide](docs/USAGE.md#troubleshooting).

## Uninstall

Exit KOReader, delete `koreader/plugins/dpd.koplugin` and restart. To remove
the database and diagnostic log too, delete `koreader/data/dpd/`.

## Documentation

- [User guide](docs/USAGE.md): how entries, compounds, similar forms and
  spellings behave, plus troubleshooting.
- [Testing and feedback](docs/TESTING.md): Kindle measurements, a device
  checklist with a test book, and how to report problems.

The plugin download includes these guides, so the links work offline.
Developer notes (`docs/DEVELOPMENT.md`) are in the source repository.

## Contributing

Bug reports and suggestions are welcome as
[GitHub issues](https://github.com/digitalpalidictionary/dpd-koreader/issues); see
[reporting feedback](docs/TESTING.md#reporting-feedback) for what to include.
For code changes, the [source repository](https://github.com/digitalpalidictionary/dpd-koreader)
has `docs/DEVELOPMENT.md`, covering the layout, tests and packaging, and
`docs/KOREADER_RUNBOOK.md`, showing how to check a change in a real KOReader
on your computer. KOReader only loads plugin folders whose names end in
`.koplugin`, so clone it under that name:

```sh
git clone https://github.com/digitalpalidictionary/dpd-koreader.git dpd.koplugin
```

## Licensing and attribution

This project is under two licenses. The plugin code is under the
[MIT License](LICENSE), and its Lua source is included in the download. This
includes the parts ported from DPD's code, which DPD's maintainer agreed could
be MIT. Dictionary data stays under DPD's license.

**Dictionary data:** Digital Pāḷi Dictionary, © Bodhirasa Bhikkhu, is licensed
under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
See [DPD](https://www.dpdict.net/) and its
[source repository](https://github.com/digitalpalidictionary/dpd-db). The
database is downloaded separately from DPD's official releases and is not
included with this plugin. Screenshots, examples and test fixtures that
reproduce dictionary data keep the DPD license. The screenshots use DPD
v0.4.20260926 and were cropped, zoomed and arranged for this page; the hero
places real KOReader screenshots in a drawn device frame. Other dictionaries bundled with DPD may have their
own terms; see DPD for their provenance. Full notices are in
[NOTICE](NOTICE) and [LICENSE-DPD](LICENSE-DPD).

This plugin reads the official data and follows DPD's conventions for sorting
senses and building meanings. In KOReader, **Help → About & licenses** in the
DPD menu shows attribution and the open database's version.
