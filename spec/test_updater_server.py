"""The native updater check's HTTP fixtures must stay inside their www root."""
import io
import pathlib
import sys
import tempfile
import unittest
from unittest import mock


TOOL = pathlib.Path(__file__).resolve().parents[1] / "tools" / "check_updater.lua"


class FixtureServer(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        base = pathlib.Path(self.temp.name)
        root = base / "www"
        (root / "good").mkdir(parents=True)
        (root / "good" / "SHA256SUMS").write_bytes(b"fixture checksum")
        (root / "good" / "release.json").write_bytes(b"fixture release")
        (root / "db.json").write_bytes(b"fixture database")
        (base / "private.txt").write_bytes(b"private marker")
        (base / "release.json").write_bytes(b"private marker")
        sibling = base / "www-other"
        sibling.mkdir()
        (sibling / "private.txt").write_bytes(b"private marker")
        (sibling / "release.json").write_bytes(b"private marker")
        (root / "outside-file").symlink_to(base / "private.txt")
        (root / "outside-dir").symlink_to(sibling, target_is_directory=True)
        (root / "db-outside.json").symlink_to(base / "private.txt")
        (root / "good-alias").symlink_to(root / "good", target_is_directory=True)
        alias = base / "www-alias"
        alias.symlink_to(root, target_is_directory=True)

        # Execute the actual embedded server's setup, stopping before it opens
        # listeners. Responses below exercise the same Handler without sockets.
        source = TOOL.read_text().split("write(server, [=[\n", 1)[1].split("\n]=])", 1)[0]
        setup = source.split('\nserve("http")', 1)[0]
        namespace = {}
        with mock.patch.object(sys, "argv", ["server.py", str(alias), str(base / "port"),
                                            str(base / "requests.log"), str(base / "certs")]):
            exec(compile(setup, str(TOOL), "exec"), namespace)
        self.handler = namespace["Handler"]

    def request(self, path):
        handler = object.__new__(self.handler)
        handler.path, handler.headers, handler.wfile = path, {}, io.BytesIO()
        with mock.patch.object(handler, "send_response") as status, \
                mock.patch.object(handler, "send_header"), mock.patch.object(handler, "end_headers"):
            handler.do_GET()
        return status.call_args.args[0], handler.wfile.getvalue()

    def test_fixture_routes_and_in_root_aliases(self):
        for path, body in (("/files/good/SHA256SUMS", b"fixture checksum"),
                           ("/files/good-alias/SHA256SUMS", b"fixture checksum"),
                           ("/api/good", b"fixture release"), ("/db", b"fixture database")):
            with self.subTest(path=path):
                self.assertEqual(self.request(path), (200, body))

    def test_paths_outside_fixture_root_are_not_served(self):
        for path in ("/files/../private.txt", "/files/good/../../private.txt", "/api/..",
                     "/files/../www-other/private.txt", "/files/outside-file",
                     "/files/outside-dir/private.txt", "/api/outside-dir", "/db-outside",
                     "/files/%2e%2e/private.txt", "/unknown", "/api"):
            with self.subTest(path=path):
                self.assertEqual(self.request(path), (404, b""))


if __name__ == "__main__":
    unittest.main()
