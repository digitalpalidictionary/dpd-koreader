# Testing and feedback

How the plugin performs on a Kindle, a checklist for testing it on your own
device, and how to report problems. For the behavior behind each check, see
the [user guide](USAGE.md).

## Kindle results

Device: Kindle Paperwhite 12th generation (ARMv7, dual core, 1 GB RAM),
KOReader v2026.07.1, plugin 0.2.1, DPD v0.4.20260926. Measured on 21 October
2026 with the [quick check](#quick-check-on-a-kindle-over-ssh), which
long-presses each word in the test book with KOReader running normally, then
repeats them. Times are in milliseconds.

| | Selection | Lookup | Popup | Painting |
|---|---|---|---|---|
| First look, median of 10 words | 10 | 28 | 68 | 31 |
| Repeat, median of 24 | 10 | 0 | 45 | 30 |

**Popup** includes the lookup and building the entry; **painting** is drawing
it on screen, before the e-ink refresh.

First looks at ordinary words took 51–59 ms (`pacchimassa` 51, `tiettha` 53,
`indakhile` 57, `bhikkhave` 59). The test book mostly holds unusual cases, so
its median is higher: the five-analysis compound `vajjakammappabhedanti` took
125 and the first popup after a restart 377.

**Vocabulary builder.** With it on, the whole long-press took a median of
116 ms the first time a word was saved and 86 for a word already saved,
against 82 with it off.

Not measured: the e-ink refresh, memory over a long session, and lookups
after a long idle.

### Measuring on your device

Turn on **Tools → More tools → Developer options → Enable debug logging**
(no restart needed), use the plugin, then read the `DPD open`, `DPD lookup`
and `DPD render` lines in `koreader/crash.log`. Turn logging off afterwards:
it grows the log quickly. The DPD diagnostic log (see
[troubleshooting](USAGE.md#troubleshooting)) also records a `Popup ready`
line per popup with lookup, build and total milliseconds.

## Device checklist

### Quick check on a Kindle over SSH

This works on a Kindle only (it uses Kindle paths such as `/mnt/us`); on
other devices, use the [checklist](#checks) below. It needs a clone of the
[source repository](https://github.com/digitalpalidictionary/dpd-koreader): the plugin
download has no `tools` folder. With KOReader's SSH server (with **Login
without password** on) and HTTP inspector running on the device (tick the
inspector's **Start on KOReader startup** once) and **DPD on word long-press**
on, from your computer:

```sh
python3 tools/kindle_check.py --install --host root@<device-ip>
```

`--install` copies this checkout's plugin, verifies it and restarts KOReader;
leave it out to test what is installed. The script long-presses 12 words of
the test book inside KOReader, with its own word selection, painting and
refresh: senses, an inflected form, a compound, `saṁ`, an attested reading, an
apostrophe form, ti and ṃ forms, English `in`, a long compound DPD lacks and a
word for the normal dictionary. It prints which popup each opened, with
milliseconds, and saves a screenshot of each under `test-artifacts/kindle/`.
Then it times long-presses with KOReader's Vocabulary builder off, saving a
word, and on a word already saved; it restores that setting and deletes the
cards it added. Last it times **Search other dictionaries**, a long
Monier-Williams article and **Other dictionaries**, in all nine dictionaries,
without adding them to Recent lookups. It takes about two minutes, and stops
if `--install` could not restart KOReader. `--host` (or `DPD_KINDLE_HOST`) is
required; `--port` (or `DPD_KINDLE_PORT`) defaults to 2222. It leaves the test
book in `documents`, its results in `/mnt/us/dpd-diag/`, the test book open
and the long-pressed words in Recent lookups.

Then check by hand only what it can't:

1. Long-press a few words with your finger in your own EPUB and PDF books,
   including a drag across `kāy’ānupassī`-style forms.
2. In a popup, expand a sense, tap a compound part, then Back.
3. Tap **KOReader dictionary**, close it, and close DPD: the highlight clears.
4. Type a word in **Look up a word** with the device keyboard.
5. Sleep and wake with a book open, then look up a word.

The full checklist below is for devices without SSH and for a release that
changes the popup or menus.

### Setup

Install the plugin and database as described in the README. Download the
[test book](https://github.com/digitalpalidictionary/dpd-koreader/raw/main/docs/dpd-test-book.epub)
(`dpd-test-book.epub`) from the repository, copy it next to your books and
open it. Each word in it says what should happen. Type the other examples
below into **Look up a word**, and use your own EPUB and PDF books for the
selection and typography checks. Note the plugin version, database release, book format and
which items you ran.

### Checks

1. Work through the test book from the top. Long-press each word, or type
   it into **Look up a word** where its section says so, and compare the
   result with its **Expect** line. Note any that differ.
2. Tap **KOReader dictionary** from a DPD result. Close that dictionary; the
   highlight clears. Also check closing DPD itself.
3. Turn off **DPD on word long-press**, long-press `pacchima`, and open DPD
   with the dictionary's **DPD** button. Closing DPD returns to the dictionary
   underneath.
4. Suspend and resume with a book open, then look up `pacchima` in the same
   book. Repeat with a large compound and a miss, then in another book. Check
   that expanding stays responsive and the screen refreshes cleanly.
5. In `saṃmantayitvā`, collapse one result, expand details in the other,
   open a component and check that Back restores the view.
6. In `indakhile`, expand a sense, follow a grammar headword and Back; the
   title, expansion and page return. **KOReader dictionary** looks up
   `indakhile`. Component taps only open exact matches.
7. In an EPUB and a PDF, test whole and partial selections and manual lookup
   of `bhikkhave’ti`, `yo’dha`, `tass’eva`, `akaṭa-anudhammena`,
   `akaṇha-asukkaṃ`, decomposed `dhammā` and `saŋ`. KOReader decides where a
   selected word starts and ends. On the Kindle, `akaṭa-anudhammena` stayed
   whole on a single hold, but `bhikkhave’ti` selected only `bhikkhave` and
   `yo’dha` only `yo`; drag-selected `yo’dha` and `tass’eva` found `yodha`
   and `tasseva`. Note what each format selects. A fragment must never gain
   a guessed ending, and a miss still opens the normal dictionary.
8. Open **Database status**: it shows the release, schema 7, core columns
   OK, read-only access and WAL journal mode.
9. In the File Manager, use DPD lookup or Database status, open a book, and
   repeat after returning to the File Manager. Both keep working.
10. If your device lets you rotate with a popup open, expand a sense, scroll,
    rotate, and check that the popup fits with its expansions and page kept.
    Open a component, rotate back and test Back.
11. If another plugin also changes dictionary lookup, turn DPD off and on a
    few times. Each time, open a DPD result and choose **KOReader
    dictionary**: it reaches the usual dictionary, not DPD again. The other
    plugin keeps working.
12. Use DPD for a long session of at least 150 lookups, expanding senses and
    details and using Back. Revisit earlier entries, suspend and resume, and
    reopen the book. Note any errors or slowdowns.
13. At popup font sizes 16, 20 and 26, try `vajjakammappabhedanti`, large
    grammar and variant groups and many expanded alternatives. Check
    wrapping, margins, reachable controls and scrolling in both orientations.
    At sizes 16 and 26, check that the popup stays on the page you tapped:
    - In `vajjakammappabhedanti`, open analyses 2–5, then expand and collapse
      the `akamma` sense in analysis 5 on a later page.
    - In `pacchima`, expand sense 1, then tap a sense on a later page. Sense 1
      closes and the tapped sense stays on screen.
    - Underlined words open entries; ▸/▾ rows expand in place.
    - A popup opened by holding a word shows a Back arrow that closes only
      that popup.
14. Long-press a number in your own book: it's looked up as an ordinary word,
    not as a DPD ID.
15. In **Look up a word**, compare suggestions for `dhamma`, pasted
    `“dhamma,”` and a word containing a soft hyphen. Compare `saṃ`, `saṁ` and `saŋ`. Switch to English, look up
    *meditation*, open a result and go Back. With Velthuis input on,
    `~naa.na` becomes `ñāṇa`, while English *aardvark* stays unchanged.
16. In **Recent lookups**, each word appears once and moves to the top;
    opening root details, frequency or other dictionaries adds no entries.
    Check the clear and off controls.
17. Tap quickly and repeatedly while a sense expands or an article opens. A
    repeated tap before the screen redraws doesn't close it again or navigate
    twice; a later tap works normally.
18. Submit an empty or spaces-only lookup: the dialog stays open. Type part of
    a search, open Recent and dismiss it: your text and mode return. Repeat
    with an empty or disabled history. Choosing a recent word runs that
    lookup.
19. Submit a missing Pāḷi word with Velthuis input on, and a missing English
    word. **Edit search** on each restores the exact text and mode. Misses add
    no history entries. Correct the text and submit.
20. With some recent lookups saved, turn off **Record recent lookups**. Cancel
    the confirmation, then repeat and confirm: only confirming clears the
    list and stops recording. Turn recording back on, add an entry, and test
    Cancel, Back and confirming **Clear recent lookups**, which leaves
    recording on.
21. Long-press a long English word in your own book: your normal dictionary
    opens.
22. With all nine dictionaries chosen, use **Search other dictionaries** for
    `dharma` (Monier-Williams, Apte's `dharmaḥ` and Edgerton) and
    `Mahā Bodhi` (three DPPN entries). Search `kṛ`, open its Monier-Williams
    article and use **Next part**: it has three. Tap **DPD**, then Back; tap
    the pencil. Search `qqqqzzzz`: the
    popup says no entries and **Edit search** restores the text. **Look up a
    word** still opens in the mode it had.
23. In the test book, with KOReader's **Vocabulary builder** on, long-press
    `pacchima`: DPD opens and the word is saved once, with its sentence.
    Long-press it again, and tap **KOReader dictionary**: no "Vocabulary
    exists" notice appears, then or after closing them. Turn off **DPD on
    long-press in this book**, below **DPD on word long-press**: `pacchima`
    opens your normal dictionary, also after closing and reopening the book.
    Reviewing `pacchima` in the Vocabulary builder still opens DPD. Turn the
    book's setting back on.

## Reporting feedback

Open an issue on [GitHub](https://github.com/digitalpalidictionary/dpd-koreader/issues).
Include:

- your exact KOReader version and device;
- the selected word;
- the action that failed;
- the relevant `DPD` lines from `koreader/crash.log`, or, if KOReader crashed
  or runs on Android, the DPD diagnostic log (see
  [troubleshooting](USAGE.md#troubleshooting)).

Issues are public. The diagnostic log records the words you looked up, and
`crash.log` can include the names and paths of books you opened, so remove
anything you'd rather not share before posting.
