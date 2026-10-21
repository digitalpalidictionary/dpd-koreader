#!/usr/bin/env python3
"""Audit a book against DPD the way long-press sees it, and report changes.

    python3 tools/audit_book.py BOOK.epub [BOOK2.pdf ...] \\
        --koreader ~/koreader --db dpd-mobile.db [--save]

Every word in the book is looked up once, through the plugin's own lookup in
KOReader's LuaJIT (tools/audit_lookup.lua). A hold selects what KOReader
selects: where bold or italic starts or stops inside a word, only the part
held, and before a closing quote, the word without ti/nti. Words are sorted
into:

  found       DPD opens with a result
  split       bold or italic splits the word and a part opens KOReader's dictionary
  long miss   a long Pāḷi word DPD lacks: DPD's miss screen with its parts
  missing     KOReader's dictionary opens instead
  English     non-Pāḷi words that DPD opens on long-press

Notes say when DPD has the joined or quoted form a hold cannot select.

Markdown and text files are read like an EPUB, as KOReader shows them as
plain text through the same engine. PDFs (with PyMuPDF installed) are read
the way KOReader selects in them: MuPDF's words, which end at a space or
after a dash, curly quote or other General Punctuation character.

Results are saved per book under test-artifacts/audit (git-ignored) as a
baseline; later runs report only what changed. A new baseline is written on
the first run, or with --save after you have reviewed the changes. Missing
words are DPD coverage, not failures: the exit status is nonzero only when a
lookup raises an error.

--koreader and --db default to $DPD_KOREADER and $DPD_DB. Books can also come
from $DPD_AUDIT_BOOKS (separated by the path separator), which keeps private
paths out of shell history and notes.
"""
import argparse
import collections
import datetime
import html.parser
import json
import os
import pathlib
import posixpath
import subprocess
import sys
import tempfile
import unicodedata
import urllib.parse
import zipfile
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
FMT, BREAK = "\x01", "\x02"
INLINE = {"b", "i", "em", "strong", "u", "span", "small", "big", "cite", "dfn", "mark", "s", "strike",
          "var", "font", "a", "abbr", "q", "tt", "code", "kbd", "samp"}
SKIP = {"head", "title", "style", "script", "sup", "sub"}
VOID = {"br", "hr", "img", "meta", "link", "input", "wbr"}
CLOSING_QUOTES = "’”\"'"
PALI_MARKS = set("āīūṃṁṅñṭḍṇḷŋĀĪŪṂṀṄÑṬḌṆḶŊ")


def is_letter(ch):
    return ch.isalpha() or unicodedata.category(ch).startswith("M")


class Text(html.parser.HTMLParser):
    """Flattens XHTML into characters with a Pāḷi flag; FMT marks an inline
    element edge, BREAK anything KOReader also ends a word at."""

    def __init__(self, book_pali):
        super().__init__(convert_charrefs=True)
        self.chars, self.flags = [], []
        self.stack = [("", book_pali, False)]  # tag, pali, skipping

    def mark(self, marker):
        self.chars.append(marker)
        self.flags.append(None)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        _, pali, skipping = self.stack[-1]
        lang = attrs.get("lang") or attrs.get("xml:lang")
        if lang:
            pali = lang.split("-")[0].lower() in ("pi", "pli")
        inline_block = "inline-block" in (attrs.get("style") or "").replace(" ", "")
        if tag in SKIP or inline_block:
            skipping = True
        self.mark(FMT if tag in INLINE and not inline_block else BREAK)
        if tag not in VOID:
            self.stack.append((tag, pali, skipping))

    def handle_startendtag(self, tag, attrs):
        self.mark(FMT if tag in INLINE else BREAK)

    def handle_endtag(self, tag):
        for depth in range(len(self.stack) - 1, 0, -1):
            if self.stack[depth][0] == tag:
                was_skipping = self.stack[depth][2] and not self.stack[depth - 1][2]
                del self.stack[depth:]
                self.mark(FMT if tag in INLINE and not was_skipping else BREAK)
                return

    def handle_data(self, data):
        _, pali, skipping = self.stack[-1]
        if skipping:
            return
        for ch in unicodedata.normalize("NFC", data):
            self.chars.append(ch)
            self.flags.append(pali)


