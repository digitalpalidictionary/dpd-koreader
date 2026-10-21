"""tools/kindle_check.py's install: a failed upload leaves the installed plugin alone."""
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import kindle_check  # noqa: E402


class Install(unittest.TestCase):
    def test_failed_upload_never_touches_the_installed_plugin(self):
        commands = []

        def ssh(command, data=None, check=True):
            commands.append(command)
            return b""

        def send(files, target):
            raise SystemExit("connection dropped")

        with self.assertRaises(SystemExit):
            kindle_check.install(ssh, send)
        self.assertFalse([c for c in commands if kindle_check.PLUGIN in c])

    def test_verified_upload_is_swapped_in(self):
        commands = []
        count = sum(1 for p in (ROOT / "dpd").rglob("*") if p.is_file()) + \
            sum(1 for p in (ROOT / "ui").rglob("*") if p.is_file()) + 2

        def ssh(command, data=None, check=True):
            commands.append(command)
            if command.startswith("find"):
                return f"{count}\n{(ROOT / 'main.lua').stat().st_size}\n".encode()
            return b""

        kindle_check.install(ssh, lambda files, target: None)
        self.assertIn(f"mv '{kindle_check.STAGING}' '{kindle_check.PLUGIN}'", commands[-1])


if __name__ == "__main__":
    unittest.main()
