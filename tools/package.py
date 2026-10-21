#!/usr/bin/env python3
"""Build the reproducible plugin ZIP."""
import argparse
import pathlib
import re
import zipfile


# Reader-facing guides, the README's screenshots and license notices only;
# development notes stay in the repository. These guides link only to each
# other and these images, so links work offline.
READER_DOCS = ("README.md", "docs/USAGE.md", "docs/TESTING.md",
               "docs/images/hero.png", "docs/images/find.png", "docs/images/deeper.png",
               "docs/images/hero-dark.png", "docs/images/find-dark.png", "docs/images/deeper-dark.png",
               "LICENSE", "LICENSE-DPD", "NOTICE")


def docs(root):
    return {name: (root / name).read_bytes() for name in READER_DOCS}


def put(archive, name, contents, compressed=True):
    info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED if compressed else zipfile.ZIP_STORED
    info.external_attr = 0o100644 << 16
    archive.writestr(info, contents)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=pathlib.Path, default=pathlib.Path("dist"))
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[1]
    args.out.mkdir(parents=True, exist_ok=True)
    runtime = [root / "_meta.lua", root / "main.lua"]
    runtime += sorted((root / "dpd").glob("*.lua")) + sorted((root / "ui").glob("*.lua"))
    version = re.fullmatch(r'return "([0-9]+\.[0-9]+\.[0-9]+)"\s*', (root / "dpd/version.lua").read_text()).group(1)
    plugin = args.out / f"dpd-koplugin-{version}.zip"
    with zipfile.ZipFile(plugin, "w") as archive:
        files = {file.relative_to(root).as_posix(): file.read_bytes() for file in runtime}
        files.update(docs(root))
        for name in sorted(files):
            put(archive, "dpd.koplugin/" + name, files[name])

    print(f"{plugin.resolve()} ({plugin.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
