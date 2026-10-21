"""Check the downloadable guides without access to the private repository."""
import hashlib
import json
import pathlib
import posixpath
import re
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGER = ROOT / "tools" / "package.py"
# Markdown links, and the README's <picture> image sources.
LINK = re.compile(r"\]\(([^)\s]+)\)|(?:href|src|srcset)=\"([^\"\s]+)\"")


class OfflineDocumentationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.out = pathlib.Path(cls.directory.name)
        subprocess.run([sys.executable, str(PACKAGER), "--out", str(cls.out)],
                       check=True, capture_output=True, text=True)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def check_documentation(self, archive, prefix):
        names = set(archive.namelist())
        guides = {prefix + name for name in ("README.md", "docs/USAGE.md", "docs/TESTING.md")}
        self.assertTrue(guides <= names)
        # Development notes are not shipped.
        self.assertEqual(guides, {name for name in names if name.endswith((".md", ".json"))})
        for name in sorted(names):
            if not name.endswith(".md"):
                continue
            text = archive.read(name).decode("utf-8")
            for target in map("".join, LINK.findall(text)):
                self.assertNotIn("github.com/nirodhav/", target,
                                 f"{name}: link to the old personal repository {target}")
                if re.match(r"[a-z]+:", target):
                    continue
                path, _, anchor = target.partition("#")
                destination = (posixpath.normpath(posixpath.join(posixpath.dirname(name), path))
                               if path else name)
                self.assertIn(destination, names, f"{name}: missing {target}")
                if anchor:
                    document = archive.read(destination).decode("utf-8")
                    headings = re.findall(r"^#+\s+(.+)$", document, re.MULTILINE)
                    slugs = {re.sub(r"[^\w\- ]", "", heading.lower()).replace(" ", "-")
                             for heading in headings}
                    self.assertIn(anchor, slugs, f"{name}: missing anchor {target}")

    def test_plugin_documentation_resolves_offline(self):
        plugin = next(self.out.glob("dpd-koplugin-*.zip"))
        with zipfile.ZipFile(plugin) as archive:
            self.check_documentation(archive, "dpd.koplugin/")

    def test_repeated_builds_produce_identical_downloads(self):
        with tempfile.TemporaryDirectory() as directory:
            subprocess.run([sys.executable, str(PACKAGER), "--out", directory],
                           check=True, capture_output=True, text=True)
            for file in self.out.iterdir():
                repeated = pathlib.Path(directory) / file.name
                self.assertEqual(hashlib.sha256(file.read_bytes()).digest(),
                                 hashlib.sha256(repeated.read_bytes()).digest(), file.name)

    def test_license_notices_and_source_are_in_the_plugin_download(self):
        plugin = next(self.out.glob("dpd-koplugin-*.zip"))
        with zipfile.ZipFile(plugin) as archive:
            for name in ("LICENSE", "LICENSE-DPD", "NOTICE", "main.lua", "dpd/about.lua"):
                self.assertEqual((ROOT / name).read_bytes(), archive.read("dpd.koplugin/" + name))

    def test_build_writes_only_the_plugin(self):
        names = [file.name for file in self.out.iterdir()]
        self.assertEqual(1, len(names))
        self.assertRegex(names[0], r"^dpd-koplugin-[0-9]+\.[0-9]+\.[0-9]+\.zip$")

    def test_committed_test_book_matches_its_generator(self):
        with tempfile.TemporaryDirectory() as directory:
            book = pathlib.Path(directory) / "dpd-test-book.epub"
            subprocess.run([sys.executable, str(ROOT / "tools/make_test_book.py"), "--out", str(book)],
                           check=True, capture_output=True, text=True)
            self.assertEqual(book.read_bytes(), (ROOT / "docs/dpd-test-book.epub").read_bytes(),
                             "run python3 tools/make_test_book.py")

    def test_current_release_metadata_agrees(self):
        version = re.fullmatch(r'return "([0-9]+\.[0-9]+\.[0-9]+)"\s*',
                               (ROOT / "dpd/version.lua").read_text()).group(1)
        readme = (ROOT / "README.md").read_text()
        usage = " ".join((ROOT / "docs/USAGE.md").read_text().split())
        self.assertIn("dpd-koplugin-<version>.zip", readme)
        self.assertNotIn(f"dpd-koplugin-{version}.zip", readme)
        minimum = re.search(r'minimum = "([^"]+)"', (ROOT / "dpd/compat.lua").read_text()).group(1)
        self.assertIn(f"**KOReader {minimum} or newer**", readme)
        self.assertIn(f"KOReader to {minimum} or newer", usage)
        compatibility = (ROOT / "dpd/db_compat.lua").read_text()
        schema = re.search(r'schema = "([^"]+)"', compatibility).group(1)
        release = re.search(r'release = "([^"]+)"', compatibility).group(1)
        self.assertIn("dpd-db/releases/latest", readme)
        self.assertIn(f"tested with DPD {release}", readme)
        self.assertIn(f"schema {schema}", readme)
        baseline = json.loads((ROOT / "tools/budget_baseline.json").read_text())
        self.assertEqual({"release": release, "schema": schema}, baseline["database"])


if __name__ == "__main__":
    unittest.main()
