#!/usr/bin/env python3
"""Write the device test book, docs/dpd-test-book.epub, reproducibly.

The book is committed so testers can download it; run this after changing
its words, and spec/test_packaging.py checks that the two agree.
"""
import argparse
import html
import pathlib
import zipfile

from package import put

INTRO = ("Long-press each word to test the plugin. The line below it says what "
         "should happen. Checked with DPD mobile v0.4.20260926.")

# Each case is the words to long-press and what should happen. The checks
# hold the first match of some words (pacchima, saṁ, ’ti, in, plugin…), so
# an expectation never names a word that appears later in the book.
SECTIONS = [
    ("Everyday lookups", [
        ("pacchima", "DPD opens at once with eight senses. Expand one: its grammar and "
         "construction appear. With sense 1 open, tap a sense further down: sense 1 "
         "closes and the one you tapped stays on screen."),
        ("pacchimassa", "A grammar header shows how this form is parsed, above its senses."),
        ("saṁ", "Read as saṃ: its grammar and senses appear."),
        ("akaḍḍhi", "Expand its sense: Grammar reads aor of akaḍḍhati, with no dash at the end."),
        ("acceka", "Expand it: the construction and example show bold text, not HTML tags."),
        ("saṃvidāvahāro", "Expand saṃvidāvahāra: Construction reads saṃvida + avahāra, "
         "and the commentary is from VINa."),
        ("Buddha Sace Nārada", "Each opens the lowercase entry, with any abbreviation spelled the same."),
        ("dhammaṃ dhammā kā", "Expand all parses: 9, 28 and 19. Tap a grammar headword, then Back. "
         "For kā, expand Variant readings."),
    ]),
    ("Compounds", [
        ("vajjakammappabhedanti", "Five analyses; only the first is open. Bold in the others marks "
         "the words each adds. Open them all: 3 and 4 say only kamma 1, 2, 5, 6, 7, 8 instead of "
         "repeating kamma. Tap kammi, then Back: your place returns."),
        ("aññabhāgiyasikkhāpadavaṇṇanā", "Open analyses 3, 4 and 5 in any order: each shows asikkhā, "
         "and aññabhāgiyo and aññabhāgiyaṃ say same as aññabhāgiya above. Close analysis 1: the "
         "others don't change."),
        ("kañjikamattakampi", "Analysis 3 adds nothing new, so nothing in it is bold. Open it: "
         "mattaka says same as mattakaṃ above."),
        ("pacchimakattikapuṇṇamā", "One analysis, already open: pacchima + kattikapuṇṇamā."),
        ("saṅghādisesoti", "The two headwords appear once each. Under the analysis, saṅghādiseso says "
         "same as the headwords above, and only iti is defined."),
        ("itīti", "Its one analysis, iti + iti, is spelled exactly as the headword, so it has no arrow."),
        ("suññasuññaṃ", "In analysis 1, suññaṃ says same as suñña above: the part just before it."),
        ("rakkhatiyeva asītīti chāyāti", "Open every analysis. A part that takes only some of a word's "
         "senses names them: rakkhatiyā shows only rakkhanta, rakkhati only rakkhati 1, 2, 3, "
         "and asītī only asīti 1.1. Tap rakkhati's name: all its senses open, and Back returns "
         "your place."),
        ("kiṃkī bhātime", "Open every analysis. kiṃkī keeps both leading kī definitions; bhātime's "
         "analysis 3 keeps bhātar and bhāti 1.1."),
        ("rūpiyappaṭiggahaṇāpatti middhīti", "Open every analysis. paṭiggahaṇā and paṭiggahaṇa are "
         "explained once; middhīti keeps middhī's definition and its correction note."),
    ]),
    ("Forms DPD finds for you", [
        ("avaharissāmā", "A labelled avaharissāma result already shows avaharati and its future "
         "plural parse."),
        ("saṃmantayitvā", "samantayitvā (an analysis) and sammantayitvā (a headword) both show at once. "
         "Expand sammantayitvā: ṃ > m."),
        ("avaharissāmāti sammantayitvāti", "The headword comes first, then the analysis with iti."),
        ("indakhile", "One result, indakhīle, showing two senses and the CST VIN1 indakhile (ka.) "
         "and MST VIN1 indakhile (mr) labels."),
        ("nnāṭṭā", "20 similar forms load; Show more reaches all 29 and keeps your place."),
        ("sūdāni", "Four labelled alternatives."),
        ("bhikkhux bhikkhuxy bhikkhuxyz dhammatq bhikkhu1", "Each opens your normal dictionary. "
         "Tap DPD there: bhikkhux and bhikkhuxy find bhikkhu (shortened prefix), bhikkhuxyz stays a "
         "miss, dhammatq opens dhamma, and bhikkhu1 finds bhikkhu (trailing digits removed). "
         "A later long-press on bhikkhux still opens your normal dictionary."),
    ]),
    ("How books print Pāḷi", [
        ("bhikkhave’ti yo’dha tass’eva", "KOReader may select only part, such as bhikkhave or yo. "
         "DPD finds that part and never guesses an ending."),
        ("akaṭa-anudhammena akaṇha-asukkaṃ", "Note what KOReader selects: DPD finds it, or your "
         "normal dictionary opens."),
        # Decomposed accents, as some books store them.
        ("dhammā ānanda saŋ", "Written with combining accents and ŋ: each finds the "
         "same entry as the usual spelling."),
        ("‘‘Seyyo’’tiettha.", "Long-press tiettha: DPD shows tiettha → ti + ettha."),
        ("idameva saccaṃ moghamaññan’ti, in", "Long-press moghamaññan: DPD shows moghamaññan → "
         "moghamaññaṃ. Long-press in: your normal dictionary opens."),
        ("dhammañ’ca", "Long-press dhammañ: DPD offers dhammaṃ."),
    ]),
    ("References, roots and abbreviations", [
        ("hotī sajjasīti di", "Each shows its spelling reference with the target already expanded. "
         "Open a target, then Back."),
        ("√har akkh", "√har shows four numbered root cards; akkh shows √akkh."),
        ("loc dī", "loc shows its abbreviation above the √loc root; dī shows Dīgha (Nikāya) above √dī."),
    ]),
    ("From an entry", [
        ("bhikkhu", "Expand it and open Frequency: counts by book in the CST, BJT and SYA editions. "
         "Check the labels and emphasis at fonts 16 and 26, in both orientations."),
        ("brahmajālasutta aññataraphalasutta", "Expand each and open Sutta information. "
         "aññataraphalasutta shows aṭṭhikamahapphalasutta, SN46.57. Back returns to the entry."),
        ("√gam", "Open Root details and Root matrix, then a matrix row and one of its headwords. "
         "Back restores each view."),
        ("tissa", "Open Other dictionaries, load more entries and open a long CPD article. Next and "
         "Previous part replace the article and start at its beginning, also at large fonts."),
        ("paṭiccasamuppāda", "Open Other dictionaries: Nyanatiloka's entry has a table that fits the "
         "popup. Back returns to the list."),
        ("dhamma", "Open Other dictionaries: Monier-Williams and Apte say via Sanskrit dharma. Check "
         "that line at fonts 16 and 26."),
    ]),
    ("When DPD doesn't have it", [
        ("dpdtestnomatch", "Your normal dictionary opens."),
        ("gaḷeyyasi", "Your normal dictionary opens. Tapping DPD there may still show variant notes."),
        ("kiriyākiriyatosamuṭṭhāti", "DPD's miss screen opens with Begins with and Ends with parts. "
         "Tap a part, then Back."),
        ("ekaṅgikadvaṅgikativaṅgikāni", "The miss screen opens with no parts."),
    ]),
    ("Type these into Look up a word", [
        ("BHS(G) ms(s) * ** () []", "Each opens its abbreviation entry."),
        ("byādhayissasīti byādhayissasī’ti byādhayissasī”ti byādhayissasī\"ti", "Each finds the same "
         "entry, byādhayati; the quoted forms show the rewrite."),
        ("tatthevantaradhāyathāti", "Its analysis is tattha + eva + antaradhāyatha + iti."),
        ("kata 5", "Opens that numbered sense."),
        ("34626", "Opens dhamma 1.01 by its DPD ID."),
    ]),
]

