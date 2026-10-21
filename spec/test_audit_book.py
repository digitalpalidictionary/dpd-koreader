"""Word extraction and hold rules of tools/audit_book.py, on a small generated book."""
import pathlib
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import audit_book  # noqa: E402
from package import put  # noqa: E402

# The markup of a commentary EPUB: Pāḷi in <span lang="pi"> inside an English
# book, bold keywords before plain ti/nti, an inline-block divider between
# compound members, doubled quotes, a footnote letter and a paragraph break.
DIVIDER = '<span style="display:inline-block;height:.7em;border-left:1px solid"></span>'
BODY = f"""<p><span lang="pi"><b>Abhāvo</b>ti vuttaṃ. Tassa <i>anuloma</i>pārājikānīti ca.</span></p>
<p><span lang="pi"><b>vatthu</b>{DIVIDER}<b>ñatti</b>{DIVIDER}<b>anussāvana</b> veditabbā.</span></p>
<p><span lang="pi">‘‘Ime dadeyyu’’nti. ‘‘Tvaṃ passasī’’ti. ‘‘Seyyo’’tiettha.</span></p>
<p><span lang="pi">Ayaṃ <b>upasampadā</b><sup><a href="#n1">a</a></sup> nāma. Kā <b>sīmā</b></span></p>
<p><span lang="pi">parisā ca.</span></p>
<p>The monks <b>care</b>fully kept the rule.</p>"""


def write_book(path):
    import zipfile
    with zipfile.ZipFile(path, "w") as archive:
        put(archive, "mimetype", "application/epub+zip", compressed=False)
        put(archive, "META-INF/container.xml", '<?xml version="1.0"?><container version="1.0" '
            'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile '
            'full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        put(archive, "OEBPS/content.opf", '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" '
            'version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier id="id">audit</dc:identifier><dc:title>Audit</dc:title><dc:language>en</dc:language>'
            '</metadata><manifest><item id="t" href="chapter%20one.xhtml" media-type="application/xhtml+xml"/></manifest>'
            '<spine><itemref idref="t"/></spine></package>')
        put(archive, "OEBPS/chapter one.xhtml", '<?xml version="1.0" encoding="UTF-8"?><html '
            f'xmlns="http://www.w3.org/1999/xhtml" lang="en"><head><title>t</title></head><body>{BODY}</body></html>')


def result(hit, long=False, begins="", ends="", via="exact", query=""):
    return {"route": "dpd" if hit or long else "dictionary", "hit": hit, "via": via, "query": query,
            "long": long, "begins": begins, "ends": ends, "senses": 1 if hit else 0, "analyses": 0,
            "suggestion": "", "ms": 0.0, "error": ""}


