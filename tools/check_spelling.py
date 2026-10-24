#!/usr/bin/env python3
"""Compare the Look up a word "Did you mean" list before and after a change.

    python3 tools/check_spelling.py --koreader /path/to/koreader --db dpd-mobile.db \\
        [--baseline HEAD] [--per-set 1000]

Makes typed misses from the database and looks each one up twice through the
plugin's manual lookup in KOReader's LuaJIT (tools/spelling_lookup.lua): once
with the working tree and once with --baseline (a git ref, default HEAD).
Sets, each with a fixed random seed so runs compare:

  headword   one typo (drop, swap, change or add a letter) in a frequent headword
  form       the same in a random DPD form (inflections included)
  bare       a typo in a random form typed without diacritics
  niggahita  a form ending in ṃ typed without it (jāneyyu’’nti selects jāneyyu)

Typos that fuzzy matching already finds never show the list and are left out.
Reports how often the intended word is first and in the first five, the
lookup time, and every case where the baseline put it first and the working
tree does not. --koreader and --db default to $DPD_KOREADER and $DPD_DB.
"""
import argparse
import os
import pathlib
import random
import sqlite3
import statistics
import subprocess
import sys
import tempfile
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parent.parent
LETTERS = "a ā i ī u ū e o k g c j ñ ṭ ḍ ṇ t d n p b m y r l v s h ḷ ṃ".split()


def bare(text):
    return "".join(c for c in unicodedata.normalize("NFD", text) if not unicodedata.combining(c))


def typo(word, rng):
    chars = list(word)
    i = rng.randrange(len(chars))
    kind = rng.choice(["drop", "swap", "change", "add"])
    if kind == "drop":
        del chars[i]
    elif kind == "swap" and i < len(chars) - 1:
        chars[i], chars[i + 1] = chars[i + 1], chars[i]
    elif kind == "change":
        chars[i] = rng.choice([c for c in LETTERS if c != chars[i]])
    else:
        chars.insert(i, rng.choice(LETTERS))
    return "".join(chars)


def cases(db, per_set):
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    has = "coalesce(headwords, '') NOT IN ('', '[]')"
    keys = [r[0] for r in con.execute(f"SELECT lookup_key FROM lookup WHERE {has} AND lookup_key NOT LIKE '% %'")]
    known = set(keys)
    lemmas = []
    for (lemma,) in con.execute("SELECT lemma_1 FROM dpd_headwords ORDER BY ebt_count DESC"):
        lemma = lemma.rsplit(" ", 1)[0] if lemma.rsplit(" ", 1)[-1].replace(".", "").isdigit() else lemma
        if lemma in known and len(lemma) >= 4 and lemma not in lemmas:
            lemmas.append(lemma)
        if len(lemmas) >= per_set:
            break
    rng = random.Random(20261008)
    forms = rng.sample([k for k in keys if 5 <= len(k) <= 15], per_set * 2)
    ending = rng.sample([k for k in keys if k.endswith("ṃ") and len(k) >= 6], per_set)
    out = []
    for set_name, words, make in (("headword", lemmas, lambda w: typo(w, rng)),
                                  ("form", forms[:per_set], lambda w: typo(w, rng)),
                                  ("bare", forms[per_set:], lambda w: bare(typo(w, rng))),
                                  ("niggahita", ending, lambda w: w[:-1])):
        for word in words:
            typed = make(word)
            if typed != word and typed not in known and len(typed) >= 3:
                out.append((set_name, typed, word))
    return out


def run(root, koreader, db, rows):
    with tempfile.TemporaryDirectory() as tmp:
        source, target = pathlib.Path(tmp, "cases.tsv"), pathlib.Path(tmp, "results.tsv")
        source.write_text("".join("\t".join(r) + "\n" for r in rows), encoding="utf-8")
        result = subprocess.run(["./luajit", str(ROOT / "tools/spelling_lookup.lua"), str(root), str(db),
                                 str(source), str(target)], cwd=koreader, capture_output=True, text=True)
        if result.returncode != 0 or not target.exists():
            sys.exit("Lookup runner failed:\n" + result.stdout[-2000:] + result.stderr[-2000:])
        out = {}
        for line in target.read_text(encoding="utf-8").splitlines():
            set_name, typed, expected, rank, top, ms = line.split("\t")
            out[(set_name, typed, expected)] = (int(rank), top, float(ms))
        return out


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--koreader", type=pathlib.Path, default=os.environ.get("DPD_KOREADER"))
    parser.add_argument("--db", type=pathlib.Path, default=os.environ.get("DPD_DB"))
    parser.add_argument("--baseline", default="HEAD", help="git ref to compare against (default HEAD)")
    parser.add_argument("--per-set", type=int, default=1000)
    args = parser.parse_args()
    if not args.koreader or not args.db:
        parser.error("needs --koreader and --db (or the DPD_* environment variables)")
    koreader, db = args.koreader.expanduser(), args.db.expanduser().resolve()
    rows = cases(db, args.per_set)
    with tempfile.TemporaryDirectory() as base:
        archive = subprocess.run(["git", "-C", str(ROOT), "archive", args.baseline, "dpd"], capture_output=True, check=True)
        subprocess.run(["tar", "-x", "-C", base], input=archive.stdout, check=True)
        before = run(base, koreader, db, rows)
    after = run(ROOT, koreader, db, rows)

    print(f"{'set':<10} {'cases':>6}   first: before → after   top five: before → after")
    for set_name in ("headword", "form", "bare", "niggahita"):
        shown = [k for k in after if k[0] == set_name and after[k][0] >= 0 and before[k][0] >= 0]
        if not shown:
            continue
        def rate(results, best):
            return 100 * sum(1 for k in shown if 1 <= results[k][0] <= best) / len(shown)
        print(f"{set_name:<10} {len(shown):>6}   {rate(before, 1):5.1f}% → {rate(after, 1):5.1f}%"
              f"         {rate(before, 5):5.1f}% → {rate(after, 5):5.1f}%")
    for name, results in (("before", before), ("after", after)):
        times = sorted(v[2] for v in results.values())
        print(f"lookup ms {name}: median {statistics.median(times):.1f}, p95 {times[int(len(times) * 0.95)]:.1f},"
              f" worst {times[-1]:.1f}")
    lost = [k for k in after if before[k][0] == 1 and after[k][0] != 1]
    print(f"\n{len(lost)} cases where the intended word was first before and is not now:")
    for k in lost:
        print(f"  [{k[0]}] {k[1]} → {k[2]}: was {before[k][1]} | now {after[k][1]}")


if __name__ == "__main__":
    main()
