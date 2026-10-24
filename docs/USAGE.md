# User guide

This guide shows how to look up words with the Digital Pāḷi Dictionary (DPD)
plugin and how to read what it shows. To install it, see the
[README](../README.md#install).

The plugin's menu is **Search → Digital Pāḷi Dictionary**, on the first page
of Search after KOReader's own dictionary items. This guide calls it the DPD
menu. For a short reminder on the device, open **Help → DPD help** there.

The last section, [Lookup rules in detail](#lookup-rules-in-detail), lists
exact limits and unusual cases. You don't need it for everyday reading.

## Look up a word

**Long-press a word** in your book. If DPD has something for it, the DPD
popup opens. Otherwise, or if something goes wrong, your normal dictionary
opens instead.

To select a phrase, or a whole form such as `bhikkhave’ti`, drag across it.
The selection menu has a **DPD** button.

**Type a word** with **Look up a word** in the DPD menu.

- When you pause, suggestions appear under the box: headwords that start
  with what you typed, the most common first. If you type without
  diacritics, close spellings are added and marked ≈:
  `nana` offers ≈ ñāṇa. Tap a suggestion, or tap **Look up**.
- A number opens the headword with that ID, as on dpdict.net.
- **English** switches to English → Pāḷi. Type an English word such as
  *good* to list the Pāḷi words whose meaning includes it, then tap one to
  open all its senses. **Pāḷi** switches back, and the dialog remembers your
  choice. English search works only here, never on long-press.
- **Recent** lists your last 50 lookups. Tap one to look it up again.

**Search other dictionaries**, just below **Look up a word**, searches the
other dictionaries bundled with DPD; see [Other dictionaries](#other-dictionaries).

**Change the word** with the pencil beside the popup's title, as in
KOReader's dictionary: tap it to edit the word you selected or typed, or hold
it to edit the form DPD matched. When a typed lookup finds nothing, **Edit
search** brings back your text so you can correct it.

## Read an entry

The title shows the DPD form that matched, such as `buddha` for a selected
`Buddha`. Below it, every sense of the word appears in DPD's order, with its
number (such as 1.01 in *dhamma 1.01*) and its part of speech in italics.

- **Tap a sense** to expand it. Opening one closes the one before.
- **Underlined text** opens another entry or list. **▸** expands something
  in place and **▾** collapses it; the popup stays on the page you tapped.
  Plain text doesn't open anything.
- **Back**, the arrow at the left of the title, returns to the previous view
  with your place kept.

An expanded sense shows, when DPD has them:

1. Where the word comes from: its construction, the word it derives from and
   its root (√ marks a root), as in `√dhar + ma · from dharati`.
2. **Grammar**, when it adds to the part of speech.
3. A row of buttons for the views it has: **Declension** or **Conjugation**,
   **Frequency**, **Sutta information**, and its word families.
4. Commentary, synonyms and antonyms, variants, examples with their sources,
   and notes.
5. DPD's editorial status (✔ complete, ◑ meaning without a source yet,
   ✘ incomplete) and the entry's permanent `dpdict.net/<ID>` reference.

Empty fields are left out. Parts of the construction, roots, derived-from
words, synonyms and antonyms link to their own entries.

**Inflected forms.** When you look up an inflected form, DPD shows its
grammar and headword: `dhammassa` shows `noun · masc, nt dat/gen sg of
dhamma`, meaning masculine and neuter, dative and genitive singular. Parses
are bundled by part of speech and headword, and share a row when they fit.
Tap **+N parses** to show the rest, one bundle per line, and tap a headword
to open its senses.

**Compounds.** DPD often splits a compound into its parts in more than one
way, and each way is an analysis.

- The first analysis that adds to the word's own entries opens with brief
  meanings for its parts. The others start collapsed, one tap away, with the
  words they add in bold.
- **Analyses · N · unchecked** means DPD made these splits automatically and
  no editor has reviewed them, so a split can be wrong, and the one that opens
  first isn't necessarily right. The entries for the parts are DPD's checked
  ones.
- Each part shows up to two brief senses. A name such as
  **khippaṃ · 3 senses ›** has more: tap it to open them all. Tap a sense line
  to expand it in place.

**Variant readings** list where a form is found, by source, book and
context. They are for information and never take you to another word.

**Below the entry**, two buttons stay in place on every page:

- **Other dictionaries** looks the word up in the other dictionaries bundled
  with DPD.
- **KOReader dictionary** closes DPD and opens the same word in KOReader's
  dictionary. A word selected in your book stays selected, so that
  dictionary's **Highlight**, **Search** and **Wikipedia** buttons work as
  usual.

A button that doesn't apply to the current view is greyed out.

## Follow words inside the popup

Hold a word in the popup, or hold and drag to select a phrase, and a second
DPD popup opens on top. This works on links too: holding selects the text,
tapping follows the link.

Close the top popup, or tap **Back** at its first entry, to return to the
entry underneath, just as you left it. A word DPD doesn't know, or a lookup
that fails, opens KOReader's dictionary on top instead; closing it brings
you back to DPD.

You can stack up to eight DPD popups. Sleeping the device closes them all.

## More from an entry

### Declension and conjugation tables

A noun, adjective, pronoun, participle, numeral or verb has a **Declension**
or **Conjugation** button in its expanded sense. It opens the headword's full
table, built from DPD's own inflection patterns. The form you looked up is
marked ▸ in bold wherever it occurs. Tap any form to look it up, then
**Back** to return to the table. Indeclinables have no table.

### Frequency

**Frequency** shows how often the headword and its inflected forms occur in
each book of the canon and its commentaries, in four editions. High counts
are bold, and the highest is on grey. The counts are for the spelling, not
the sense, so identical forms of other words are counted too.

### Sutta information

When a headword names a sutta, vagga, saṃyutta, nipāta or paṇṇāsaka,
**Sutta information** shows where the text is in the main editions, its page
numbers and PTS reference and, for single suttas, a summary, themes, similes
and parallels.

### Roots

A root card has two links. **Root details** gives the root's group and sign,
the bases built from it, and its entries in the traditional grammars.
**Root matrix** sorts every word from the root by kind, such as verbs by
tense or nouns by gender; tap a row to see its words, and a word to open it.

### Related words and families

Expanded senses and root cards link to the word's families: root families,
word families, compounds, idioms and thematic sets (words on one topic, such
as *colours*, *bodyparts* or *great disciples*). A list opens 20 members at a
time, and **Show more** adds the next 20. Tap a member to open it, then
**Back** to return to the list.

### Other dictionaries

**Other dictionaries**, below an entry, looks its headwords up in the
dictionaries bundled with the DPD database. By default these are the
Dictionary of Pāli Proper Names, the Critical Pali Dictionary, the PTS
Pāḷi-English Dictionary and Nyanatiloka's Buddhist Dictionary. Choose others under **Other dictionaries**
in the DPD menu: Pali English Ultimate, Edgerton's Buddhist Hybrid Sanskrit
Dictionary, Monier-Williams, Apte and WordNet. Hold a name there for its full
title and author.

Each result shows the start of the article; tap it to open the rest. Long
articles come a part at a time, with **Next part** and **Previous part**.
When a dictionary has no exact entry, close spellings are shown, marked ≈.
Monier-Williams and Apte first try the Sanskrit word DPD gives for the
headword and say so, as in **via Sanskrit dharma**.

**Search other dictionaries**, in the DPD menu, searches the same
dictionaries for exactly what you type, such as a Sanskrit word (`dharma`,
`ātman`) or a name DPD doesn't have (`Mahā Bodhi`). **DPD** below the results
looks the word up in DPD instead.

These dictionaries come with DPD v0.4.20260926 and newer, and PTS with
releases after it. With an older database, the **Other dictionaries** button
doesn't appear below entries, and **Search other dictionaries** finds
nothing. A dictionary missing from the open database, such as PTS before its
release, finds nothing, and holding its name in the menu says so.

## When there's no exact match

DPD never quietly swaps your word for another one. Anything that isn't an
exact match is labelled.

- **Similar forms.** If DPD finds one similar spelling, its entry opens with
  `selected → resolved · similar form` in the header. If it finds several,
  they're listed as choices. When manuscripts record your spelling, the
  header says **variant reading** and names the source.
- **Spelling corrections.** Where DPD records a misspelling, the popup says
  **Incorrect spelling of …** and links to the right word when DPD has it.
- **Did you mean.** When a typed word has no entry and no similar form, DPD
  lists words one letter away: `kamna` offers kamma.
- **Shortened words.** In a typed lookup, or with a **DPD** button, a word
  with a stray letter or a footnote number at the end is found without it:
  `bhikkhux` and `bhikkhu1` offer `bhikkhu`, labelled as approximate. A
  long-press never does this.
- **Forms printed oddly in books.** Some texts join `ti` to the next word
  (`’’tiettha`), print a final ṃ as n before `ti` (`saccan’ti`), or as ñ or ṅ
  before a consonant (`dhammañ’ca`, `Yaṅ’kiñci`). DPD tries the likely word
  and labels it:
  `saccan → saccaṃ · ṃ printed as n before ti`.
- **Long Pāḷi words.** A long word with diacritics that DPD doesn't have,
  such as `kiriyākiriyatosamuṭṭhāti`, is usually a compound DPD hasn't
  recorded. DPD then shows the longest beginning and ending it knows
  (**Begins with kiriyākiriyato…**, **Ends with …samuṭṭhāti**), even after a
  long-press; tap one to open it. These are plain pieces of the spelling, not
  an analysis.
- **Nothing found.** After a long-press, your normal dictionary opens. After a
  typed lookup, the popup says there's no entry and offers **Edit search**.

## Spelling and diacritics

- Diacritics and capitals are optional: `Buddha` finds `buddha`. An exact
  spelling still comes first, and other spellings are labelled.
- `ṁ`, `ŋ` and `ṃ` all match.
- Joined forms such as `bhikkhave’ti`, `akaṭa-anudhammena` and `hotī”ti` are
  recognised when you select or type the whole form. A hyphenated spelling
  DPD records is tried before the same word without the hyphen. KOReader decides where a
  long-pressed word begins and ends, so on some devices a long-press selects
  only one part. Drag across the whole form, or type it in **Look up a
  word**.
- To type diacritics without a Pāḷi keyboard, turn on Velthuis input (see
  [Settings](#settings)) and type `aa` for ā, `.t` for ṭ, `~n` for ñ and so
  on.

## Settings

All settings are in the DPD menu.

- **DPD on word long-press** (on by default) opens DPD when you long-press a
  word. Turn it off to have your normal dictionary open first; it then has a
  **DPD** button that opens DPD on top.
- **DPD on long-press in this book** makes an exception for the open book
  only, such as an English book. The book keeps it when you reopen it.
- **Display and input**:
  - **Popup font size** (16 by default) is separate from KOReader's
    dictionary font. The next popup uses the new size.
  - **Show ṁ instead of ṃ** (off by default) shows niggahīta as ṁ. Searching
    works with either spelling.
  - **Velthuis input (aa → ā, .t → ṭ, ~n → ñ)** (off by default) lets you
    type diacritics in **Look up a word** with a plain keyboard.
- **Other dictionaries** chooses which dictionaries the **Other
  dictionaries** button searches.
- **Recent lookups** has **Show recent lookups**, **Record recent lookups**
  (on by default; turning it off also forgets the list) and **Clear recent
  lookups**. The list is kept only on your device, in KOReader's settings.
- **Choose database file** and **Database status**: see
  [Updating and the database](#updating-and-the-database).
- **Help** has **DPD help**, **About & licenses** and **Diagnostics**.

KOReader's **Vocabulary builder** saves the words you look up in DPD in a
book, with their sentence, when its own setting is on, as it does for
KOReader's dictionary.

## Words in English books

**DPD on word long-press** doesn't check the book's language, and short Pāḷi
forms such as `to`, `the`, `have` and `time` are also English words. In an
English book, turn off **DPD on long-press in this book**. Pāḷi terms there
are still one tap away, through the **DPD** button in your normal
dictionary.

## Updating and the database

**Plugin.** Exit KOReader, delete `koreader/plugins/dpd.koplugin`, put the
folder from the new zip in its place and restart. Your DPD settings and
recent lookups are kept: they're stored in KOReader's settings, not in the
plugin folder.

**Database.** Exit KOReader and replace `dpd-mobile.db` with the one from the
[latest DPD release](https://github.com/digitalpalidictionary/dpd-db/releases/latest).
Delete any `dpd-mobile.db-wal` and `dpd-mobile.db-shm` files beside it, then
restart. **Database status** shows the new release.

The plugin only reads the database and never changes it. SQLite still
creates small `-wal` and `-shm` files beside it, so the folder holding it
must be writable, wherever you keep it. If it isn't in `koreader/data/dpd/`,
pick it with **Choose database file**.

**Database status** shows which DPD release is open, whether its core columns
are OK, and the release this plugin was tested with. Newer releases work as
long as the core columns are OK.

## Troubleshooting

- **DPD never opens:** check **Database status**. If the database isn't found,
  use **Choose database file**. Make sure external plugins are enabled.
- **A message says DPD can't open its database:** this happens, for example,
  before `dpd-mobile.db` is installed. DPD says so once per session, and
  long-press opens your normal dictionary until it's fixed. Choose the
  extracted `dpd-mobile.db` with **Choose database file**.
- **Look up a word shows "DPD database unavailable":** choose a valid file to
  carry on with your search, or check **Database status**.
- **A long-press picks only part of the word:** drag across the whole word,
  or type it in **Look up a word**.
- **English words open DPD:** turn off **DPD on long-press in this book**.
- **The DPD menu says "Needs a newer KOReader":** update KOReader to
  v2026.07 or newer. Until then DPD stays off and long-presses open your
  normal dictionary.
- **KOReader closes unexpectedly, or something looks wrong:** turn on
  **Help → Diagnostics → Write diagnostic log** in the DPD menu and repeat
  what you did (restart KOReader first if the problem happens at startup). Then send
  `koreader/data/dpd/dpd-debug.log`, or open **Help → Diagnostics → Show
  diagnostic log** and take a screenshot. The log records the words you look
  up, links you tap, errors and the lookup, build and total time of each
  popup, so turn it off afterwards. On Android, KOReader keeps no
  `crash.log`, so this log is the only record of what happened.
- **Reporting a problem:** see [reporting feedback](TESTING.md#reporting-feedback).

## Uninstalling

Exit KOReader, delete `koreader/plugins/dpd.koplugin` and restart. The
database and diagnostic log are kept in `koreader/data/dpd/` (unless you chose
a database elsewhere); delete that folder too to remove them.

## Compared with DPD's website and app

The plugin aims to show what the dictionary panel of
[dpdict.net](https://www.dpdict.net/) shows, plus the other dictionaries and
early-text counts that DPD's mobile app adds, from the same database and
adapted for e-ink:

- **Expanded senses** list the grammar, construction, etymology, examples and
  notes as fields, rather than the website's tables.
- **Declension and conjugation tables** are split by gender or voice to fit
  small screens, with the same forms as DPD's own tables.
- **Frequency** uses bold and grey cells instead of colour shading.
- **Sutta information** follows the website's sections and rules, without
  its links to other sites.
- **Root matrix** lists categories first, then a row's words in Pāḷi
  alphabetical order.
- **Other dictionaries** show text and basic formatting only; the data has
  no links between entries. What the originals show on hover or in colour is
  left out: Monier-Williams and Apte abbreviation expansions (`q.v.`, `T.`),
  DPPN's marks for revised text (Added, Modified, Original), and CPD's
  footnote and edition superscripts, which print as plain digits. MW and
  Apte show only an amendment's current reading.
- **Suggestions as you type** offer headwords, and ≈ forms such as
  inflections; unlike the app's, they don't include roots or family names. **Recent lookups** keeps a list, but
  there is no Back/Forward history across separate lookups.

Not available:

- Marking forms that never occur in the texts, and DPD's manual variant
  redirects. The mobile database doesn't include this data.
- Sinhala, Devanagari and Thai input, pronunciation audio, bold-definition
  search, Tipiṭaka translations and Russian.
- General typo search beyond **Did you mean**, KOReader gesture or shortcut
  actions for DPD, and a smaller database.
- Anything beyond the dictionary itself, such as reading texts; KOReader is
  the reader here.

## Lookup rules in detail

This section is for reference. It adds exact limits and unusual cases to the
sections above, in the same order.

### Long-press and popups

- **DPD on word long-press** affects only words selected in a book. Searches
  you type in KOReader's own dictionary behave as usual.
- After **KOReader dictionary**, a highlight you make there is saved when that
  dictionary closes. Dragging across words opens KOReader's selection menu as
  before.
- With **DPD on word long-press** off, closing a DPD popup opened from the
  normal dictionary's **DPD** button returns you to that dictionary.
- In **DPD on long-press in this book**, choosing the same as **DPD on word
  long-press** removes the exception, so the book follows that setting again.
- Vocabulary builder: a word it already has isn't sent again. Reviewing a
  saved word opens it in DPD while **DPD on word long-press** is on, even in
  a book that turns DPD off for itself.
- The pencil: the popup stays open under the editor, so **Cancel** returns to
  it, and the search you submit replaces it. In an entry opened from another
  one, the pencil edits that entry's word and opens the result on top, so
  **Back** returns to it. Tables, families and other lists have no pencil. In a popup opened from
  another, the result replaces only that popup, so **Back** still returns to
  the one beneath.
- With eight popups open, close one before opening another. Closing a popup
  clears the text you selected in the popup beneath it; closing the first
  popup clears the selection in the book. Changing databases also closes all
  DPD popups.
- A word held in a popup is matched as in a book: shortened-word suggestions
  come only from the **DPD** buttons and **Look up a word**.
- When the device sleeps, DPD also closes the database, and reopens it at
  your next lookup.
- KOReader scales **Popup font size** for the screen.

### Look up a word in detail

- Up to six suggestions appear. Close spellings marked ≈ also include words
  that differ in aspiration or doubled consonants. For a short or very common
  beginning, suggestions come from a sample of candidates, so a word may
  appear only after you type another letter or two. **No suggestions — Look
  up still searches.** means no candidates were found; **Look up** still
  searches the whole dictionary.
- In English mode, suggestions for one or two letters may be incomplete.
  Results list 20 Pāḷi words at a time, with **Show more**.
- A number that isn't a headword ID says **No DPD headword with ID …**.
  **Look up** with an empty box keeps the dialog open. **Edit search**
  restores the mode you used, Pāḷi or English, as well as the text, so you
  can also switch languages without retyping.
- **Recent** records words you look up in a book, in a popup or by typing,
  but not tables, families and other pages you open. Searches of the other
  dictionaries that find something appear too, marked *Dictionaries*.
- Dismissing **Recent** returns to your unfinished search. If the list is
  empty or recording is off, your draft stays open.
- Turning off **Record recent lookups** asks first when the list isn't
  empty. **Clear recent lookups** also asks first, and doesn't turn
  recording off.
- Velthuis input: `aa ii uu` for ā ī ū, `.t .d .n .l .m .h` for ṭ ḍ ṇ ḷ ṃ ḥ,
  `~n` for ñ and `"n` for ṅ. The dialog's title ends in **· Velthuis** while
  it's on. It never changes selected book text or English searches. In
  **Search other dictionaries** it also turns `"s` into ś, `.s` into ṣ, `.r`
  into ṛ and `.rr` into ṝ; Pāḷi lookup leaves those as typed.

### Entries in detail

- The origin line also gives the root's meaning, sign and base, as in
  `√i 1 (come, go)`. A smaller line adds the Sanskrit, cognates, derivative,
  suffix, phonetic change, the headword's IPA pronunciation and, for nouns
  like `satthar`, the traditional lemma (`satthu`).
- **Grammar** appears only when it adds something: `dhamma 1.04` shows
  "normally pl dhammā", while `dhamma 1.01` shows none. A suffix that ends the
  construction, or a compound construction identical to the construction,
  isn't repeated.
- The row of buttons wraps onto more rows on a narrow screen or at a larger
  font. A family button names the family only when the entry doesn't already
  say it, as in **Root family: ā √kam** or **Compounds: cakka**.
- At most two examples are shown, each followed by its source and sutta.
- The end of a sense shows any web link DPD gives, such as a Wikipedia page
  for a plant. ✔ doesn't promise a cited source, since DPD marks entries with
  nothing to cite as complete. The `dpdict.net/<ID>` reference is plain text
  and needs internet.
- A link whose target DPD doesn't have stays plain text.
- Parses are bundled by part of speech and headword before they share a
  row. N in **+N parses** counts the individual parses still hidden, not the
  bundles.
- Long variant-reading lists show 50 readings at a time, with **Previous
  readings** and **Next readings** above and below. Switching returns to the
  start of the section; **Back** from another view restores the readings you
  were on and your place.

### Compounds in detail

- Each alternative gives brief meanings only for words that the headwords and
  the analysis that opened first don't already explain, once each.
  Alternatives are compared independently, so a word shared by two of them
  can appear in both.
- A differently spelled form with exactly the same senses says where it's
  explained instead, such as **aññabhāgiyo · same as aññabhāgiya above** or
  **saṅghādiseso · same as the headwords above**.
- A form with only some of an earlier word's senses still shows which
  reading it takes: `chāyā` after `chāya`, or `rakkhatiyā` (only rakkhanta)
  under the headword rakkhatiyeva. When its rows would repeat that word's, it
  names its senses on one line instead, such as **kammā · 6 senses › · only
  kamma 1, 2, 5, 6, 7, 8** after `kamma`. This also applies to subsets of the
  headword list: `rakkhatiyā` shows **only rakkhanta**, and `rakkhati` shows
  **only rakkhati 1, 2, 3**.
- An analysis whose parts all appear above, spelled the same, has no ▸. If
  you close the analysis that opened first, the words it explained stay out
  of the others; tap a word to open its entry.
- The lemma and sense number show which meaning a tapped sense line expanded.
  Each part keeps its own expansions, including in similar-form and
  cross-reference results.
- Words in an analysis's header open their entries whether or not the
  analysis is open. The arrow expands or collapses it.
- A headword's **Construction** and **Compound construction** are DPD's own
  fields, separate from the automatic analyses. Their parts link to exact
  entries too: `buddhānussati` lets you open `buddha` and `anussati`.
- A part DPD has no headword for keeps its place in the breakup and says so.

### Tables, counts and suttas in detail

- In a declension or conjugation table, each form has its own line within its
  cell, and the form you looked up is marked in every cell where it occurs:
  `dhammassa` is both dative and genitive singular.
- Tables are split into masculine, feminine and neuter, or active and
  reflexive. When the popup is wide enough, for example in landscape on a
  larger screen, the sections sit side by side; a larger font stacks them
  again.
- DPD's website greys out forms that never occur in the texts. That
  information isn't in the mobile database, so these tables don't mark it.
- Frequency covers CST, split into root text (M), commentaries (A) and
  sub-commentaries (Ṭ); BJT and SYA, split into M and A; and the
  Mahāsaṅgīti, M only. A key below the table names the editions and columns.
  On a narrow screen the editions are split into as many tables as needed.
- Forms inside compounds or sandhi aren't counted.
- Sutta information covers the Chaṭṭha Saṅgāyana, SuttaCentral and Buddha
  Jayanti editions, page numbers in printed editions, the PTS reference and,
  for single suttas, the Dhamma Vinaya Tools catalogue (themes, summary,
  similes, key excerpts) and parallels in the Āgamas and other collections.
- A sutta's alternative names count too: *pāṭikavagga* opens the record of
  *pāthikavaggapāḷi*, whose canonical DPD name and code appear above the
  details.
- Root details lists the root's entries in the Dhātupāṭha, Dhātumañjūsā,
  Saddanīti and Pāṇini's Dhātupāṭha.
- The root matrix sorts verbs by tense and mood, then participles, nouns by
  gender, adjectives and indeclinables, each split by derivation (causative,
  passive, desiderative, intensive, denominative). It lists the rows with
  their counts, and a row's words one per line.
- Families appear only when the database includes them. **Show more** keeps
  your place. A word can belong to several thematic sets. A family that can't
  be read is reported without closing the entry.

### Other dictionaries in detail

- Each dictionary has a one-line heading with a short name, such as
  *Edgerton · Buddhist Hybrid Sanskrit*, and its entry count. Holding a name
  in the menu also shows the entry count.
- Each entry shows the headword and its homonym number (*kamma³*) before the
  start of the article. Groups of exact entries show their total and how many
  are loaded; **More entries** loads the next batch.
- Parts are labelled **Part N · X%**; an article in one part has no label.
  The percentage is how much of the article you've reached, by text rather
  than screen pages. **Previous part** appears above and below each part
  after the first; **Next part** appears below while more remains. A new
  part opens at the entry's title.
- Opening an entry closes the one that was open. Reopening an entry in the
  same view returns to the part you last read.
- A word DPD lacks, such as a name, is looked up as typed.
- Each dictionary without an exact entry shows up to three close spellings.
  **N approximate · limited search** counts the close spellings shown, not
  every possible one. Dictionaries with exact entries come first.
- Edgerton's dictionary keeps many Pāḷi-like forms, so it shows close
  spellings first and tries the Sanskrit word only when it has none. A
  Sanskrit word that DPD gives as an analysis (`atyaya + sūtra`) isn't used.
- Pali English Ultimate has Burmese script in some entries. KOReader bundles
  no Burmese font, so previews leave it out, and articles need a Myanmar
  font installed in KOReader.
- Colours, links and page layout from the original are left out.
- **Search other dictionaries** tries the text exactly as typed, punctuation
  included (`e.g.`, `Accayasutta (Akodhanasutta)`), then without surrounding
  quotes and punctuation, each also in lower case, so `Śāriputra` finds
  `śāriputra`. After a final vowel it also tries `ḥ`, and after `a` also `ṃ`,
  because Apte lists many nouns that way (`dharmaḥ`, `phalaṃ`). Typed
  without diacritics, close spellings are offered marked ≈: `sariputra`
  finds ≈ `śāriputra`.
- It has no suggestions as you type. Its results look and page like **Other
  dictionaries**. **Back** from **DPD** returns to the results, and the
  pencil, or **Edit search** after a miss, edits the search.
- **DPD** in its dialog switches to **Look up a word**. Choosing **Search
  other dictionaries** doesn't change whether **Look up a word** opens in
  Pāḷi or English.

### Similar forms and corrections in detail

- Several similar forms are ordered attested readings first, then by
  closeness in length. Each says whether it has headwords, compound analyses,
  variant readings, roots, abbreviations, grammar or references.
- The first two start open and later ones collapsed. Collapse or expand one
  with its arrow, or tap its name to open it on its own page. Up to 20 load
  at once; **Show more** loads the rest without losing your place or the ones
  you opened or closed.
- When one similar form opens directly, the title keeps your word. Tap the
  arrow beside **variant reading** to see all the source notes.
- Spelling corrections and "see" notes are entries in their own right. A
  recorded correction opens DPD on long-press even when the corrected word
  or phrase has no entry. Manuscript readings on the same record stay
  available. A correction's link opens the right word's exact entry,
  expanded. Similar-form suggestions never replace a recorded correction.
- **Did you mean** puts the closest spellings first: diacritics you didn't
  type don't count against a word, and a missing ṃ counts as half a letter,
  so `jāneyyu` offers jāneyyuṃ first. The search is bounded, so the list
  isn't guaranteed to hold the closest words.

### Shortened words in detail

- DPD tries this only after exact and similar-form lookup both miss.
- It removes one or two letters from the end, labelled **approximate ·
  shortened prefix**. Up to three trailing digits, such as a footnote number,
  are removed first, labelled **approximate · trailing digits removed**.
  Digits inside a word are never removed.
- A complete shortened word comes first, even over continuations of a longer
  beginning: `dhammatq` offers `dhamma`. Otherwise a limited list of words
  that continue the shortened form appears.
- DPD always keeps at least four letters, and this works for single words of
  up to 64 letters.
- The shortened form is used as typed: a word typed without diacritics *and*
  with an extra letter is found only when DPD records the unaccented spelling.
- Long-press skips this because a shortened word can be an unrelated one.
  Compound parts and recorded references still resolve exactly.

### Forms printed oddly in detail

- **`ti` joined to the next word:** after a closing quote, some texts print
  `ti` attached to the following word, as in `’’tiettha`, and long-press then
  selects `tiettha`. When such a word has no entry or similar form and the
  rest starts with a vowel, DPD looks up the rest. The header shows
  `tiettha → ti + ettha · ti split from the next word`. Before a consonant,
  `ti` can be the numeral "three", so those words aren't split. This is a
  guess from the spelling: an unrelated name such as `Tiana` can also be
  split if DPD knows the rest.
- **ṃ printed as n before `ti`:** some texts write `saccan’ti` for
  `saccaṃ ti`, and long-press stops at the quote and selects `saccan`. When
  such a word has no entry or similar form, DPD looks up `saccaṃ`. Words of
  three letters or fewer are left alone, so English `in` and `run` still go
  to your normal dictionary. Words in DPD's English index are left alone too,
  but words and names outside it, such as `sedan` and `Japan`, can still open
  a Pāḷi form. Turn off **DPD on long-press in this book** when that gets in
  the way.
- **ṃ printed as ñ or ṅ:** chanting books write `dhammañ’ca` and
  `Yaṅ’kiñci`, and long-press stops at the apostrophe. A selected word ending
  in `ñ` or `ṅ` that has no entry is looked up with `ṃ` (`dhammaṃ`, `yaṃ`). To
  look up the whole form, such as `kāy’ānupassī`, select across the
  apostrophe.
- All three apply to long-press as well as typed lookups.

### Long Pāḷi words in detail

- This applies to a word of 15 letters or more with Pāḷi diacritics, when
  DPD knows a beginning or ending of at least five letters. When neither is
  found, long-press goes straight to your normal dictionary.
- Where sandhi changes letters at a join, a part may be missing; DPD never
  makes up an analysis.
- To look up another part, shorten the word with the pencil in the title
  bar. **KOReader dictionary** still opens your normal dictionary.

### Spellings DPD accepts

- Decomposed Unicode, found in some EPUBs, matches the usual form.
- Closing-quote spellings match in capitals too, as in `HOTĪ”TI`.
- A typed numbered headword such as `Dhamma 1.01` opens that exact sense;
  capitals don't matter.
- Roots (`√har`) and abbreviations (`loc`) have their own cards.
- **Look up a word** also accepts abbreviation symbols and brackets as
  typed, such as `*`, `[]`, `BHS(G)` and `ms(s)`.

### The database in detail

- **Database status** also shows the schema version, read-only access and
  journal mode. The database is in SQLite's WAL mode, which is why the `-wal`
  and `-shm` files appear.
- **DPD database unavailable** appears before the search dialog when
  **Look up a word** can't open the database. Choose a valid file, check
  **Database status**, or **Cancel**. A valid file resumes your saved draft
  and language. Closing **Database status** returns to this choice, or
  resumes the search if the database now opens. **Recent** stays
  available, and a saved lookup you choose is retried once you select a
  valid file.
- **Help → About & licenses** shows the plugin and dictionary licenses and
  the open database's version. It works without a database too. The plugin
  download includes the full licenses and attribution notices.