class AuditBook(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        book = pathlib.Path(cls.tmp.name, "selection.epub")
        write_book(book)
        cls.occs = list(audit_book.occurrences(book))
        cls.by_text = {}
        for occ in cls.occs:
            cls.by_text.setdefault(occ["text"], occ)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_formatting_splits_keep_their_parts(self):
        self.assertEqual(["Abhāvo", "ti"], self.by_text["Abhāvoti"]["fragments"])
        self.assertEqual(["anuloma", "pārājikānīti"], self.by_text["anulomapārājikānīti"]["fragments"])
        self.assertEqual("Abhāvo|ti", audit_book.key_for(self.by_text["Abhāvoti"]))

    def test_dividers_footnotes_and_paragraphs_end_words(self):
        for word in ("vatthu", "ñatti", "anussāvana", "upasampadā", "sīmā", "parisā"):
            self.assertIn(word, self.by_text, word)
        self.assertNotIn("vatthuñatti", self.by_text)
        self.assertNotIn("upasampadāa", self.by_text)
        self.assertNotIn("sīmāparisā", self.by_text)

    def test_quote_then_separate_ti(self):
        self.assertEqual("dadeyyu’’nti", self.by_text["dadeyyu"]["quoted"])
        self.assertEqual("passasī’’ti", self.by_text["passasī"]["quoted"])
        self.assertIsNone(self.by_text["Seyyo"]["quoted"])  # ’’tiettha: ti is fused
        self.assertIn("tiettha", self.by_text)

    def test_language_marks_pali(self):
        self.assertTrue(self.by_text["Abhāvoti"]["pali"])
        self.assertFalse(self.by_text["monks"]["pali"])
        self.assertFalse(self.by_text["carefully"]["pali"])
        self.assertIn("[Abhāvoti]", self.by_text["Abhāvoti"]["context"])

    def test_manifest_hrefs_are_url_decoded(self):
        self.assertEqual("chapter one.xhtml", self.by_text["Abhāvoti"]["where"])

    def test_outcomes_follow_what_a_hold_selects(self):
        results = {"Abhāvoti": result(True), "Abhāvo": result(True), "ti": result(True),
                   "navanītantiādimāha": result(False), "navanīta": result(True), "ntiādimāha": result(False),
                   "pārājikānīti": result(False), "anulomapārājikānīti": result(True), "anuloma": result(True),
                   "dadeyyu": result(False), "dadeyyu’’nti": result(True), "passasī": result(True),
                   "tiettha": result(True, via="ti", query="tiettha"),
                   "kiriyākiriyatosamuṭṭhāti": result(False, long=True, begins="kiriyākiriyato", ends="samuṭṭhāti")}
        occ = lambda text, fragments=None, quoted=None: {"text": text, "fragments": fragments or [text], "quoted": quoted}
        self.assertEqual("found", audit_book.outcome(occ("Abhāvoti", ["Abhāvo", "ti"]), results)["status"])
        split = audit_book.outcome(occ("anulomapārājikānīti", ["anuloma", "pārājikānīti"]), results)
        self.assertEqual("split", split["status"])
        self.assertIn("part not found: pārājikānīti (DPD has the joined form)", split["note"])
        self.assertEqual("split", audit_book.outcome(occ("navanītantiādimāha", ["navanīta", "ntiādimāha"]), results)["status"])
        quoted = audit_book.outcome(occ("dadeyyu", quoted="dadeyyu’’nti"), results)
        self.assertEqual(("missing", "before a quote; DPD has dadeyyu’’nti"), (quoted["status"], quoted["note"]))
        self.assertEqual("found", audit_book.outcome(occ("passasī", quoted="passasī’’ti"), results)["status"])
        self.assertEqual("ti split from the next word", audit_book.outcome(occ("tiettha"), results)["note"])
        long = audit_book.outcome(occ("kiriyākiriyatosamuṭṭhāti"), results)
        self.assertEqual(("long miss", "parts: kiriyākiriyato…, …samuṭṭhāti"), (long["status"], long["note"]))
        self.assertEqual("error", audit_book.outcome(occ("unseen"), results)["status"])
        results["ti"] = dict(result(False), route="error", error="boom")
        failed = audit_book.outcome(occ("Abhāvoti", ["Abhāvo", "ti"]), results)
        self.assertEqual(("error", "ti: boom"), (failed["status"], failed["note"]))

class AuditText(unittest.TestCase):
    def test_pdf_words_split_like_koreader(self):
        words = list(audit_book.pdf_words("viññāṇaṃ—ime bhāveti—‘aho BHS(G) Māra’s vedanā…pe…"))
        self.assertEqual(["viññāṇaṃ—", "ime", "bhāveti—", "‘", "aho", "BHS(G)", "Māra’", "s",
                          "vedanā…", "pe…"], words)

    def test_markdown_splits_words_like_an_epub(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp, "book.md")
            path.write_text("# Title\n\nkāy’ānupassī viharati—‘aho *dhammañ*’ca\n", encoding="utf-8")
            texts = [occ["text"] for occ in audit_book.occurrences(path)]
        self.assertEqual(["Title", "kāy", "ānupassī", "viharati", "aho", "dhammañ", "ca"], texts)

if __name__ == "__main__":
    unittest.main()