CSS = """body { margin: 0; }
h1 { font-size: 1.5em; margin: 0 0 .5em; text-align: left; }
h2 { font-size: 1.2em; margin: 1.6em 0 .2em; padding-bottom: .1em; border-bottom: 1px solid #000;
     text-align: left; page-break-after: avoid; }
p { margin: 0; text-indent: 0; text-align: left; hyphens: none; }
p.intro { margin-bottom: .6em; }
p.word { font-size: 1.15em; font-weight: bold; margin-top: 1em; page-break-after: avoid; }
p.expect { font-size: .85em; margin-top: .15em; }
"""


def esc(text):
    return html.escape(text, quote=False)


def body():
    out = ['<h1>DPD lookup test</h1>', f'<p class="intro">{esc(INTRO)}</p>']
    for title, cases in SECTIONS:
        out.append(f'<h2>{esc(title)}</h2>')
        for words, expect in cases:
            out.append(f'<p class="word">{esc(words)}</p>')
            out.append(f'<p class="expect"><i>Expect:</i> {esc(expect)}</p>')
    return "\n".join(out)


def write(path):
    with zipfile.ZipFile(path, "w") as archive:
        put(archive, "mimetype", "application/epub+zip", compressed=False)
        put(archive, "META-INF/container.xml", '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''')
        put(archive, "OEBPS/content.opf", '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">urn:dpd-koplugin:test-book</dc:identifier>
<dc:title>DPD plugin test book</dc:title><dc:language>pi</dc:language>
<meta property="dcterms:modified">2026-10-21T00:00:00Z</meta></metadata>
<manifest><item id="test" href="test.xhtml" media-type="application/xhtml+xml"/>
<item id="style" href="style.css" media-type="text/css"/>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/></manifest>
<spine><itemref idref="test"/></spine></package>''')
        put(archive, "OEBPS/nav.xhtml", '''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Contents</title></head><body><nav epub:type="toc"><ol>
<li><a href="test.xhtml">Lookup test words</a></li></ol></nav></body></html>''')
        put(archive, "OEBPS/style.css", CSS)
        put(archive, "OEBPS/test.xhtml", f'''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="pi">
<head><title>DPD lookup test</title><link rel="stylesheet" type="text/css" href="style.css"/></head><body>
{body()}
</body></html>''')


def main():
    root = pathlib.Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=pathlib.Path, default=root / "docs/dpd-test-book.epub")
    args = parser.parse_args()
    write(args.out)
    print(f"{args.out.resolve()} ({args.out.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
