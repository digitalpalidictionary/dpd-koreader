#!/usr/bin/env python3
"""Pair screenshots side by side, labelled, so a review reads two screens per image.

    python3 tools/contact_sheet.py out.png a.png [b.png ...]

Needs Pillow. Reviewing 80 screens as 40 sheets halves the images to inspect.
"""
import os
import sys

from PIL import Image, ImageDraw

COLUMNS, GAP, LABEL = 2, 20, 40


def main(out, files):
    images = [Image.open(path).convert("L") for path in files]
    width, height = images[0].size
    rows = (len(images) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("L", (COLUMNS * width + GAP, rows * (height + LABEL)), 255)
    draw = ImageDraw.Draw(sheet)
    for index, (path, image) in enumerate(zip(files, images)):
        x, y = (index % COLUMNS) * (width + GAP), (index // COLUMNS) * (height + LABEL)
        draw.text((x + 10, y + 5), os.path.basename(path), fill=0)
        sheet.paste(image.crop((0, 0, width, height)), (x, y + LABEL))
    sheet.save(out)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2:])