def documents(path):
    """Yields (name, xhtml) in spine order, and the book's language."""
    with zipfile.ZipFile(path) as archive:
        container = ET.fromstring(archive.read("META-INF/container.xml"))
        opf_path = container.find(".//{*}rootfile").get("full-path")
        opf = ET.fromstring(archive.read(opf_path))
        base = posixpath.dirname(opf_path)
        language = (opf.findtext(".//{http://purl.org/dc/elements/1.1/}language") or "").strip()
        # Manifest hrefs are URLs: chapter%20one.xhtml names "chapter one.xhtml".
        items = {item.get("id"): urllib.parse.unquote(urllib.parse.urlsplit(item.get("href")).path)
                 for item in opf.findall(".//{*}item")}
        names = [posixpath.normpath(posixpath.join(base, items[ref.get("idref")]))
                 for ref in opf.findall(".//{*}itemref") if ref.get("idref") in items]
        texts = [(name, archive.read(name).decode("utf-8", "replace")) for name in names]
    return language, texts


def pdf_words(text):
    """Splits like KOReader's MuPDF page text (ffi/mupdf.lua getPageText): at
    whitespace, and after a General Punctuation or CJK character, which stays
    on the word before (viññāṇaṃ—ime is viññāṇaṃ— and ime)."""
    word = ""
    for ch in text:
        if ch.isspace():
            if word:
                yield word
            word = ""
            continue
        word += ch
        c = ord(ch)
        if 0x2000 <= c <= 0x206F or 0x4E00 <= c <= 0x9FFF or 0x3000 <= c <= 0x303F or 0x3400 <= c <= 0x4DBF \
                or 0xF900 <= c <= 0xFAFF or 0xFF01 <= c <= 0xFFEE or 0x20000 <= c <= 0x2A6DF:
            yield word
            word = ""
    if word:
        yield word


def pdf_occurrences(path):
    """A PDF hold selects one of KOReader's MuPDF words, punctuation included;
    the plugin trims it as it would on the device. Words count as Pāḷi only
    with Pāḷi diacritics."""
    import pymupdf
    with pymupdf.open(path) as pdf:
        for number, page in enumerate(pdf, 1):
            words = [w for token in page.get_text("words") for w in pdf_words(unicodedata.normalize("NFC", token[4]))]
            for index, text in enumerate(words):
                if not any(is_letter(ch) for ch in text):
                    continue
                context = " ".join(words[max(0, index - 6):index] + ["[" + text + "]"] + words[index + 1:index + 7])
                yield {"text": text, "fragments": [text], "quoted": None,
                       "pali": any(ch in PALI_MARKS for ch in text), "where": f"p. {number}", "context": context}


def occurrences(path):
    """Yields one dict per word occurrence: the joined text, its fragments,
    an optional quote + ti form, whether it is Pāḷi, and where it is."""
    if str(path).lower().endswith(".pdf"):
        yield from pdf_occurrences(path)
        return
    if str(path).lower().endswith((".md", ".txt")):
        # KOReader shows these as plain text through crengine, like an EPUB.
        language, texts = "", [(pathlib.Path(path).name, html.escape(pathlib.Path(path).read_text(encoding="utf-8")))]
    else:
        language, texts = documents(path)
    book_pali = language.split("-")[0].lower() in ("pi", "pli")
    for name, xhtml in texts:
        parser = Text(book_pali)
        parser.feed(xhtml)
        chars, flags = parser.chars, parser.flags
        n, i = len(chars), 0
        while i < n:
            if not (chars[i] not in (FMT, BREAK) and is_letter(chars[i])):
                i += 1
                continue
            start, j, pieces, piece, pali = i, i, [], [], False
            while j < n and (chars[j] == FMT or (chars[j] != BREAK and is_letter(chars[j]))):
                if chars[j] == FMT:
                    if piece:
                        pieces.append("".join(piece))
                        piece = []
                else:
                    piece.append(chars[j])
                    pali = pali or bool(flags[j])
                j += 1
            if piece:
                pieces.append("".join(piece))
            text = "".join(pieces)
            # A closing quote, then a separate ti/nti: X’’ti, X’’nti, X”ti.
            k, quotes = j, ""
            while k < n and (chars[k] == FMT or (chars[k] in CLOSING_QUOTES and len(quotes) < 3)):
                if chars[k] != FMT:
                    quotes += chars[k]
                k += 1
            quoted = None
            if quotes:
                for particle in ("nti", "ti"):
                    tail = "".join(ch for ch in chars[k:k + len(particle) + 4] if ch != FMT)
                    if tail.startswith(particle) and not (len(tail) > len(particle) and is_letter(tail[len(particle)])
                                                          and tail[len(particle)] not in (FMT, BREAK)):
                        quoted = text + quotes + particle
                        break
            plain = lambda a, b: "".join(c if c not in (FMT, BREAK) else " " for c in chars[max(0, a):min(n, b)])
            context = " ".join((plain(start - 40, start) + "[" + text + "]" + plain(j, j + 40)).split())
            yield {"text": text, "fragments": pieces, "quoted": quoted,
                   "pali": pali or any(ch in PALI_MARKS for ch in text),
                   "where": posixpath.basename(name), "context": context}
            i = j


