# Development

## How it works

The plugin reads DPD's official mobile SQLite database and renders every view
as a small HTML document in KOReader's MuPDF-based `ScrollHtmlWidget`, the
same widget behind KOReader's dictionary popup. Tapping an internal `dpd:`
link updates the view state and rebuilds the HTML, keeping the scroll
position. MuPDF supplies wrapping, bold and e-ink paging for free.

| Module | Role |
|---|---|
| `main.lua` | Lifecycle, menus, settings and KOReader entry points |
| `dpd/db.lua` | Opens the database read-only and runs the core lookup queries |
| `dpd/lookup.lua` | Turns rows into a result model: senses, grammar, compound analyses, references, variants, roots and abbreviations; caches results |
| `dpd/normalize.lua` | Selection cleanup, DPD's query normalisation and the diacritic-free fuzzy key |
| `dpd/sortkey.lua`, `dpd/deconstruct.lua` | Sense ordering and compound analysis parsing |
| `dpd/navigation.lua`, `variant.lua`, `traditional.lua` | Similar forms, variant readings and the traditional lemma shown in entries |
| `dpd/suggest.lua`, `velthuis.lua`, `history.lua` | **Look up a word** suggestions, Velthuis input and Recent lookups |
| `dpd/popup.lua`, `direct.lua` | Reading-selection routing and HTML preparation shared by the popup and the budget check; the long-press wrapper |
| `dpd/compat.lua`, `db_compat.lua`, `diag.lua`, `about.lua` | KOReader and database compatibility checks, the diagnostic log and the About text |
| `dpd/frequency_layout.lua`, `rootmatrix_rules.lua` | Tables generated from DPD's source by `tools/gen_frequency_layout.py` and `tools/gen_root_matrix_rules.py`; do not edit by hand |
| `dpd/inflection.lua`, `frequency.lua`, `sutta.lua`, `rootinfo.lua`, `rootmatrix.lua`, `families.lua`, `dictionaries.lua`, `english.lua` | The views opened from an entry, each read only when opened |
| `ui/dpd_render.lua` | Model and view state → HTML; pure, so it is tested without KOReader |
| `ui/dpd_viewer.lua` | The popup: title bar, navigation stack, link dispatch and child popups |
| `ui/dpd_input.lua` | The **Look up a word** dialog |

Dependencies run one way: `ui` → `lookup` → `db`. The one exception is
`dpd/popup.lua`, which uses `ui/dpd_render.lua` so the headless budget check
builds the same HTML as the real popup.

**Data facts the code relies on:**

- The mobile database ships DPD's whole `lookup` table (headwords, grammar
  parses, compound analyses, spelling and "see" references, variants, roots,
  abbreviations and English→Pāḷi data) plus an indexed `fuzzy_key`, and
  nearly all `dpd_headwords` columns. It also bundles the other dictionaries,
  families, roots, sutta information and inflection templates, which is why
  it is about 1 GB. The family tables are optional: without them lookup and
  details still work, and a family that can't be read is reported without
  replacing the entry.
- Senses are **not** in stored order. Like the web app, the plugin sorts by
  DPD's `pali_sort_key`, ported literally: its regex tries `k` before `kh`,
  so aspirates are never matched as digraphs. Keep that quirk, or the order
  stops matching dpdict.net.
- A sense's meaning is `meaning_1`, plus `; lit. meaning_lit` when present.
  Entries without `meaning_1` aren't fully edited yet, and DPD shows
  `meaning_2` for them.
- Compound analyses are JSON arrays of strings joined by `+`, at most five,
  already ranked: analysis 1 is DPD's preferred one. The plugin opens the
  first analysis that adds to the headwords. Each alternative is compared
  with the headwords and that initial analysis, independently of the other
  alternatives. Closing the initial analysis does not change this comparison.
  Manual corrections have irregular spacing and some components contain
  spaces, so split on `+` and trim each part; never split on whitespace.
- `spelling` and `see` contain displayable correction/referral text, not
  required lookup targets. Nonblank notes count as hits and retain their text
  even when optional exact navigation cannot resolve a target. Corrections
  can contain spaces; do not split them or substitute approximate definitions.
  A record with a correction and manuscript notes is not variant-only.
- The exporter sets `journal_mode=WAL`, which persists in the file. The plugin
  opens with `SQ3.open(path, "ro")` and `PRAGMA query_only=1`, and never
  changes the file, not even its journal mode.

**KOReader integration.** `ReaderDictionary:addToDictButtons` adds the **DPD**
button to the dictionary popup. `ReaderHighlight:addToHighlightDialog` adds it to
the selection menu without patching anything. Direct mode (**DPD on word
long-press**) is the only patch: an instance-level wrapper around
`ReaderDictionary:onLookupWord` that falls through to the normal dictionary
when DPD has no match, and is removed when turned off.

## Unit tests

Pure Lua logic uses LuaJIT and Busted. Install Busted for LuaJIT
(`luarocks --lua-version=5.1 --local install busted`, with LuaRocks set up
for LuaJIT) and run that copy. A Busted installed for a newer Lua, such as
Homebrew's, fails about 18 specs with errors unrelated to the code.

```sh
~/.luarocks/bin/busted spec
python3 -m unittest discover -s spec -p 'test_*.py'
python3 tools/probe.py /path/to/dpd-mobile.db
```

`.github/workflows/portable.yml` runs the Busted and Python tests (and each
spec file on its own, to catch order dependencies) and builds the plugin ZIP
for every push and pull request; `probe.py` needs a database, so it isn't
run there. It uses Debian 13 with pinned
LuaJIT, Busted and JSON package versions. Native KOReader, official-data gates
and physical-device checks remain separate; portable CI does not certify them.

