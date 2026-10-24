# Testing in KOReader

How to run the plugin's checks inside a real KOReader on a Mac or a Linux
computer, without a display and without touching your own KOReader settings.
The checks use KOReader's own LuaJIT, SQLite, JSON and MuPDF, so they test the
plugin as KOReader runs it. For what each check covers, see the
[script table in Development](DEVELOPMENT.md#native-koreader-checks).

The checks write screenshots from KOReader's framebuffer, but they can't test
touch accuracy, the e-ink refresh or sleep and wake. Those still need a device;
see the [device checklist](TESTING.md#device-checklist).

You need Python 3, the `sqlite3` command-line tool and, on a Mac, the
[KOReader app](https://github.com/koreader/koreader/releases) in
`/Applications`. Screenshot tools also need Pillow (`pip install pillow`).

## 1. Get a KOReader runtime

Use a copy, never your installed KOReader: running a check writes settings
and caches into the runtime directory.

**macOS.** Copy the app's runtime; no download is needed, and its `luajit` is
native on Apple silicon:

```sh
DPD_KOREADER=$(mktemp -d /tmp/dpd-runtime.XXXXXX)/koreader
cp -R /Applications/KOReader.app/Contents/koreader "$DPD_KOREADER"
```

**Linux x86_64.** Extract the official release (about 30 MB):

```sh
DPD_TEST_ROOT=$(mktemp -d /tmp/dpd-runtime.XXXXXX)
mkdir "$DPD_TEST_ROOT/native"
curl -fsSL \
  https://github.com/koreader/koreader/releases/download/v2026.07.1/koreader-linux-x86_64-v2026.07.1.tar.xz \
  | tar -xJ -C "$DPD_TEST_ROOT/native"
DPD_KOREADER="$DPD_TEST_ROOT/native/lib/koreader"
```

The Lua runtime is in `native/lib/koreader`, not `native/koreader`.

Either way, check that the directory has `setupkoenv.lua` and `luajit`, and
run every script from it, so `require("setupkoenv")` finds KOReader's
libraries, fonts and frontend modules.

## 2. Get the database and the plugin

Point `DPD_DB` at a `dpd-mobile.db`. The lookup budget gate is pinned to the
official mobile release v0.4.20260926 (schema 7); other releases are fine for
smoke tests but won't pass that gate. Check a file's release with:

```sh
sqlite3 "$DPD_DB" "SELECT value FROM db_info WHERE key = 'dpd_release_version'"
```

Point `DPD_PLUGIN` at your checkout. KOReader only loads a plugin from a
directory whose name ends in `.koplugin`, so clone into `dpd.koplugin` (a
plain clone is named `dpd-koreader`). A checkout or worktree named anything else
fails `check_learning`, `check_reader` and `capture_screens` with "must
discover the plugin". Put extra worktrees at, say, `/tmp/wt/dpd.koplugin`.

Keep the runtime, database, screenshots and temporary books outside the checkout.

Before each check that takes a book, copy the committed test EPUB into a fresh
temporary directory and pass `"$DPD_BOOK"` as its book argument:

```sh
DPD_BOOK_DIR=$(mktemp -d /tmp/dpd-book.XXXXXX)
DPD_BOOK="$DPD_BOOK_DIR/dpd-test-book.epub"
cp "$DPD_PLUGIN/docs/dpd-test-book.epub" "$DPD_BOOK"
```

Copy only the EPUB, without its `.sdr` folder. KOReader writes book metadata
beside the book even with a fresh profile, so recreate this copy for each
check. Keep the same copy through that check's internal closes and reopens.

## 3. Run isolated checks

- `SDL_VIDEODRIVER=dummy` supplies a virtual screen without a display.
- `KO_MULTIUSER=1` with a fresh `XDG_CONFIG_HOME` per run isolates global
  settings, caches and first-run state. Create the profile directory first:
  KOReader doesn't create missing parent directories. Book metadata stays
  beside the temporary `DPD_BOOK` prepared above.
- `EMULATE_READER_W`, `EMULATE_READER_H` and `EMULATE_READER_DPI` set the
  screen size; `DPD_TEST_FONT_SIZE` sets the DPD popup font.

This runs `check_ux.lua` at the target device's portrait and landscape sizes,
each with its own profile and screenshot folder:

```sh
DPD_EVIDENCE=$(mktemp -d /tmp/dpd-evidence.XXXXXX)
cd "$DPD_KOREADER"

run_ux() {
    local name="$1" font="$2" width="$3" height="$4" dpi="${5:-300}"
    local out="$DPD_EVIDENCE/$name" profile="$DPD_EVIDENCE/profiles/$name"
    mkdir -p "$out" "$profile" || return 1
    if ! SDL_VIDEODRIVER=dummy KO_MULTIUSER=1 XDG_CONFIG_HOME="$profile" \
        EMULATE_READER_W="$width" EMULATE_READER_H="$height" \
        EMULATE_READER_DPI="$dpi" DPD_TEST_FONT_SIZE="$font" \
        ./luajit "$DPD_PLUGIN/tools/check_ux.lua" \
        "$DPD_PLUGIN" "$DPD_DB" "$out" > "$out/run.log" 2>&1; then
        cat "$out/run.log"
        return 1
    fi
    grep '^PASS' "$out/run.log"
}

run_ux paperwhite16 16 1264 1680 && \
run_ux paperwhite20 20 1264 1680 && \
run_ux paperwhite26 26 1264 1680 && \
run_ux paperwhite-landscape26 26 1680 1264
```

Other checks run the same way; the comment at the top of each script gives its
arguments. When a run fails, read its traceback and decide whether it is a
plugin defect, a missing dependency or an outdated expectation in the check.

Run at most about six native checks at once against one database: eight
together have failed with `database is locked`, then passed alone.

### Screen profiles

The target device is a Kindle Paperwhite (12th generation).

| Profile | Width × height | DPI | DPD fonts |
|---|---|---|---|
| Paperwhite | 1264×1680 | 300 | 16, 20, 26 |
| Paperwhite landscape | 1680×1264 | 300 | 26 |
| Small screen (optional) | 600×800 | KOReader's default (unset `EMULATE_READER_DPI`; `run_ux` always sets it) | 26 |

Fonts 16–20 are normal reading sizes, 26 is the large-font edge and 12 the
compact edge. A smaller screen adds little: KOReader scales the popup font
with DPI, so the Paperwhite popup holds about as many characters per line as
600×800 does. Screen sizes are pixels, not a calibrated physical device.

## 4. Which checks to run

In order of value per minute:

1. `check_ux.lua`: database recovery, the Database status detour, Help,
   suggestion states, pager hit areas, similar-form disclosure and dense
   links.
2. `check_learning.lua` with the test book: entry views, other dictionaries
   (including table clipping and article page counts), frequency, sutta
   information and selection inside popups.
3. `check_input.lua` and `check_channels.lua`.
4. `check_failure_containment.lua`, which needs no official database.
5. `check_budget.lua`, then `check_budget_failures.py`, with the existing
   ceilings. The latter is a Python script run from the checkout, not with
   `./luajit`: `python3 tools/check_budget_failures.py "$DPD_KOREADER"
   "$DPD_PLUGIN" "$DPD_DB"`. A render that passes never justifies raising a ceiling; see
   [Lookup budgets](DEVELOPMENT.md#lookup-budgets).

When data, dictionary handoff or lifecycle code changed, add
`check_dictionaries.lua … all` (all 606,003 articles, about 25 s),
`check_sanskrit.lua`, `check_search_keys.lua`, `check_families.lua`, `check_inflection.lua`, `check_sutta.lua`,
`check_reader.lua`, `check_book_lookup.lua`, `check_lifecycle.lua` and
`check_resize.lua`. When rendering or the database release changed, run
`check_extremes.lua` at fonts 26 and 32 in the Paperwhite profile and at 26 on the small screen.
When `dpd/suggest.lua` changed, run `check_suggest_recall.lua` (a few
seconds) before and after the change and compare how often headwords with
ṅ ḍ ṇ ḷ ṃ appear in the suggestions, typed as KOReader's keyboard can.
When English lookup or autocomplete changed, also run
`check_english_case.lua "$DPD_PLUGIN" "$DPD_DB"`. It checks English case,
punctuation and diacritics, the index fold across all English keys, and
bounded autocomplete reads with the real SQLite binding.
When popup keyboard handling changed, run
`check_keyboard.lua "$DPD_PLUGIN" "$DPD_DB" "$DPD_EVIDENCE"` with a fresh
profile. It sends native key events and captures the visible link focus;
desktop results do not establish physical D-pad or assistive-technology behavior.

For each book-taking check, use a fresh `DPD_BOOK` copy from
[the setup above](#2-get-the-database-and-the-plugin).

## 5. Reviewing screens

The checks capture popups only. For a full review, also run
`tools/capture_screens.lua`, which captures the screens no check reaches: the
reader popups, all nine other dictionaries, a long article in the middle of
its second part with the part buttons (`dict-article-mid`), the DPD menu and
submenus, Gesture manager's General and Reader lists with DPD's actions and
the notice the long-press toggle shows (`gesture-*`), dictionary details,
Database status, About, Help, confirmations, diagnostics and the input dialog.
It leaves KOReader's Gestures plugin on for that. Together with the screenshot
folders of `check_ux`, `check_learning`, `check_channels`, `check_input`,
`check_expansion`, `check_controls` and `check_variants`, that gives about 85
screens.
`check_updater` adds the **Check for updates** screens: the update dialog,
both QR codes, database status, a failed install, the restart prompt and the
background notice. It serves its own fake releases, so it needs no network.

`capture_screens.lua` reads the README's sutta passage rather than the test
book. Generate it in a fresh temporary directory for each capture, from the
checkout (needs Pillow):

```sh
DPD_BOOK_DIR=$(mktemp -d /tmp/dpd-capture-book.XXXXXX)
DPD_BOOK="$DPD_BOOK_DIR/sutta.epub"
python3 -c "import sys, pathlib; sys.path.insert(0, 'tools'); import readme_screenshots as r; r.write_book(pathlib.Path(sys.argv[1]))" "$DPD_BOOK"
```

Pass `"$DPD_BOOK"` as the book argument to `capture_screens.lua`.

- Pair screens with `tools/contact_sheet.py` to compare before and after.
- Capture the first and last screen of long paged views. Treat MuPDF page
  counts as layout measurements, not reading time.
- Before proposing a CSS fix, try it: a one-line change, re-rendered and
  reverted, turns a guess into a proven fix. After implementing, rerun the
  same captures, compare pairwise and rerun `check_budget.lua`.

Known worst cases in DPD mobile v0.4.20260926:

| Record | Why it is useful |
|---|---|
| `ca` | Largest variant list: 1,679 readings |
| `dhamma 1.01` | Compound family with 578 members |
| `pacchima` | Eight ordered senses |
| `nnāṭṭā` | 29 similar forms |
| `sabba` | Wide three-gender declension |
| `akkandati` | Verb conjugation |
| `good` | 38 English→Pāḷi results |
| `tissa` | Proper-names group with 47 entries |
| `paticcasamuppāda` (Nyanatiloka) | Widest imported table |
| Longest CPD article (the bibliography) | 432,776 bytes in 27 parts |
| `bhikkhave’ti`, `akaṭa-anudhammena` | A long-press selects only one side |
| `999999999` | Missing numeric ID |
| Missing database → Database status | Recovery detour |
| Schema 999 with the core columns | A newer database opens without warning |

Problems found on screens rather than by checks:

| Look for | Example found |
|---|---|
| A heading that repeats the title bar | Declension, frequency, sutta, root and dictionary views |
| A label that repeats the data beside it | A dictionary's author after a title naming them |
| A legend or key that takes the first screen | The frequency key before the table |
| Duplicate controls | Next part above and below a part |
| Script with no bundled font | Burmese in Pali English Ultimate shows as boxes |
| A menu longer than a page | Diagnostics alone on page 2 |

**MuPDF quirks.** It ignores inline backgrounds. A link's
`text-decoration: none` also removes a nested `<u>`, so restate
`a.plain u { text-decoration: underline; }`. Keep a number and its noun
together with `&nbsp;` ("9&nbsp;entries"), because headings wrap rather than
shrink.