def run_lookups(forms, koreader, db):
    with tempfile.TemporaryDirectory() as tmp:
        source, target = pathlib.Path(tmp, "forms.txt"), pathlib.Path(tmp, "results.tsv")
        source.write_text("\n".join(sorted(forms)) + "\n", encoding="utf-8")
        result = subprocess.run(["./luajit", str(ROOT / "tools/audit_lookup.lua"), str(ROOT), str(db),
                                 str(source), str(target)], cwd=koreader, capture_output=True, text=True)
        if result.returncode != 0 or not target.exists():
            sys.exit("Lookup runner failed:\n" + result.stdout[-2000:] + result.stderr[-2000:])
        lines = target.read_text(encoding="utf-8").splitlines()
    release = lines[0].split("\t", 1)[1] if lines and lines[0].startswith("release\t") else ""
    results = {}
    for line in lines[1:]:
        cols = line.split("\t")
        if len(cols) < 13:
            continue
        results[cols[0]] = {"route": cols[1], "hit": cols[2] == "hit", "via": cols[3], "query": cols[4],
                            "long": cols[5] == "long", "begins": cols[6], "ends": cols[7],
                            "senses": int(cols[8] or 0), "analyses": int(cols[9] or 0),
                            "suggestion": cols[10], "ms": float(cols[11] or 0), "error": cols[12]}
    return release, results


def outcome(occ, results):
    """What a hold on this occurrence shows."""
    text, fragments, quoted = occ["text"], occ["fragments"], occ["quoted"]
    get = results.get
    if len(fragments) > 1:
        # KOReader selects only the part held.
        failed = [f for f in fragments if get(f, {}).get("route") == "error"]
        if failed:
            return {"status": "error", "form": text, "query": "", "via": "",
                    "note": "; ".join(f"{f}: {get(f)['error']}" for f in failed)}
        missed = [f for f in fragments if not get(f, {}).get("hit")]
        if missed:
            joined = " (DPD has the joined form)" if get(text, {}).get("hit") else ""
            status = "missing" if len(missed) == len(fragments) else "split"
            return {"status": status, "form": text, "query": "", "via": "",
                    "note": f"bold/italic split; part not found: {', '.join(missed)}{joined}"}
        return {"status": "found", "form": text, "query": "", "via": "", "note": "bold/italic split; each part found"}
    r = get(text) or {"route": "error", "error": "not looked up"}
    if r["route"] == "error":
        return {"status": "error", "form": text, "query": "", "via": "", "note": r.get("error", "")}
    note = ""
    if r["hit"]:
        status = "found"
    elif r["long"]:
        status = "long miss"
        parts = [p for p in ((r["begins"] and r["begins"] + "…"), (r["ends"] and "…" + r["ends"])) if p]
        note = "parts: " + ", ".join(parts) if parts else "no parts"
    else:
        status = "missing"
    if status != "found" and quoted and get(quoted, {}).get("hit"):
        note = (note + "; " if note else "") + f"before a quote; DPD has {quoted}"
    if r["via"] == "ti":
        note = (note + "; " if note else "") + "ti split from the next word"
    return {"status": status, "form": text, "query": r["query"], "via": r["via"], "note": note}


