#!/usr/bin/env python3
"""Inspect a standalone DPD release file without changing it."""
import argparse
import json
import pathlib
import sqlite3


def file_journal_mode(database):
    """Read persisted mode; immutable connections can report DELETE for WAL files."""
    with database.open("rb") as source:
        header = source.read(20)
    if len(header) != 20 or header[:16] != b"SQLite format 3\x00":
        raise ValueError("Not a SQLite database")
    versions = (header[18], header[19])
    if versions == (2, 2):
        return "wal"
    if versions == (1, 1):
        return "rollback"  # DELETE/TRUNCATE/PERSIST cannot be distinguished here.
    raise ValueError(f"Unsupported SQLite header versions: {versions}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=pathlib.Path)
    parser.add_argument("--sizes", action="store_true", help="Also scan per-table dbstat page sizes")
    args = parser.parse_args()
    db = args.database.resolve()
    wal = db.with_name(db.name + "-wal")
    if wal.exists() and wal.stat().st_size:
        parser.error("Nonempty WAL sidecar: use a standalone, closed release copy; immutable reads ignore WAL changes")
    persisted_mode = file_journal_mode(db)
    with sqlite3.connect(db.as_uri() + "?mode=ro&immutable=1", uri=True) as conn:
        conn.row_factory = sqlite3.Row
        report = {"bytes": db.stat().st_size, "file_journal_mode": persisted_mode,
                  "immutable_connection_journal_mode": conn.execute("PRAGMA journal_mode").fetchone()[0],
                  "journal_note": "The file header identifies WAL or rollback format. The immutable connection's PRAGMA is not the persisted file mode; KOReader uses a normal read-only connection.",
                  "schema": {}, "samples": {}}
        for table in ("lookup", "dpd_headwords", "db_info"):
            report["schema"][table] = [row["name"] for row in conn.execute(f"PRAGMA table_info({table})")]
        report["release"] = dict(conn.execute(
            "SELECT key,value FROM db_info WHERE key IN ('dpd_release_version','db_schema_version','license','citation')"))
        for word in ("pacchima", "vajjakammappabhedanti", "pacchimakattikapuṇṇamā", "pacchimassa"):
            row = conn.execute("SELECT lookup_key,headwords,deconstructor,grammar FROM lookup WHERE lookup_key=?", (word,)).fetchone()
            report["samples"][word] = {key: json.loads(row[key]) if row[key] else []
                                       for key in ("headwords", "deconstructor", "grammar")} if row else None
        if args.sizes:
            report["table_bytes"] = dict(conn.execute("SELECT name,sum(pgsize) FROM dbstat GROUP BY name ORDER BY sum(pgsize) DESC"))
        print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
