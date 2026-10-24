"""Regression checks for persisted WAL mode versus immutable PRAGMA results."""
import importlib.util
import pathlib
import sqlite3
import subprocess
import sys
import tempfile
import unittest

PROBE = pathlib.Path(__file__).resolve().parents[1] / "tools" / "probe.py"
module = importlib.util.spec_from_file_location("dpd_probe", PROBE)
probe = importlib.util.module_from_spec(module)
module.loader.exec_module(probe)


class JournalModeTests(unittest.TestCase):
    def test_closed_wal_file_is_not_misreported_as_delete(self):
        with tempfile.TemporaryDirectory() as directory:
            database = pathlib.Path(directory) / "fixture.db"
            with sqlite3.connect(database) as connection:
                self.assertEqual(connection.execute("PRAGMA journal_mode=WAL").fetchone()[0], "wal")
                connection.execute("CREATE TABLE example(value TEXT)")
                connection.execute("INSERT INTO example VALUES ('committed')")
            connection.close()
            with sqlite3.connect(database.as_uri() + "?mode=ro&immutable=1", uri=True) as immutable:
                self.assertEqual(immutable.execute("PRAGMA journal_mode").fetchone()[0], "delete")
                self.assertEqual(immutable.execute("SELECT value FROM example").fetchone()[0], "committed")
            self.assertEqual(probe.file_journal_mode(database), "wal")

    def test_rollback_file_and_invalid_header(self):
        with tempfile.TemporaryDirectory() as directory:
            database = pathlib.Path(directory) / "fixture.db"
            with sqlite3.connect(database) as connection:
                connection.execute("CREATE TABLE example(value TEXT)")
            connection.close()
            self.assertEqual(probe.file_journal_mode(database), "rollback")
            database.write_bytes(b"not SQLite")
            with self.assertRaises(ValueError):
                probe.file_journal_mode(database)

    def test_probe_rejects_active_wal_instead_of_ignoring_committed_data(self):
        with tempfile.TemporaryDirectory() as directory:
            database = pathlib.Path(directory) / "fixture.db"
            connection = sqlite3.connect(database)
            try:
                connection.execute("PRAGMA journal_mode=WAL")
                connection.execute("CREATE TABLE example(value TEXT)")
                connection.commit()
                result = subprocess.run([sys.executable, str(PROBE), str(database)], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Nonempty WAL sidecar", result.stderr)
            finally:
                connection.close()


if __name__ == "__main__":
    unittest.main()