def key_for(occ):
    return "|".join(occ["fragments"]) + (occ["quoted"][len(occ["text"]):] if occ["quoted"] else "")


def audit(book, koreader, db):
    occs = list(occurrences(book))
    forms = set()
    for occ in occs:
        forms.add(occ["text"])
        if len(occ["fragments"]) > 1:
            forms.update(occ["fragments"])
        if occ["quoted"]:
            forms.add(occ["quoted"])
    release, results = run_lookups(forms, koreader, db)
    entries = {}
    for occ in occs:
        key = key_for(occ)
        entry = entries.get(key)
        if not entry:
            entry = entries[key] = dict(outcome(occ, results), count=0, pali=False,
                                        where=occ["where"], context=occ["context"])
        entry["count"] += 1
        entry["pali"] = entry["pali"] or occ["pali"]
    slow = sorted(((r["ms"], form) for form, r in results.items()), reverse=True)[:10]
    errors = sorted(form for form, r in results.items() if r["route"] == "error")
    return {"book": pathlib.Path(book).name, "release": release, "words": len(occs),
            "forms": len(results), "entries": entries, "slow": slow, "errors": errors}


def signature(entry):
    return [entry["status"], entry["query"], entry["via"], entry["note"]]


def table(rows, headers):
    out = ["| " + " | ".join(headers) + " |", "|" + "---|" * len(headers)]
    for row in rows:
        out.append("| " + " | ".join(str(cell).replace("|", "¦") for cell in row) + " |")
    return out


