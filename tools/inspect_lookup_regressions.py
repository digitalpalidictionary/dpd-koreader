#!/usr/bin/env python3
"""Inspect reported DPD lookups without changing the database.

Related forms are diagnostic controls, not automatic corrections. Fuzzy groups
come from their stored keys, so this script does not invent a normalisation rule.
"""

import argparse
import json
from pathlib import Path
import sqlite3


CASES = {
    "saṃvidāvahāro": ["saṃvidāvahāra"],
    "avaharissāmā": ["avaharissāma", "avaharati", "avaharissāmāti"],
    "saṃmantayitvā": ["sammantayitvā", "samantayitvā", "sammantayitvāti"],
}
LOOKUP_COLUMNS = (
    "lookup_key", "headwords", "deconstructor", "grammar", "see",
    "spelling", "variant", "fuzzy_key",
)
SENSE_COLUMNS = (
    "id", "lemma_1", "pos", "meaning_1", "meaning_2", "construction",
)


def inspect(database):
    with sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True) as db:
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA query_only=ON")

        def lookup(word):
            row = db.execute(
                "SELECT " + ",".join(LOOKUP_COLUMNS)
                + " FROM lookup WHERE lookup_key = ?", (word,),
            ).fetchone()
            if row is None:
                return None
            result = dict(row)
            ids = json.loads(result["headwords"] or "[]")
            result["senses"] = []
            if ids:
                rows = db.execute(
                    "SELECT " + ",".join(SENSE_COLUMNS)
                    + " FROM dpd_headwords WHERE id IN ("
                    + ",".join("?" for _ in ids) + ") ORDER BY id", ids,
                )
                result["senses"] = [dict(sense) for sense in rows]
            return result

        report = {
            "release": db.execute(
                "SELECT value FROM db_info WHERE key = 'dpd_release_version'",
            ).fetchone()[0],
            "note": "Related forms are diagnostic controls, not corrections.",
            "cases": [],
        }
        for query, related in CASES.items():
            forms = [lookup(word) for word in [query, *related]]
            groups = {}
            for form in forms:
                if form and form["fuzzy_key"]:
                    key = form["fuzzy_key"]
                    if key not in groups:
                        words = db.execute(
                            "SELECT lookup_key FROM lookup WHERE fuzzy_key = ?"
                            " ORDER BY lookup_key", (key,),
                        )
                        groups[key] = [lookup(row[0]) for row in words]
            report["cases"].append({
                "query": query,
                "exact": forms[0],
                "related": dict(zip(related, forms[1:])),
                "related_fuzzy_groups": groups,
            })
        return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    args = parser.parse_args()
    print(json.dumps(inspect(args.database), ensure_ascii=False, indent=2))