The sort-key tests use 500 real lemmas and golden keys generated by DPD's
Python implementation. Compound tests cover substitutions, insertion,
deletion, resegmentation, repeated parts and irregular manual-correction
spacing. Rendering/navigation and direct-wrapper tests run without KOReader.

`tools/probe.py` reports the database file's persisted journal format
separately, because an immutable connection can report `delete` for a WAL
file.

## Native KOReader checks

These checks run inside a real KOReader, using its own LuaJIT, SQLite, JSON
and MuPDF. [Testing in KOReader](KOREADER_RUNBOOK.md) explains how to set up a
disposable runtime on macOS or Linux, run checks in isolated profiles at the
target screen sizes, and review the screenshots. Before each book-taking
check, prepare the runbook's fresh temporary `DPD_BOOK` copy and pass
`"$DPD_BOOK"` as the book argument; a fresh profile alone does not isolate
metadata stored beside a book.

### The checks

For KOReader SQLite, JSON, MuPDF, popup and lifecycle checks, from the
runtime directory:

```sh
SDL_VIDEODRIVER=dummy DPD_TEST_FONT_SIZE=16 ./luajit /path/to/dpd.koplugin/tools/check_koreader.lua \
  /path/to/dpd.koplugin /path/to/dpd-mobile.db /existing/screenshot/directory
```

Repeat with `DPD_TEST_FONT_SIZE=20` and `26`. The check resolves the actual Back
icon asset and invokes the title button to verify parent state and scroll
restoration. The screenshot directory is optional. Tests create and remove tiny
temporary databases for failure/read-only checks; they never change the
official file. The production plugin always uses KOReader's bundled JSON and
SQLite modules.

Run these with the same native LuaJIT setup:

