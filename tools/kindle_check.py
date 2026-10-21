#!/usr/bin/env python3
"""Check the plugin on a Kindle over SSH, in about two minutes.

    python3 tools/kindle_check.py [--install] --host root@<device-ip> [--port 2222]

Needs KOReader's SSH server and HTTP inspector running on the device (Tools →
More tools → HTTP inspector; tick "Start on KOReader startup" once), with DPD
on word long-press turned on. The SSH server's empty password is answered
automatically.

  --install   copy this checkout's plugin (main.lua, _meta.lua, dpd/, ui/),
              verify it and restart KOReader so it loads
  (always)    copy the test book and tools/kindle_drive.lua, which long-presses
              the book's words inside KOReader with its own word selection,
              painting and refresh; then fetch results and screenshots to
              test-artifacts/kindle/<time>/

Then it times the Vocabulary builder's save on long-press (off, first save,
already saved), Search other dictionaries, Other dictionaries and a long
article, restoring the Vocabulary builder setting and deleting its test cards.

Exits nonzero when a hold opens the wrong place. What it cannot check: your
finger, how the popup feels, sleep and wake.
"""
import argparse
import datetime
import io
import os
import pathlib
import statistics
import subprocess
import sys
import tarfile
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLUGIN = "/mnt/us/koreader/plugins/dpd.koplugin"
DRIVE = "/mnt/us/dpd-diag/drive"
BOOK = "/mnt/us/documents/dpd-test-book.epub"
INSPECTOR = "http://127.0.0.1:8080/koreader"


# Restarts as KOReader's own menu item does, once the inspector has replied.
# The inspector's event/Restart doesn't always reach the reader.
RESTART = """local UIManager = require("ui/uimanager")
UIManager:nextTick(function()
    local ui = require("apps/reader/readerui").instance or require("apps/filemanager/filemanager").instance
    if ui then ui:handleEvent(require("ui/event"):new("Restart")) end
end)
return "restarting"
"""
STAGING = "/mnt/us/dpd-diag/staging"
PREVIOUS = "/mnt/us/dpd-diag/previous"