def report(result, baseline, limit):
    entries = result["entries"]
    pali = {k: e for k, e in entries.items() if e["pali"]}
    other = {k: e for k, e in entries.items() if not e["pali"]}
    by_status = collections.Counter()
    for e in pali.values():
        by_status[e["status"]] += e["count"]
    total = sum(e["count"] for e in pali.values()) or 1
    lines = [f"# DPD book audit: {result['book']}", "",
             f"DPD release {result['release'] or 'unknown'} · {datetime.date.today()} · "
             f"{result['words']:,} words, {len(entries):,} distinct, {result['forms']:,} forms looked up", "",
             "In book text, ¦ marks where bold or italic starts or stops inside a word.", ""]
    lines += table([[status, f"{by_status[status]:,}", f"{100 * by_status[status] / total:.2f}%",
                     sum(1 for e in pali.values() if e["status"] == status)]
                    for status in ("found", "split", "long miss", "missing", "error")],
                   ["Pāḷi words", "Occurrences", "Share", "Distinct"])
    grabbed = {k: e for k, e in other.items() if e["status"] == "found"}
    if other:
        lines += ["", f"Non-Pāḷi words: {sum(e['count'] for e in other.values()):,}; "
                      f"DPD opens {len(grabbed):,} distinct ones on long-press "
                      f"({sum(e['count'] for e in grabbed.values()):,} occurrences)."]

    def section(title, chosen, columns):
        rows = sorted(chosen.items(), key=lambda item: (-item[1]["count"], item[0]))
        if not rows:
            return
        lines.extend(["", f"## {title} ({len(rows)})", ""])
        lines.extend(table([columns(k, e) for k, e in rows[:limit]],
                           ["Book text", "Count", "Result", "Note", "Where", "Context"]))
        if len(rows) > limit:
            lines.append(f"\n… {len(rows) - limit} more")

    if baseline:
        before = baseline.get("entries", {})
        changed = {k: e for k, e in entries.items() if k in before and before[k] != signature(e)}
        added = {k: e for k, e in entries.items() if k not in before and e["status"] != "found"}
        lines += ["", f"## Changes since the baseline of {baseline.get('date', '?')} "
                      f"(DPD release {baseline.get('release') or 'unknown'})", ""]
        if not changed and not added:
            lines.append("No changes.")
        rows = []
        for k, e in sorted(changed.items(), key=lambda item: -item[1]["count"]):
            was = before[k]
            rows.append([k, e["count"], f"{was[0]} → {e['status']}", f"{was[1] or '-'} → {e['query'] or '-'}",
                         e["note"], e["where"]])
        for k, e in sorted(added.items(), key=lambda item: -item[1]["count"]):
            rows.append([k, e["count"], f"new · {e['status']}", e["query"] or "-", e["note"], e["where"]])
        if rows:
            lines.extend(table(rows[:limit * 2], ["Book text", "Count", "Status", "DPD form", "Note", "Where"]))
            if len(rows) > limit * 2:
                lines.append(f"\n… {len(rows) - limit * 2} more")
        removed = [k for k in before if k not in entries]
        if removed:
            lines.append(f"\n{len(removed)} distinct words in the baseline are no longer in the book.")

    def cols(k, e):
        return [k, e["count"], e["query"] or e["status"], e["note"], e["where"], e["context"]]
    section("Pāḷi words that open KOReader's dictionary", {k: e for k, e in pali.items() if e["status"] == "missing"}, cols)
    section("Split by bold or italic; a part opens KOReader's dictionary", {k: e for k, e in pali.items() if e["status"] == "split"}, cols)
    section("Long words on DPD's miss screen", {k: e for k, e in pali.items() if e["status"] == "long miss"}, cols)
    section("Non-Pāḷi words DPD opens on long-press", grabbed, cols)
    section("Lookup errors", {k: e for k, e in entries.items() if e["status"] == "error"}, cols)
    lines += ["", "## Slowest lookups (desktop ms)", ""]
    lines += table([[form, f"{ms:.0f}"] for ms, form in result["slow"]], ["Form", "ms"])
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("books", nargs="*", type=pathlib.Path)
    parser.add_argument("--koreader", type=pathlib.Path, default=os.environ.get("DPD_KOREADER"),
                        help="desktop KOReader directory (default $DPD_KOREADER)")
    parser.add_argument("--db", type=pathlib.Path, default=os.environ.get("DPD_DB"),
                        help="dpd-mobile.db (default $DPD_DB)")
    parser.add_argument("--out", type=pathlib.Path, default=ROOT / "test-artifacts/audit",
                        help="where baselines and reports go (default test-artifacts/audit)")
    parser.add_argument("--save", action="store_true", help="replace the baseline with this run")
    parser.add_argument("--limit", type=int, default=60, help="rows per report section")
    args = parser.parse_args()
    books = args.books or [pathlib.Path(p) for p in os.environ.get("DPD_AUDIT_BOOKS", "").split(os.pathsep) if p]
    if not books or not args.koreader or not args.db:
        parser.error("needs at least one book, --koreader and --db (or the DPD_* environment variables)")
    args.out.mkdir(parents=True, exist_ok=True)
    failed = False
    for book in books:
        result = audit(book, args.koreader.expanduser(), args.db.expanduser().resolve())
        stem = book.stem
        baseline_path = args.out / f"{stem}.baseline.json"
        baseline = json.loads(baseline_path.read_text(encoding="utf-8")) if baseline_path.exists() else None
        text = report(result, baseline, args.limit)
        report_path = args.out / f"{stem}.{datetime.date.today()}.md"
        report_path.write_text(text, encoding="utf-8")
        if args.save or baseline is None:
            baseline_path.write_text(json.dumps({
                "book": result["book"], "release": result["release"], "date": str(datetime.date.today()),
                "entries": {k: signature(e) for k, e in result["entries"].items()},
            }, ensure_ascii=False, indent=0), encoding="utf-8")
        summary = text.split("\n## ")[0].strip()
        changes = text.split("## Changes since", 1)
        print(summary)
        if baseline is not None:
            print("\n## Changes since" + changes[1].split("\n## ")[0] if len(changes) > 1 else "")
        print(f"\nReport: {report_path.relative_to(ROOT) if report_path.is_relative_to(ROOT) else report_path}"
              + ("\nBaseline saved." if args.save or baseline is None else ""))
        if result["errors"]:
            print(f"\n{len(result['errors'])} lookups raised an error: {', '.join(result['errors'][:10])}")
        failed = failed or bool(result["errors"]) or any(e["status"] == "error" for e in result["entries"].values())
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