| Script | What it checks |
|---|---|
| `tools/check_db.lua` | Optional schemas, bound batches, all independent fuzzy channels and counts |
| `tools/check_prefix.lua` | Bounded Unicode prefix ranges, literal wildcard/injection inputs, minimal schemas, approximate labels, lookup priority, direct-mode fallback and 20 uncached-model timing samples. Runs with the real SQLite/JSON binding on desktop or device. |
| `tools/check_budget.lua <plugin> <mobile.db>` | 23 fixed cases through shared popup routing/preparation; fresh/cached query, row, logical-payload and HTML-body ceilings; separate database-open budget, lazy-read assertions and informational median/p95 timings. |
| `tools/kindle_check.py` | From your computer over SSH: optionally installs the plugin and restarts KOReader, then long-presses the test book's words on the device through the HTTP inspector (`tools/kindle_drive.lua`) and fetches results and screenshots. See [the quick check](TESTING.md#quick-check-on-a-kindle-over-ssh). |
| `tools/kindle_soak.sh` | On-device soak run over SSH: opens and closes popups through KOReader's HTTP inspector and samples process memory and the settled Lua heap between cycles. See [Running the gate on a Kindle](#running-the-gate-on-a-kindle). |
| `tools/check_budget_failures.py <koreader directory> <plugin> <mobile.db>` | Python process driver using only that KOReader's LuaJIT/SQLite. Checks equal/below ceilings, every budget failure, DB/settings mismatches, caught lazy reads, broken smaller results and compound rows with or without toggles, using disposable profiles/baselines. |
| `tools/check_channels.lua` | The official release's 544 spelling records, the added payloads and their real popup controls, including all 29 forms in a large fuzzy group and page preservation after loading more. Accepts the optional screenshot directory and `DPD_TEST_FONT_SIZE`. |
| `tools/check_selection.lua <plugin> <database> "$DPD_BOOK" [screenshots]` | Actual document selection with disposable ReaderUI settings |
| `tools/audit_book.py <book ...>` | Not a check: every word of real EPUB, PDF, Markdown or text books through the plugin's lookup, compared with a saved baseline. See [Auditing real books](#auditing-real-books). |
| `tools/check_spelling.py` | **Did you mean** ranking on about 3,000 generated typed misses, the working tree against a git ref. See [Checking "Did you mean"](#checking-did-you-mean). |
| `tools/check_reader.lua <plugin> <database> "$DPD_BOOK"` | Opens the test EPUB through the real ReaderUI and plugin loader; checks direct lookup, fallback, the dictionary-popup button and DPD's place on Search's first page |
| `tools/check_lookup_edges.lua` | Correction-only and mixed-channel hits, phrase corrections, literal punctuation-bearing abbreviations, and cache identity against official data |
| `tools/check_book_lookup.lua <plugin> <database> "$DPD_BOOK" [screenshots]` | Real long-presses in the test EPUB with KOReader's Vocabulary builder enabled: a book's own long-press setting and its persistence after reopening, DPD lookups saved once with their context and beneath the popup, reviews opening DPD, and fallbacks announced by KOReader alone |
| `tools/check_lifecycle.lua <plugin> <database> "$DPD_BOOK"` | FileManager connection cleanup, repeated teardown, retained dictionary wrappers, suspend/resume and reader reopening |
| `tools/check_expansion.lua` | In-place toggles on later pages keep the tapped control visible: a compound component sense, a `pacchima` sense switch that closes the sense above, and `dutiyā` grammar parses inserted above their toggle. Accepts the optional screenshot directory and `DPD_TEST_FONT_SIZE`. |
| `tools/check_extremes.lua <plugin> <mobile.db> [screenshots]` | The database's extremes rather than hand-picked words: for each displayed field the three headwords with its longest unbroken word, the three longest headwords with an inflection table, and one headword per whole-word irregular pattern. No word may end past the popup edge in the expanded sense or its table. Run at fonts 26 and 32 on the Paperwhite and at 26 on 600×800, and for each new database release. |
| `tools/check_controls.lua <plugin> <mobile.db> [screenshots]` | Native responsive controls, full-cell taps and article pager boundaries. Accepts `DPD_TEST_FONT_SIZE`. |
| `tools/check_variants.lua <plugin> <mobile.db> [screenshots]` | Walks every `ca` reading window through native tap dispatch, without database reads. |
| `tools/check_resize.lua` | Native SDL screen resizing with an existing popup, preserved navigation/expansions/page and coalesced reflow |
| `tools/check_failure_containment.lua <plugin>` | Real MuPDF/KOReader popup disposal after injected navigation, hit-test, queued handoff/edit and cleanup failures with diagnostics off/on; parent survival, at-most-once cleanup, Help/About with no DB and dynamic metadata, and that a temporary native SQLite DB with a newer schema but the core columns opens read-only. Needs no official DB; run with a disposable `KO_MULTIUSER=1`/`XDG_CONFIG_HOME` profile. |
| `tools/check_input.lua <plugin> <mobile.db>` | The "Look up a word" dialog with KOReader's real InputDialog: empty submission stays open, ID routing, Recent draft restoration, real miss-card Edit search taps in both modes, Cancel/Back and confirmation for history deletion, Velthuis input, pasted-input suggestions (no query before the pause, stale results dropped, cancelled on close), English mode, and searching the other dictionaries (no suggestion queries, Sanskrit Velthuis, exact Sanskrit and DPPN headwords, DPD and Back, the pencil, a miss with Edit search) against a real database |
| `tools/check_ux.lua <plugin> <mobile.db> [screenshots]` | Real File Manager/database recovery and retry, the Database status detour back to recovery, Help, fixed-height empty/unavailable/error suggestion states, MuPDF taps on pager padding, part replacement, similar-form disclosure (the first two open), spaced paradigm and matrix renders. Run at Paperwhite size with fonts 16, 20 and 26 in portrait and 26 in landscape; see the command below. |
| `tools/check_learning.lua <plugin> <database> ["$DPD_BOOK"] [screenshots]` | Native text selection inside DPD, stacked popup ownership/fallback, etymology and exact cross-references, inline component details, family navigation, paradigm tables and the views opened from entries (root details and matrix, English→Pāḷi, frequency, sutta information). Imported dictionary tables must not run past the popup edge at any font. Article parts must stay under 25 screen pages. |
| `tools/check_families.lua` | Optional family schemas, exact numbered members, lazy pages, malformed family handling and official root/word/compound/idiom/thematic-set data |
| `tools/check_inflection.lua` | Every inflection template's shape, a table for every patterned headword in the release, 16 reference form sets matching DPD's generated tables, highlighting and the indeclinable case. Run it against each newly supported database release. |
| `tools/check_inflection_html.lua <plugin> <mobile.db> <full dpd.db>` | Every generated table against DPD's own generated HTML from the full database of the same release, cell by cell: headers, row labels, cell grammar and the exact forms in order. Last run on v0.4.20260531: all 79,556 matched. |
| `tools/check_rootinfo_html.lua <plugin> <mobile.db> <full dpd.db>` | Root details against DPD's generated root info of the same release: every row label and value for every root (bases compared as sets; missing Sanskrit roots displayed as a single dash). |
| `tools/check_frequency_html.lua <plugin> <mobile.db> <full dpd.db>` | Frequency tables against DPD's generated frequency HTML of the same release: every book row's values and row spans. Last run on v0.4.20260531: all 83,687 matched. |
| `tools/check_rootmatrix_html.lua <plugin> <mobile.db> <full dpd.db>` | Root matrices against DPD's generated root_matrix HTML of the same release: categories and rows in order and each row's headwords (as sets; the plugin sorts rows alphabetically). Last run on v0.4.20260531: all 753 roots matched. |
| `tools/gen_root_matrix_rules.py <root_matrix.py>` | Regenerates `dpd/rootmatrix_rules.lua` from DPD's classifier. |
| `tools/gen_frequency_layout.py <frequency_template.js>` | Regenerates `dpd/frequency_layout.lua` from DPD's frequency template. |
| `tools/check_sutta.lua <plugin> <mobile.db>` | Sutta links and labels for every headword against DPD's type rules (canonical names and semicolon/comma-separated aliases), and that no panel shows an empty field. v0.4.20260926: 5,383 headwords. |
| `tools/check_dictionaries.lua <plugin> <mobile.db> [all]` | Other-dictionary articles read page by page: cuts outside tags, characters and comments; pages cover each article; only kept tags, no attributes, balanced; text kept. Plus lookups of sample headwords. v0.4.20260926: all 606,003 articles pass with `all` (about 25 s). |
| `tools/check_sanskrit.lua <plugin> <mobile.db> [outdir]` | Other dictionaries' Sanskrit-equivalent fallback for every headword: exact Pāḷi matches and Edgerton's close spellings unchanged, groups found via Sanskrit exact. Prints the changes per dictionary and their cost; `outdir` gets each change as TSV to read. v0.4.20260926: MW 10,509, Apte 6,959 and Edgerton 2,874 headwords gain entries; about 0.04 ms extra per lookup with Sanskrit words on desktop. |
| `tools/check_search_keys.lua <plugin> <mobile.db> [outdir]` | Search other dictionaries against every MW, Apte and Edgerton headword: each found typed as stored, Apte's `ḥ`/`ṃ` forms found by their MW stems, and a report of Apte headwords the search doesn't reach. See [Dictionary search rules](#dictionary-search-rules). About 30 s. |
| `tools/check_parity_data.lua` | The data assumptions the frequency, sutta, family and other-dictionary views rely on: schemas, vector lengths, sutta names, index use and key formats. |
| `tools/capture_screens.lua <plugin> <db> "$DPD_BOOK" <screenshots>` | Not a check: screenshots of the screens the checks do not capture (reader popups, all other dictionaries, the DPD menu and submenus, dialogs) for a design review. Use the fresh generated README-passage book in [Reviewing screens](KOREADER_RUNBOOK.md#5-reviewing-screens). |
| `tools/contact_sheet.py <out.png> <screens…>` | Pairs screenshots side by side, labelled, for review. Needs Pillow. |
| `tools/capture_compound_cases.lua <plugin> <db> <out>` | Not a check: focused screenshots of compound analyses at font 26, for reviewing compound layout changes. |
| `tools/inspect_lookup_regressions.py` | Not a check: prints what the database holds for a set of reported lookups (lookup rows, fuzzy groups and related forms), for investigating a lookup report. |

`tools/audit_lookup.lua` and `tools/spelling_lookup.lua` are the KOReader-side
runners for `audit_book.py` and `check_spelling.py`; you don't run them
directly.

Run `check_reader.lua` and `check_lifecycle.lua` from a disposable desktop KOReader extraction with
`SDL_VIDEODRIVER=dummy`, `KO_MULTIUSER=1`, and `XDG_CONFIG_HOME` set to a
disposable directory, using a fresh `DPD_BOOK` copy for each run.

Run `check_ux.lua` at Paperwhite size (1264×1680, 300 dpi) with fonts 16, 20
and 26, and in landscape at 26, each with its own profile;
[the runbook](KOREADER_RUNBOOK.md#3-run-isolated-checks) has a loop that does
this. These are desktop layout and interaction checks; physical touch and
e-ink behavior still need a device.

## Auditing real books

The checks above use fixed words. `tools/audit_book.py` runs every word of a
real book through the plugin's own lookup, in KOReader's LuaJIT, and reports
what a long-press would show:

```sh
export DPD_KOREADER=/path/to/koreader DPD_DB=/path/to/dpd-mobile.db  # runtime as in the runbook
python3 tools/audit_book.py /path/to/book.epub [another.pdf ...]
```

It reads EPUBs, PDFs (with PyMuPDF installed; a PDF word ends at a space or
after a dash or curly quote, so `viññāṇaṃ—ime` is `viññāṇaṃ—` and `ime`) and
Markdown or text files, which KOReader shows as plain text like an EPUB.

A run takes about ten seconds for a 180,000-word book. It applies what
KOReader selects on a hold: only the part held when bold or italic starts or
stops inside a word, and the word without ti/nti before a closing quote.
The report sorts Pāḷi words into found, split (a part opens KOReader's
dictionary), long miss (DPD's miss screen with its parts) and missing, and
lists non-Pāḷi words DPD opens on long-press. Words count as Pāḷi inside
`lang="pi"`, in a book whose language is `pi`, or with Pāḷi diacritics.

The first run saves a baseline per book in `test-artifacts/audit/`
(git-ignored), with a report beside it. Later runs list only what changed:
newly missing or found words, a different DPD form, new English grabs. After
reviewing a change, accept it with `--save`. Missing words are DPD coverage,
not failures; the exit status is nonzero only for lookup errors.

Run it after changing lookup, normalization or routing, after downloading a
new DPD release, and before sharing a version, on two or three books: a
plain CST-style text, a bilingual book and an English book with Pāḷi terms.
Keep the books out of the repository; `DPD_AUDIT_BOOKS` can list their paths.

## Checking "Did you mean"

`tools/check_spelling.py` measures the **Did you mean** list after a typed
miss. It makes about 3,000 typed misses from the database (a typo in a
frequent headword, a typo in a random form, a typo typed without diacritics,
and a form ending in ṃ typed without it), looks each up through the plugin's
manual lookup with the working tree and with a git ref, and compares:

```sh
python3 tools/check_spelling.py --koreader /path/to/koreader --db /path/to/dpd-mobile.db [--baseline HEAD]
```

It prints how often the intended word comes first and in the first five,
lookup times, and every case the baseline put first and the working tree no
longer does. Run it after changing `dpd/suggest.lua` or the fuzzy key.

## Bounded searches

Several searches read a capped slice of an index rather than every match, so
they stay fast on an e-reader. The user guide gives the effect (samples,
pages of 20) but not the caps:

- **Look up a word** suggestions (`dpd/suggest.lua`): Pāḷi reads at most
  1,000 rows of the `lemma_1` index. Without diacritics, or when no headword
  matches, it adds approximate forms from at most 200 `fuzzy_key` rows and
  ranks the first 20: up to three when headwords matched, reserving up to two
  places for them, and all six places when none did. Typed diacritics that
  do match headwords get at most one alternative instead, from up to 50 forms
  with the same `fuzzy_key` (`kāla` → ≈ `kāḷa`). English reads up to 200 likely-English keys for one or
  two characters; from three characters, 400 plus 10 for each next letter, so
  that `sama…` forms can't crowd out `same`, plus up to 50 capitalised keys
  for names (`Nibbāna`), and only then keeps keys that have English→Pāḷi
  entries.
- **Did you mean**: one indexed query over about 900 one-edit keys,
  returning at most 200 forms; only the closest 20 are checked for
  headwords.
- Similar forms load 20 at a time, scanning at most 200 rows for a batch.
- Other dictionaries read 20 entries at a time per dictionary; see
  [Dictionary search rules](#dictionary-search-rules) for the key limits.

## Pāḷi lookup rules

DPD's own lookup also rewrites some words. The user guide explains each
([When there's no exact match](USAGE.md#when-theres-no-exact-match),
[Spelling and diacritics](USAGE.md#spelling-and-diacritics)) and gives
their exact limits in [Lookup rules in detail](USAGE.md#lookup-rules-in-detail); this table
records what each rests on and what guards it. Two properties keep them safe
to get slightly wrong: the rewrites in the second group run only after the
exact and similar-form lookups miss, so they never replace a match; and every
result found by one is labelled in the header (`saccan → saccaṃ · ṃ printed
as n before ti`), never shown as an exact match.

| Rule | Rests on | Limits | Checked by |
|---|---|---|---|
| NFC; `ṁ` and `ŋ` as `ṃ`; capitals and diacritics optional | DPD's lookup keys and the exporter's diacritic-free `fuzzy_key` | Diacritic-free matches are similar forms, labelled | `normalize_spec`, `check_channels` |
| Apostrophe and hyphen forms (`bhikkhave’ti`, `akaṭa-anudhammena`); closing-quote `hotī”ti` | DPD's recorded spellings: all 544 official spelling records | Hyphens joined only between Pāḷi letters; a usable hyphenated record is tried before its hyphen-free form | `check_channels`, `check_selection`, `channels_spec` |
| Spelling corrections and "see" notes displayed; available targets followed | DPD's own notes | Text remains valid without a target entry; definitions stay exact | `lookup_edges_spec`, `check_lookup_edges`, `check_channels`, `check_learning` |
| *After a miss:* `ti` split from a following vowel (`tiettha` → `ti + ettha`) | Corpus printing after a closing quote | Not before a consonant, where `ti` can be "three"; not for words in DPD's English index (`tiara`, `ties`) | `prefix_spec`, `kindle_drive.lua`; measured below |
| *After a miss:* final `n` before `ti` as `ṃ` (`saccan` → `saccaṃ`) | Corpus printing of `saccan’ti` | Words of four letters or more, so English `in` is untouched; not for words in DPD's English index (`thin`). English words outside it (`sedan`, `Japan`) still turn into Pāḷi | `prefix_spec`; measured below |
| *After a miss:* final `ñ` or `ṅ` as `ṃ` (`dhammañ` → `dhammaṃ`) | Chanting books' `dhammañ’ca`, `Yaṅ’kiñci` | | `prefix_spec`, `kindle_drive.lua`; measured below |
| *After a miss, manual lookup only:* trailing digits, then one or two trailing letters, removed (`bhikkhu1`, `bhikkhux`) | Footnote numbers and typos | At least four letters, 64 at most, first 20 lookup forms; never on long-press | `check_prefix`, `prefix_spec` |
| *After a miss:* **Did you mean** ranking | DPD's lookup forms | Ranking only, labelled | `check_spelling.py` (about 3,000 generated misses) |
| *After a miss, long-press:* a word of 15 letters or more with Pāḷi diacritics and a known part opens the miss screen, with **Begins with** / **Ends with** parts of five letters or more; without parts it falls back | Unrecorded compounds | Plain parts of the spelling, never an analysis | `prefix_spec`, `result_ui_spec`, `check_book_lookup.lua`, `kindle_drive.lua` |
| Long-press takes any word DPD has, whatever the book's language | — | English words that are also Pāḷi forms (`to`, `the`) open DPD; the per-book setting is the remedy | `audit_book.py` (English grabs per book) |

The three rewrites after a miss were measured in October 2026 on all
1,282,512 lookup forms of v0.4.20260926 and, with `audit_book.py`, on nine
real books (2.3 million words: canon in Pāḷi, Pāḷi–English parallel
translations, English books with Pāḷi citations, a PDF and an OCR text):

- `ti` split: 2 database forms, both English (`tiara`, `ties`) and now
  skipped; 1 book word, correct.
- Final `n`: 7 database forms, all English and now skipped; 1,849 book words,
  1,282 confirmed by DPD's own analyses (`dukkhan` → `dukkhanti` = `dukkhaṃ +
  iti`), 23 wrong (English `sedan`, `divan`, `Roman`, `Japan`, `akin`) and the
  rest not settled by DPD's data.
- Final `ñ`/`ṅ`: no database forms; 8 book words, 6 confirmed, 2 not settled.

`audit_book.py` on real books remains the broadest measure of all the rules
together.

## Dictionary search rules

**Other dictionaries** (from a DPD result) and **Search other dictionaries**
(typed) turn the reader's word into a few search keys. Some keys rest on how
a dictionary writes its headwords, not on Sanskrit grammar, and the
developers don't read Sanskrit, so each rule is listed here with its evidence
from the dictionaries' own data. Numbers are for v0.4.20260926.

| Rule | Applies to | Evidence | Limits |
|---|---|---|---|
| The typed text is tried first, punctuation kept | Typed | DPPN's `Accayasutta (Akodhanasutta)`, WordNet's `e.g.`; all 246,132 MW, Apte and Edgerton headwords are found typed as stored | Text over 100 bytes is cut |
| NFC; soft hyphens removed; `ṁ` and `ŋ` become `ṃ` | Typed | The dictionaries write `ṃ` | |
| Also cleaned as a book selection: quotes and end punctuation | Typed | Pasted `“dhamma,”` | |
| Also lower-cased | Typed | MW `śāriputra` for `Śāriputra` | Only the capitals in `dpd/normalize.lua` |
| Each key also tried with a capital first letter | Both | DPPN and Nyanatiloka capitalize names (`Buddha`) | `Dictionaries.capitalized`: Pāḷi capitals only, not `Ś` `Ṣ` `Ṛ` |
| `ḥ` added after a final vowel, `ṃ` after `a` | Typed | Apte lists a- and i-stem nouns in the nominative (`dharmaḥ`, `phalaṃ`, `agniḥ`) and other stems as stems (`rājan`, `latā`, `nadī`, `guru`). Of 194,013 MW headwords typed, 17,174 find Apte as typed and 10,663 also or only with the ending | Apte's convention, not declension: `guruḥ` is tried and not found. A dictionary with both forms shows both |
| At most five keys | Both | | Typed: the lower-cased literal comes last, so it is dropped first |
| Sanskrit equivalents from DPD's `sanskrit` field | From a result | `check_sanskrit.lua`: 10,509 headwords gain MW entries, 6,959 Apte, 2,874 Edgerton. MW and Apte try them before close spellings, Edgerton only when it has none | A field with `+` or `?` gives none; roots and notes dropped; three words at most. Shown as **via Sanskrit** |
| Close spellings (`word_fuzzy`), marked ≈ | Both | | Only in a dictionary with no exact hit, three at most. Can be coincidences (`ḍama` for `dhamma`) |
| Velthuis Sanskrit sequences (`.r` `"s` `.s`) | Typed, when on | The standard Velthuis scheme | |

Accepted limits, found by `tools/check_search_keys.lua`. The search doesn't
change these; type the dictionary's own spelling:

- 1,990 Apte headwords write `ṃ` where MW writes a nasal letter (`abaṃdhu`
  for `abandhu`, `saṃmūḍha` for `sammūḍha`). 459 share MW's close-spelling
  key (`ṃ` before `p`, `b` or `m`, or at the end), so they can appear marked
  ≈; the other 1,531 don't. Trying `ṃ` for every nasal would reach most of
  them, but it also adds different words as exact matches: `alam` "enough"
  finds Apte's `alaṃ` "scorpion's sting", `sākam` "together" finds `sākaṃ`
  "vegetable", and `asanmati` finds MW's `asaṃmati`.
- 245 Apte headwords are denominative verbs in the third person
  (`abhimukhayati`) where MW has the stem (`abhimukhaya`). This assumes
  readers type the verb as printed, which is found, rather than MW's stem.

No further spelling rules are added. Each one needs Sanskrit judgement that
counts of found headwords can't supply, as the nasal rule showed: it would
have reached thousands of entries and passed every coverage check while
adding wrong ones. Changes to the rules above are compared with
`check_search_keys.lua` (and, for the Sanskrit equivalents,
`check_sanskrit.lua`) before and after, including what a change adds to
searches that already worked. Its report lists Apte headwords spelled like an
MW headword that the search doesn't reach; most are other words.

## Lookup budgets

From the disposable KOReader directory, run the gate without a display or taps:

```sh
./luajit /path/to/dpd.koplugin/tools/check_budget.lua \
  /path/to/dpd.koplugin /path/to/dpd-mobile.db
```

Use KOReader's own LuaJIT and SQLite, never system Lua/SQLite. The committed
`tools/budget_baseline.json` is for official mobile `v0.4.20260926`, schema 7.
It records fixed dictionary sources, ṃ display, popup geometry in em units,
selection options and English miss recovery. A DB/settings mismatch fails
before case measurements. Case order and expectations are fixed in the script.
The selection word `timing` falls back; manual English `timing` is a recoverable
miss in this release. `mind` and `sanskrit` exercise successful English searches.

Each fresh sample creates its own read-only DB connection and model. Each
cached case primes its own connection, result cache and availability probe
before measuring. Both passes use 20 samples per case. Fresh does not mean
the OS filesystem cache is cold. The availability query and HTML preparation
run through `dpd/popup.lua`, also used by the actual plugin/viewer. Selection
fallbacks have zero DPD HTML; normal KOReader dictionary work is outside this
DPD gate.

All four case metrics use exact ceilings: equality or a reduction passes;
any increase fails. Opening has separate query/row/payload ceilings. Expected
routes, visible controls and semantic model fingerprints must still match.
Lazy-read assertions cover initialization too, and cannot be suppressed by
catching an optional-reader error. Updating a baseline still runs those
assertions and checks fresh/cached consistency.

To deliberately record reviewed changes:

```sh
./luajit /path/to/dpd.koplugin/tools/check_budget.lua \
  /path/to/dpd.koplugin /path/to/dpd-mobile.db --update-baseline
git -C /path/to/dpd.koplugin diff -- tools/budget_baseline.json
```

The baseline is replaced only after every case passes. Commit its diff with
the reason for changed costs or results. A new DB release may also require
reviewing the pinned case expectations. `--baseline /path/to/file.json` selects
an alternate baseline for deliberate comparisons or failure tests.

Exercise the gate's failure paths with the same native runtime:

```sh
python3 /path/to/dpd.koplugin/tools/check_budget_failures.py \
  /path/to/koreader /path/to/dpd.koplugin /path/to/dpd-mobile.db
```

Rows count all returned rows across queries, including repeated reads. The
always-on DB counters measure logical payload: UTF-8 text/blob byte lengths,
eight bytes per numeric value, zero for NULL. They exclude column names,
Lua object overhead, SQLite page reads and rows scanned internally. HTML
bytes count the popup body, excluding CSS/native layout. Lookup, HTML-generation
and DB-open median/p95 timings never fail. Neither counts nor body size prove
unchanged query-plan cost, MuPDF layout time, e-ink refresh or long-session
memory. Continue the native popup/reader checks and physical-device acceptance;
an optional SSH run on a Kindle provides device timing evidence.

## Running the gate on a Kindle

The plugin folder holds no `tools/`, so copy the scripts to a separate folder
such as `/mnt/us/dpd-diag/tools`. Over SSH on the device, from KOReader's
directory:

```sh
cd /mnt/us/koreader && ./luajit /mnt/us/dpd-diag/tools/check_budget.lua \
  /mnt/us/koreader/plugins/dpd.koplugin /mnt/us/koreader/data/dpd/dpd-mobile.db \
  --baseline /mnt/us/dpd-diag/tools/budget_baseline.json
```

`--baseline` is needed because the script otherwise looks in the plugin's own
`tools/`. Never pass `--update-baseline` on a device: it would replace the
reviewed desktop baseline with Kindle numbers. Counts and byte ceilings are
platform independent; the timings are the device evidence. `check_prefix.lua`,
`check_parity_data.lua` and `check_db.lua` run the same way.

For popup timing and memory, switch on **Diagnostics → Write diagnostic log**,
start **More tools → HTTP Inspector** and run `CYCLES=2 sh tools/kindle_soak.sh`
on the device. The log's `Popup ready` line gives lookup, build and total
milliseconds per popup; `Settled memory` lines come after a full collection.
Do not force a collection on the popup path: it empties KOReader's caches and
makes the next build several times slower. The inspector has no authentication
and opens a firewall port, so stop it afterwards; KOReader's auto-suspend also
stops it. It cannot send touches, so selection, painting and refresh still
need hands, and sleep/wake needs the power button (ideally in no-framework
mode; see the Kindle results in [Testing](TESTING.md#kindle-results)).

## KOReader compatibility

The README states the minimum KOReader version DPD is tested on.
`dpd/compat.lua` lists KOReader APIs that older releases lack; the plugin
checks them once at startup and, if any is missing, keeps its menu but never
handles a lookup. Add an entry, and raise `Compat.minimum` and the README,
whenever DPD starts relying on a newer KOReader API. A check that fails to run
never disables the plugin, but logs its error through KOReader's ordinary
logger. The HTML viewer is loaded only when displaying a result, after the
compatibility check has run; missing viewer modules cannot prevent the
unsupported-build menu from loading.

Beyond those APIs, DPD relies on KOReader internals that can change without a
missing function to detect. After updating KOReader, rerun the checks listed
for each. They last passed on desktop KOReader v2026.07.2-155-g1c042a9, a nightly
build after the v2026.07.1 release the device results use.

| Internal | Used for | Checked by |
|---|---|---|
| `ReaderDictionary.onLookupWord(word, is_sane, boxes, highlight, link, close_callback)`, wrapped on the instance (`dpd/direct.lua`) | Direct long-press | `check_reader`, `check_lifecycle` |
| `ReaderDictionary:cleanSelection(word, is_sane)` | Saving a long-pressed word as KOReader would | `check_book_lookup` |
| `ReaderDictionary.showDict` and `showNoResultsDialog`, wrapped; `dict_window.dict_close_callback` | Closing a fallback dictionary popup that opens after its caller returns | `check_learning`, `check_failure_containment` |
| `ReaderDictionary:addToDictButtons`; its `_dict_buttons` table for removal | The **DPD** button in the dictionary popup | `check_reader`, `check_koreader` |
| `ReaderHighlight:addToHighlightDialog` / `removeFromHighlightDialog`, `getClearId`, `selected_text` | The selection menu's **DPD** item and clearing the selection | `check_selection`, `check_reader` |
| `WordLookedUp` event, sent by KOReader's dictionary in `stardictLookup` before its lookup coroutine yields | Announcing DPD lookups; skipping a repeat when handing a word to KOReader's dictionary | `check_book_lookup` |
| Vocabulary builder: `onWordLookedUp` as a class method (overridden on the instance during a handoff); `widget.current_lookup_word` set while reviewing | Saving lookups; opening reviews in DPD | `check_book_lookup` (imitates the review tap) |
| Vocabulary builder's storage: the `vocabulary_builder` setting's `enabled`, and `vocabulary_builder.sqlite3` in the settings directory with a `vocabulary` table keyed by `word`, read directly | Not announcing a word it already has, whose "Vocabulary exists" dialog would delay the popup | `check_book_lookup`, `kindle_drive.lua` |
| `doc_settings` `readSetting` / `saveSetting` / `delSetting` | DPD on long-press in this book | `check_book_lookup` |
| `filemanager_menu_order` / `reader_menu_order` `.search` lists | DPD's place on Search's first page | `check_reader` |
| `InputDialog` calls `edited_callback` while it is constructed; `addWidget` | Suggestions under **Look up a word** | `check_input` |
| `ScrollHtmlWidget.htmlbox_widget` (`page_number`, `page_count`, `onTapText`) | Taps, paging and keeping the place | `check_resize`, `check_expansion`, `check_controls` |

The optional diagnostic log (`dpd/diag.lua`) appends to
`data/dpd/dpd-debug.log` and keeps one `.old` file past 1 MB. Disabled, its
calls return at once; keep expensive arguments, such as `Diag.memory()`,
behind `if Diag.enabled`.
Production UI boundaries use `Diag.protect`, which always logs a traceback
through KOReader's logger and returns the original protected-call results.
Links, tap hit-testing, delayed actions and cleanup are independently protected.
Unexpected navigation errors dismiss the affected popup and its descendants;
cleanup callbacks run at most once and a failed dictionary handoff releases
the transferred selection. Expected optional-read failures retain their
existing error/fallback behavior. Do not turn diagnostic instrumentation into
implicit recovery: choose and test an explicit boundary and ownership policy.

The result cache keeps 100 insertions; the expanded-detail cache separately
keeps 100 insertions. Both are FIFO. Frames may retain evicted details while
displaying them; reopening an evicted detail fetches it again. Suspend and
database teardown release the lookup object. Database status distinguishes
the structural column checks from validated schema/release metadata; unknown
metadata is advisory and does not reject compatible minimal databases.

## Packaging

```sh
python3 tools/package.py
```

This writes `dist/dpd-koplugin-<version>.zip`: the plugin source, reader
guides and screenshots, `LICENSE`, `LICENSE-DPD` and `NOTICE`. It packages
the working tree, uncommitted edits included, so release builds come from CI.
Only reader-facing guides and the README's
screenshots are shipped; the guides link only to each other and those images,
so the links work offline. Building twice gives byte-identical files.

The device test book, `docs/dpd-test-book.epub`, is committed rather than
released, so testers can download it from the repository. After changing its
words in `tools/make_test_book.py`, regenerate it:

```sh
python3 tools/make_test_book.py
```

A packaging test fails if the committed book and the script disagree.

## Releasing

1. Bump `dpd/version.lua` and update the README and guides if behaviour
   changed. Commit, push and wait for **Portable checks** to pass.
2. Run the native KOReader checks that the change calls for (see
   [the runbook](KOREADER_RUNBOOK.md#4-which-checks-to-run)), and the Kindle
   [quick check](TESTING.md#quick-check-on-a-kindle-over-ssh) before a major
   release.
3. Tag the commit and push the tag:

   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

   `.github/workflows/release.yml` then checks that the tag matches
   `dpd/version.lua`, reruns the portable checks, builds the ZIP and creates
   the GitHub release with the ZIP and its `SHA256SUMS`. Edit the generated
   release notes on GitHub if needed.

## README screenshots

`docs/images/hero.png`, `find.png` and `deeper.png`, and their `-dark`
versions, come from desktop KOReader:

```sh
python3 tools/readme_screenshots.py --db /path/to/dpd-mobile.db
```

It copies the macOS app's `koreader` directory and the database to a
temporary folder, then runs `tools/readme_capture.lua` with two profiles,
both at the Paperwhite's 1264×1680 resolution and 300 dpi. The `paperwhite`
profile uses normal popup type; `large-type` uses larger type for the slim
tiles. The lookup dialogs also come from the full Paperwhite screen.
The capture long-presses words in a short Pāḷi
book, types others into **Look up a word** and follows popup links as a
reader would. The script then crops, zooms and arranges the screens into
tiles, scaling each so body text comes out about the same size. Popup cards
trim the captured outer black frame and use a subtle warm-grey border,
rounded corners and a soft shadow; the UI text stays as captured. It saves
255-colour PNGs with transparent rounded corners, once per theme in `THEMES`.
The dark versions tone each screenshot like KOReader's night mode, mapping
paper to a warm dark card and ink to cream, and darken the saffron tiles to
ember; the README's `<picture>` elements show them in GitHub's dark theme.
It needs Pillow and, by default, the macOS app at
`/Applications/KOReader.app`. Always pass `--db`: the default path is an
ignored local copy. Pass `--koreader` or `--fonts` to use other copies;
otherwise it downloads Inter and Vollkorn (OFL). `--keep <dir>` saves the
captures and `--shots <dir>` recomposes from them without KOReader. The
capture names DPD v0.4.20260926 headword ids and the crops fit that data, so
check both after a database update. The same cached captures, font files and
Pillow version reproduce the images byte for byte.

The hero uses a separate `paperwhite/compound-book.png` capture taken after
word selection but before the dictionary opens, plus `compound.png` and
`hero-senses.png`. Its angled device bezel and shadows are drawn by Pillow;
all book, dictionary and grammar text comes from real KOReader screenshots.
The foreground popup stays flat for readability. Older capture caches without
these additional files must be refreshed once.

For hero-only layout iteration, retain captures and fonts in an ignored folder:

```sh
python3 tools/readme_screenshots.py --fonts <font-directory> --keep test-artifacts/readme-hero/shots --only hero
python3 tools/readme_screenshots.py --fonts <font-directory> --shots test-artifacts/readme-hero/shots --only hero
```

The font directory must contain `Inter.ttf` and `Vollkorn.ttf`. Headings use
Vollkorn semibold, sized to Inter's cap height on Inter's baselines; supporting
copy uses Inter, which also covers ṁ. `--only` selects
the image to render; a fresh capture still collects all screens. The other
README images are not rewritten when `--only hero` is used. Review the hero at
880 px wide and at mobile width, including its full-size README link, after
changing crops or font sizes.

The search image also needs `large-type/find-english.png` and
`large-type/find-similar.png`. It combines these with the Paperwhite typing
dialog and cropped spelling/Velthuis captures. Refresh older caches that
used narrow or small screens, then use `--shots <dir> --only find` for
layout iteration.
Recent lookups remain documented in the README rather than shown as a tile.

### Social preview

`docs/images/social-preview.png` is the 1280×640 card that link previews
show. The same script renders it from the hero's `compound-book.png` and
`compound.png` captures, light theme only:

```sh
python3 tools/readme_screenshots.py --fonts <font-directory> --shots <dir> --only social
```

All text and the popup stay inside GitHub's recommended 80 px margin; only
the Kindle runs past it. `docs/images/dpd-logo.png` is DPD's logo,
rasterised from its SVG and cut to the circle. The release ZIP leaves out
both files. After regenerating, upload the card under **Settings → General →
Social preview**; GitHub keeps the upload, not this file.