def install(ssh, send):
    """Upload and verify a copy beside the plugins folder, then swap it in, so a
    dropped connection leaves the installed plugin as it was."""
    files = {"_meta.lua": ROOT / "_meta.lua", "main.lua": ROOT / "main.lua", "dpd": ROOT / "dpd", "ui": ROOT / "ui"}
    count = sum(1 for p in (ROOT / "dpd").rglob("*") if p.is_file()) + \
        sum(1 for p in (ROOT / "ui").rglob("*") if p.is_file()) + 2
    ssh(f"rm -rf '{STAGING}' && mkdir -p '{STAGING}'")
    send(files, STAGING)
    got = ssh(f"find '{STAGING}' -type f | wc -l; wc -c < '{STAGING}/main.lua'").split()
    if [int(got[0]), int(got[1])] != [count, (ROOT / "main.lua").stat().st_size]:
        sys.exit(f"Upload did not verify ({got} on the device, {count} files expected); the plugin is unchanged")
    # Same file system, so the moves are renames; put the old copy back if the second fails.
    ssh(f"rm -rf '{PREVIOUS}'; if [ -d '{PLUGIN}' ]; then mv '{PLUGIN}' '{PREVIOUS}'; fi; "
        f"if mv '{STAGING}' '{PLUGIN}'; then rm -rf '{PREVIOUS}'; "
        f"else [ -d '{PREVIOUS}' ] && mv '{PREVIOUS}' '{PLUGIN}'; exit 1; fi")
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    host = os.environ.get("DPD_KINDLE_HOST")
    parser.add_argument("--host", default=host, required=not host, help="e.g. root@<device-ip>, or set DPD_KINDLE_HOST")
    parser.add_argument("--port", default=os.environ.get("DPD_KINDLE_PORT", "2222"))
    parser.add_argument("--install", action="store_true", help="install this checkout's plugin and restart KOReader")
    args = parser.parse_args()

    tmp = tempfile.TemporaryDirectory()
    askpass = pathlib.Path(tmp.name, "askpass.sh")
    askpass.write_text('#!/bin/sh\necho ""\n')
    askpass.chmod(0o700)
    env = dict(os.environ, SSH_ASKPASS=str(askpass), SSH_ASKPASS_REQUIRE="force")

    def ssh(command, data=None, check=True):
        result = subprocess.run(["ssh", "-o", "PreferredAuthentications=password", "-o", "NumberOfPasswordPrompts=1",
                                 "-o", "ConnectTimeout=8", "-p", args.port, args.host, command],
                                input=data, capture_output=True, env=env)
        if check and result.returncode != 0:
            sys.exit(f"SSH failed ({command[:60]}…): {result.stderr.decode(errors='replace').strip()}\n"
                     "Is the Kindle on the network with KOReader's SSH server running? Its IP may have changed.")
        return result.stdout

    def send(files, target):
        """files: {name in target: local path}. A tar stream, since scp -r misnames folders on this device."""
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w") as archive:
            for name, path in files.items():
                archive.add(path, arcname=name)
        ssh(f"mkdir -p '{target}' && tar -C '{target}' -xf -", buffer.getvalue())

    def inspector_up():
        return ssh(f"curl -s -m3 -o /dev/null -w '%{{http_code}}' {INSPECTOR}/", check=False).strip() == b"200"

    if args.install:
        count = install(ssh, send)
        print(f"Installed {(ROOT / 'dpd/version.lua').read_text().split(chr(34))[1]} ({count} files); restarting KOReader")
        if not inspector_up():
            sys.exit("Installed, but the HTTP inspector is off: restart KOReader by hand, start the inspector, "
                     "then run this again without --install.")
        before = ssh("pidof luajit", check=False).split()
        ssh(f"mkdir -p '{DRIVE}' && cat > '{DRIVE}/restart.lua'", RESTART.encode())
        ssh(f"curl -s -m5 '{INSPECTOR}/globals/dofile/%22{DRIVE}/restart.lua%22/' >/dev/null", check=False)
        # A new KOReader process, answering again; the old one would keep the old plugin.
        for _ in range(60):
            time.sleep(2)
            now = ssh("pidof luajit", check=False).split()
            if now and not set(now) & set(before) and inspector_up():
                break
        else:
            sys.exit("KOReader did not restart with the inspector: restart it by hand, check that the inspector's "
                     "\"Start on KOReader startup\" is ticked, then run this again without --install.")

    if not inspector_up():
        sys.exit("The HTTP inspector is not running: Tools → More tools → HTTP inspector.")
    send({"kindle_drive.lua": ROOT / "tools/kindle_drive.lua"}, DRIVE)
    send({"dpd-test-book.epub": ROOT / "docs/dpd-test-book.epub"}, str(pathlib.PurePosixPath(BOOK).parent))
    ssh(f"rm -rf '{DRIVE}/out'")
    # The reply can be slow while the book reopens; the results file is the record.
    ssh(f"curl -s -m10 '{INSPECTOR}/globals/dofile/%22{DRIVE}/kindle_drive.lua%22/' >/dev/null", check=False)
    results = b""
    for _ in range(150):
        time.sleep(2)
        results = ssh(f"cat '{DRIVE}/out/results.tsv' 2>/dev/null", check=False)
        if b"DONE" in results or b"FAIL\topen" in results or b"FAIL\tplugin" in results or b"FAIL\tdirect" in results:
            break
    out = ROOT / "test-artifacts/kindle" / datetime.datetime.now().strftime("%Y-%m-%d-%H%M%S")
    out.mkdir(parents=True)
    with tarfile.open(fileobj=io.BytesIO(ssh(f"tar -C '{DRIVE}/out' -cf - .")), mode="r") as archive:
        archive.extractall(out, filter="data")
    lines = results.decode().splitlines()
    print("\n".join(lines))
    ms = {}
    for line in lines:
        fields = line.split("\t")
        if fields[0] in ("PASS", "FAIL") and fields[1].startswith("vocab-") and fields[-1].isdigit():
            ms.setdefault(fields[1].split("-")[1], []).append(int(fields[-1]))
    # Where a DPD long-press spends its time, the Vocabulary builder off: the
    # published headline is lookup + popup (DPD's own lookup and build).
    parts = {}
    for line in lines:
        fields = line.split("\t")
        if fields[0] == "PASS" and fields[3] == "dpd" and not fields[1].startswith(("vocab-first", "vocab-saved")) \
                and len(fields) == 8 and "select" in fields[6]:
            for part in fields[6].split(" · "):
                key, _, value = part.partition(" ")
                if value.isdigit():
                    parts.setdefault(key, []).append(int(value))
    if parts:
        print("DPD long-press, medians: " + ", ".join(
            f"{key} {statistics.median(values):.0f} ms" for key, values in parts.items()))
    for name, label in (("off", "Vocabulary builder off"), ("first", "first save"), ("saved", "already saved")):
        if ms.get(name):
            print(f"{label}: median {statistics.median(ms[name]):.0f} ms, worst {max(ms[name])} ms ({len(ms[name])} holds)")
    print(f"Screenshots: {out}")
    if "DONE" not in lines or any(line.startswith("FAIL") for line in lines):
        sys.exit(1)


if __name__ == "__main__":
    main()
