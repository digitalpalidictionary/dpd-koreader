#!/usr/bin/env python3
"""Regenerate the README images (docs/images/hero.png, find.png, deeper.png and
their -dark versions) and the repository's social preview card
(docs/images/social-preview.png) from desktop KOReader.

Needs Pillow and the macOS KOReader app (or --koreader pointing at another
desktop build's koreader directory). The capture script names headword ids
from DPD v0.4.20260926, and the crops below fit that data; check both after a
database update.
"""
import argparse
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import types
import urllib.request
import zipfile

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[1]
FONTS = {  # OFL, from Google Fonts. Inter covers Pāḷi, ṁ, √ and arrows; Vollkorn the headings.
    "Inter.ttf": "https://github.com/google/fonts/raw/main/ofl/inter/Inter%5Bopsz,wght%5D.ttf",
    "Vollkorn.ttf": "https://github.com/google/fonts/raw/main/ofl/vollkorn/Vollkorn%5Bwght%5D.ttf",
}
HEADING = ("Vollkorn.ttf", lambda size: [600])  # semibold; lining figures are set when drawn
WIDTH = 1760  # 2x the README column on GitHub

# A short Pāḷi passage holding every word the capture looks up.
PASSAGE = [
    "<h2>Paṭiccasamuppāda</h2>",
    "<p>Evaṃ me sutaṃ — ekaṃ samayaṃ bhagavā sāvatthiyaṃ viharati jetavane anāthapiṇḍikassa ārāme. "
    "Tatra kho bhagavā bhikkhū āmantesi — “bhikkhavo”ti. “Bhadante”ti te bhikkhū bhagavato "
    "paccassosuṃ. Bhagavā etadavoca —</p>",
    "<p>“Paṭiccasamuppādaṃ vo, bhikkhave, desessāmi. Taṃ suṇātha, sādhukaṃ manasi karotha, "
    "bhāsissāmī”ti. “Evaṃ, bhante”ti kho te bhikkhū bhagavato paccassosuṃ.</p>",
    "<p>Avijjāpaccayā, bhikkhave, saṅkhārā; saṅkhārapaccayā viññāṇaṃ; viññāṇapaccayā nāmarūpaṃ; "
    "nāmarūpapaccayā saḷāyatanaṃ; saḷāyatanapaccayā phasso; phassapaccayā vedanā; vedanāpaccayā "
    "taṇhā; taṇhāpaccayā upādānaṃ; upādānapaccayā bhavo; bhavapaccayā jāti; jātipaccayā jarāmaraṇaṃ "
    "sokaparidevadukkhadomanassupāyāsā sambhavanti. Evametassa kevalassa dukkhakkhandhassa "
    "samudayo hoti.</p>",
    "<p>Te bhikkhū sīlasamādhipaññāvimuttivimuttiñāṇadassanasampannā. Idaṃ garubhaṇḍaṃ avissajjiyaṃ, idaṃ "
    "vissajjiyavebhaṅgiyaṃ. Tassa gehe suvaṇṇavalayanūpurādisaṅghaṭṭanasaddasammissita "
    "gītavāditasaddo hoti; so pana dhammaṃ suṇāti.</p>",
    "<p>Ekāyano ayaṃ, bhikkhave, maggo sattānaṃ visuddhiyā, sokaparidevānaṃ samatikkamāya, "
    "dukkhadomanassānaṃ atthaṅgamāya, ñāyassa adhigamāya, nibbānassa sacchikiriyāya, yadidaṃ "
    "cattāro satipaṭṭhānā. Idha, bhikkhave, bhikkhu kāye kāyānupassī viharati ātāpī sampajāno "
    "satimā, vineyya loke abhijjhādomanassaṃ; dhammesu dhammānupassī viharati. So gacchati, "
    "dhammaṃ suṇāti, cittaṃ bhāveti.</p>",
    "<p>Te bhikkhū saṃmantayitvā indakhile aṭṭhaṃsu.</p>",
]

def write_book(path):
    html = ('<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml">'
            '<head><title>Sutta</title><style>p{text-align:justify}</style></head><body>'
            + "".join(PASSAGE) + "</body></html>")
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", '<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        z.writestr("content.opf", '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Sutta</dc:title><dc:identifier id="id">dpd-readme</dc:identifier><dc:language>pi</dc:language></metadata><manifest><item id="t" href="t.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="t"/></spine></package>')
        z.writestr("t.xhtml", html)




# Both profiles use the Paperwhite's 1264x1680 screen at 300 dpi. Larger
# popup type keeps the slim tiles legible after scaling the full-width popup.
PROFILES = {"paperwhite": 1264, "large-type": 1264}


def capture(koreader, database, work):
    ko = work / "koreader"
    shutil.copytree(koreader, ko, symlinks=True)
    book = work / "sutta.epub"
    write_book(book)
    # SQLite may add -wal/-shm files beside the database; keep them off the original.
    db = work / "dpd.db"
    shutil.copyfile(database, db)
    for profile, width in PROFILES.items():
        (work / "xdg" / profile).mkdir(parents=True)
        (work / "shots" / profile).mkdir(parents=True)
        env = dict(os.environ, SDL_VIDEODRIVER="dummy", KO_MULTIUSER="1", XDG_CONFIG_HOME=str(work / "xdg" / profile),
                   EMULATE_READER_W=str(width), EMULATE_READER_H="1680", EMULATE_READER_DPI="300",
                   EMULATE_BW_SCREEN="1")
        result = subprocess.run(["./luajit", str(ROOT / "tools/readme_capture.lua"), str(ROOT), str(db),
                                 str(book), str(work / "shots" / profile), profile],
                                cwd=ko, env=env, capture_output=True, text=True, timeout=600)
        if result.returncode != 0 or "DONE" not in result.stdout:
            sys.exit(result.stdout[-4000:] + result.stderr[-4000:])
    return work / "shots"


def popup(path):
    """Crop a screenshot to the popup's outer frame."""
    im = Image.open(path).convert("L")
    w, h = im.size
    px = im.load()
    y = h // 2
    dark = [x for x in range(w - 3) if all(px[x + k, y] < 60 for k in range(3))]
    x0 = next(x for x in dark if x > 30)
    x1 = max(x for x in dark if x < w - 30) + 2
    # Full-width dark rows are the frame's top and bottom borders.
    rows = [yy for yy in range(h - 120)
            if sum(px[x, yy] < 60 for x in range(x0 + 6, x1 - 6)) > 0.97 * (x1 - x0 - 12)]
    return im.crop((x0, min(rows), x1 + 1, max(rows) + 3))


# Palette: warm paper, saffron accent; the screenshots themselves stay grey.
BG, TILE = (247, 241, 231, 255), (238, 228, 212, 255)
INK, MUTED = (43, 33, 24, 255), (107, 93, 79, 255)
ACCENT, ACCENT_DARK, TAN = (217, 115, 26, 255), (154, 82, 15, 255), (255, 228, 200, 255)
WHITE = (255, 255, 255, 255)
MARGIN, PAD = 88, 28


def night(card, ink):
    """KOReader's night mode as a warm tone map: paper becomes card, ink cream."""
    lut = [round(card[c] + (ink[c] - card[c]) * (255 - v) / 255) for c in range(3) for v in range(256)]

    def apply(im):
        out = Image.merge("RGB", [im.convert("L")] * 3).point(lut).convert("RGBA")
        if im.mode == "RGBA":
            out.putalpha(im.getchannel("A"))
        return out
    return apply


# Each image is written once per theme; README.md picks one with <picture>.
# Dark tones the screenshots like night mode and turns saffron to ember.
THEMES = {
    "": types.SimpleNamespace(
        bg=BG, tile=TILE, ink=INK, muted=MUTED, label=ACCENT_DARK,
        accent=ACCENT, on_accent=WHITE, accent_note=TAN, screen=None,
        # Device shell fill and outline, face fill and outline, inner edge.
        device=((22, 23, 24), (65, 65, 64), (44, 45, 44), (110, 111, 107), (25, 26, 26))),
    "-dark": types.SimpleNamespace(
        bg=(24, 21, 18, 255), tile=(36, 31, 26, 255), ink=(242, 232, 218, 255),
        muted=(160, 147, 132, 255), label=(240, 160, 80, 255),
        accent=(112, 58, 22, 255), on_accent=(252, 222, 186, 255), accent_note=(206, 160, 118, 255),
        screen=night((50, 44, 37), (236, 227, 214)),
        device=((14, 12, 11), (58, 52, 46), (66, 60, 54), (128, 119, 108), (30, 27, 24))),
}

class Fonts:
    def __init__(self, directory, heading=None):
        self.dir = directory
        # (file, axes for a size) of the heading face; Inter semibold if None.
        self.heading = heading

    def get(self, name, size, axes):
        face = ImageFont.truetype(str(self.dir / name), size)
        if axes:
            face.set_variation_by_axes(axes)
        return face

    def title(self, size=80):
        """The heading face, sized to match Inter semibold's cap height."""
        inter = self.text(size, 600)
        if not self.heading:
            return inter
        name, axes = self.heading
        face = self.get(name, size, axes and axes(size))
        k = cap_height(inter) / cap_height(face)
        return self.get(name, round(size * k), axes and axes(round(size * k)))

    def text(self, size, weight=450):
        return self.get("Inter.ttf", size, [min(max(size, 14), 32), weight])  # opsz, wght


def cap_height(face):
    return -face.getbbox("H", anchor="ls")[1]


class Canvas:
    def __init__(self, fonts, height, title, subtitle, theme=THEMES[""], width=WIDTH):
        self.fonts, self.theme = fonts, theme
        self.im = Image.new("RGBA", (width, height), theme.bg)
        self.draw = ImageDraw.Draw(self.im)
        self.heading((MARGIN, 72), title, 80)
        self.draw.text((MARGIN, 176), subtitle, font=fonts.text(32), fill=theme.muted)
        self.top, self.bottom, self.right = 246, height - 72, width - MARGIN

    def shadow(self, box, radius=24, blur=26, dy=18, alpha=55):
        x0, y0, x1, y1 = box
        mask = Image.new("L", self.im.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle((x0, y0 + dy, x1, y1 + dy), radius, fill=alpha)
        self.im.paste(Image.new("RGBA", self.im.size, (40, 25, 10, 255)), (0, 0), mask.filter(ImageFilter.GaussianBlur(blur)))
        self.draw = ImageDraw.Draw(self.im)

    def tile(self, box, fill=None, label=None, color=None):
        self.draw.rounded_rectangle(box, 30, fill=fill or self.theme.tile)
        if label:
            self.draw.text((box[0] + PAD + 6, box[3] - 50), label, font=self.fonts.text(26, 650),
                           fill=color or self.theme.label)

    def place(self, im, xy, alpha=40):
        """A screenshot cutout with a shadow, toned for the theme."""
        if self.theme.screen:
            im = self.theme.screen(im)
        x, y = xy
        self.shadow((x, y, x + im.width, y + im.height), alpha=alpha)
        self.im.alpha_composite(im, (x, y))
        self.draw = ImageDraw.Draw(self.im)
        return (x, y, x + im.width, y + im.height)

    def heading(self, xy, text, size, color=None):
        """Headings on Inter's baselines, so any heading face keeps the layout."""
        x, y = xy
        inter = self.fonts.text(size, 600)
        # Inter keeps Pillow's tight multiline step; other faces get book leading.
        step = inter.getbbox("A")[3] if not self.fonts.heading else round(size * 1.1)
        for i, line in enumerate(text.split("\n")):
            self.draw.text((x, y + inter.getmetrics()[0] + i * step), line, font=self.fonts.title(size),
                           fill=color or self.theme.ink, anchor="ls", features=["lnum"])

    def text(self, xy, text, size, color, weight=450, spacing=8):
        self.draw.multiline_text(xy, text, font=self.fonts.text(size, weight), fill=color, spacing=spacing)

    def save(self, path):
        """255 colours plus a transparent one for the rounded corners."""
        image = self.im.convert("RGB").quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        palette = image.getpalette()[:255 * 3]
        image.putpalette(palette + [0] * (255 * 3 - len(palette)) + [0, 0, 0])
        corners = Image.new("L", image.size, 255)
        ImageDraw.Draw(corners).rounded_rectangle((0, 0, WIDTH - 1, image.height - 1), 44, fill=0)
        image.paste(255, (0, 0), corners)
        image.save(path, optimize=True, transparency=255)
        print(f"{path} ({path.stat().st_size:,} bytes)")


def scaled(im, k):
    return im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)


def rounded(im, radius, border=False):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), radius, fill=255)
    out = im.convert("RGBA")
    if border:
        ImageDraw.Draw(out).rounded_rectangle((0, 0, im.width - 1, im.height - 1), radius,
                                             outline=(210, 202, 190, 255), width=2)
    out.putalpha(mask)
    return out


def faded(im, px=90):
    """Fade the bottom of a cut card into white."""
    im = im.convert("RGBA")
    ramp = Image.linear_gradient("L").resize((im.width, px))
    part = im.crop((0, im.height - px, im.width, im.height))
    im.paste(Image.composite(Image.new("RGBA", (im.width, px), WHITE), part, ramp), (0, im.height - px))
    return im


def card(path, k, max_h, fade_px=90):
    """A popup scaled by k, cut and faded if taller than max_h."""
    im = popup(path).convert("RGB")
    # Trim the captured black outer frame; a quiet warm-grey outline fits the
    # surrounding tiles while preserving the title, controls and body pixels.
    im = im.crop((4, 4, im.width - 4, im.height - 4))
    rows = int(max_h / k)
    if rows < im.height:
        return rounded(faded(scaled(im.crop((0, 0, im.width, rows)), k), fade_px), 18, border=True)
    return rounded(scaled(im, k), 18, border=True)


def dimensional_device(path, theme, width=540):
    """A real reader screen in a stylized bezel, with shallow perspective.

    Only the frame is drawn. Book text and selection are untouched screenshot
    pixels. The foreground dictionary popup is composed separately.
    """
    source = Image.open(path).convert("RGB")
    if theme.screen:
        source = theme.screen(source)
    inset = 30
    screen = rounded(scaled(source, (width - 2 * inset) / source.width), 12)
    height = screen.height + 2 * inset + 18
    layer = Image.new("RGBA", (width + 36, height + 36))
    d = ImageDraw.Draw(layer)
    shell, shell_edge, face, face_edge, inner = theme.device
    d.rounded_rectangle((10, 14, width + 8, height + 12), 48, fill=shell,
                        outline=shell_edge, width=3)
    d.rounded_rectangle((4, 4, width, height), 46, fill=face,
                        outline=face_edge, width=3)
    d.rounded_rectangle((12, 12, width - 8, height - 8), 40,
                        outline=inner, width=4)
    layer.alpha_composite(screen, (inset, inset))
    # A padded inverse quadrilateral gives a mild tilted face, not a distorted
    # popup. Transparent padding preserves all bezel edges after the transform.
    w, h = layer.size
    padded = Image.new("RGBA", (w + 100, h + 100))
    padded.alpha_composite(layer, (50, 50))
    return padded.transform(padded.size, Image.Transform.QUAD,
                            (20, 45, 48, h + 76, w + 90, h + 40, w + 55, 10),
                            Image.Resampling.BICUBIC)


def hero(shots, fonts, out, theme):
    pw = shots / "paperwhite"
    backdrop = pw / "compound-book.png"
    for name in ("compound-book.png", "hero-senses.png"):
        if not (pw / name).exists():
            raise ValueError(f"Missing {name}; recapture with --keep before using --shots")
    # Hero has its own spacing; the other two image compositions stay stable.
    c = Canvas(fonts, 1280, "", "", theme)
    c.heading((54, 44), "Read Pāḷi. Understand more.", 86)
    left = (44, 160, 980, 1236)
    senses = (1004, 160, 1716, 650)
    grammar = (1004, 674, 1716, 1090)
    speed = (1004, 1114, 1716, 1236)
    for box in (left, senses, grammar):
        c.tile(box)

    dev = dimensional_device(backdrop, theme)
    # Shadow follows the tilted device silhouette, not its rectangular bounds.
    shadow = Image.new("RGBA", c.im.size)
    silhouette = Image.new("L", c.im.size)
    silhouette.paste(dev.getchannel("A"), (52, 202))
    shadow.paste((35, 28, 20, 75), (0, 0, WIDTH, c.im.height),
                 silhouette.filter(ImageFilter.GaussianBlur(22)))
    c.im.alpha_composite(shadow)
    c.im.alpha_composite(dev, (44, 180))
    c.draw = ImageDraw.Draw(c.im)
    # Crop complete rows from genuine KOReader output; never redraw UI text.
    compound = card(pw / "compound.png", 0.59, 785)
    c.place(compound, (962 - compound.width, 264), 65)
    c.text((78, 1053), "Long-press a word", 26, theme.muted, 500)
    c.heading((74, 1092), "Compounds, explained\nin one lookup", 54)

    c.heading((1034, 180), "Every sense in one view", 45)
    sense = card(pw / "hero-senses.png", 0.54, 380, fade_px=32)
    c.place(sense, (1034, 247))

    c.heading((1034, 693), "Declensions &\nconjugations", 43)
    # Leave headroom above the column headers and below the last row.
    decl = scaled(Image.open(pw / "declension.png").convert("RGB")
                  .crop((60, 336, 660, 860)), 0.50)
    # The present-tense rows only: crop from the original full screenshot.
    conj = scaled(Image.open(pw / "conjugation.png").convert("RGB")
                  .crop((60, 410, 660, 738)), 0.50)
    # Offset cutouts retain the bento's depth without hiding any table content.
    c.place(rounded(decl, 10), (1034, 805), 50)
    c.place(rounded(conj, 10), (1368, 905), 50)

    c.tile(speed, fill=theme.accent)
    c.heading((1030, 1117), "50 ms", 88, theme.on_accent)
    c.text((1298, 1125), "Typical lookup on\nKindle Paperwhite", 25, theme.on_accent, 550, 4)
    c.text((1298, 1195), "Excludes e-ink refresh", 20, theme.accent_note)
    c.save(out)


def find(shots, fonts, out, theme):
    pw, large = shots / "paperwhite", shots / "large-type"
    for name in ("find-english.png", "find-similar.png"):
        if not (large / name).exists():
            raise ValueError(f"Missing {name}; recapture with --keep before using --shots")
    c = Canvas(fonts, 1280, "", "", theme)
    c.heading((54, 44), "Find any word.", 86)
    c.text((58, 148), "In Pāḷi or English, with or without diacritics.", 30, theme.muted)
    english = (44, 210, 920, 746)
    spelling = (944, 210, 1716, 746)
    suggestions = (44, 770, 800, 1236)
    velthuis = (824, 770, 1716, 1128)
    variants = (824, 1152, 1716, 1236)
    for box in (english, spelling, suggestions, velthuis):
        c.tile(box)
    c.heading((74, 228), "English to Pāḷi", 43)
    c.place(card(large / "find-english.png", 0.68, 412, fade_px=32), (74, 304))

    c.heading((974, 228), "Find close matches", 43)
    # Skip the title bar, retaining the actual no-match explanation and rows.
    similar = popup(large / "find-similar.png").convert("RGB")
    similar = rounded(scaled(similar.crop((12, 128, similar.width - 18, 598)), 0.61), 14)
    c.place(similar, (974, 304))
    # A second floating cutout demonstrates typo suggestions without a long list.
    typo = scaled(Image.open(pw / "spelling.png").convert("RGB")
                  .crop((60, 486, 480, 596)), 0.90)
    c.place(rounded(typo, 12), (1304, 612), 55)

    c.heading((74, 790), "Suggestions as you type", 43)
    typing = Image.open(pw / "suggestions.png").convert("RGB").crop((126, 578, 1136, 1106))
    c.place(rounded(scaled(typing, 0.60), 14), (100, 866))
    c.heading((854, 790), "No Pāḷi keyboard needed", 43)
    # Keep the actual input and first suggestions row; omit the remaining rows.
    entry = Image.open(pw / "velthuis.png").convert("RGB").crop((126, 578, 1136, 901))
    c.place(rounded(scaled(entry, 0.78), 14), (874, 852))
    c.tile(variants, fill=theme.accent)
    c.text((854, 1164), "saṃ  saṁ  saŋ", 46, theme.on_accent, 650)
    c.text((1234, 1175), "All find the same word.", 28, theme.on_accent, 500)
    c.save(out)


def deeper(shots, fonts, out, theme):
    pw, large = shots / "paperwhite", shots / "large-type"
    c = Canvas(fonts, 1340, "", "", theme)
    c.heading((54, 44), "Go deeper.", 86)
    c.text((58, 148), "Roots, families, frequency and more, a tap from any entry.", 30, theme.muted)
    frequency = (44, 210, 884, 738)
    sutta = (908, 210, 1372, 738)
    matrix = (1396, 210, 1716, 738)
    dictionaries = (44, 762, 884, 1296)
    families = (908, 762, 1716, 1296)
    for box in (frequency, sutta, matrix, dictionaries, families):
        c.tile(box)
    c.heading((74, 232), "Frequency by edition", 43)
    # Fewer rows at a larger scale; retain the complete edition column headers.
    table = Image.open(pw / "frequency.png").convert("RGB").crop((58, 240, 1195, 820))
    c.place(rounded(faded(scaled(table, 0.68), 30), 14), (74, 310))
    c.heading((938, 232), "Sutta details", 40)
    c.place(card(large / "sutta.png", 0.35, 398, fade_px=32), (938, 310))
    c.heading((1420, 237), "Root matrix", 34)
    # Include the real root heading, so the counts have an identifiable subject.
    root = Image.open(pw / "matrix.png").convert("RGB").crop((60, 135, 520, 815))
    c.place(rounded(faded(scaled(root, 0.57), 30), 14), (1420, 310))
    c.heading((74, 784), "Compare dictionaries", 43)
    c.place(card(pw / "dictionaries.png", 0.68, 404, fade_px=32), (74, 858))
    c.heading((938, 784), "Families & thematic sets", 43)
    c.place(card(large / "family-word.png", 0.32, 404, fade_px=32), (932, 858))
    c.place(card(large / "family.png", 0.32, 404, fade_px=32), (1328, 858))
    c.save(out)


def social(shots, fonts, out, theme):
    """GitHub's 1280x640 repository card, uploaded under Settings > General.

    Platforms crop the edges, so everything but the device stays 80 px in, as
    GitHub's repo card template recommends. Only the light theme is drawn:
    one image serves every viewer.
    """
    pw = shots / "paperwhite"
    x0, y0, x1, y1 = 80, 80, 1200, 560
    c = Canvas(fonts, 640, "", "", theme, width=1280)
    pop = card(pw / "compound.png", 0.47, y1 - 88, fade_px=60)
    px = x1 - pop.width
    dev = dimensional_device(pw / "compound-book.png", theme, width=470)
    shadow = Image.new("RGBA", c.im.size)
    silhouette = Image.new("L", c.im.size)
    silhouette.paste(dev.getchannel("A"), (px - 86, 34))
    shadow.paste((35, 28, 20, 75), (0, 0) + c.im.size, silhouette.filter(ImageFilter.GaussianBlur(20)))
    c.im.alpha_composite(shadow)
    c.im.alpha_composite(dev, (px - 94, 12))
    c.place(pop, (px, 88), 65)
    # DPD's logo, rasterised from its SVG and cut to the circle.
    with Image.open(ROOT / "docs/images/dpd-logo.png") as logo:
        c.im.alpha_composite(logo.convert("RGBA").resize((52, 52), Image.LANCZOS), (x0, y0))
    d = c.draw = ImageDraw.Draw(c.im)
    title = fonts.title(70)
    for i, line in enumerate(("Digital Pāḷi", "Dictionary")):
        d.text((x0 - 3, 210 + i * 77), line, font=title, fill=theme.ink, anchor="ls", features=["lnum"])
    d.text((x0 - 2, 354), "for KOReader", font=fonts.title(48), fill=theme.label, anchor="ls",
           features=["lnum"])
    plain = fonts.text(30, 450)
    d.text((x0, 414), "Pāḷi words and compounds,", font=plain, fill=theme.muted, anchor="ls")
    lead = "explained in "
    d.text((x0, 464), lead, font=plain, fill=theme.muted, anchor="ls")
    # "one lookup" on a saffron marker, like KOReader's selection highlight.
    x = x0 + d.textlength(lead, font=plain) + 4
    bold = fonts.text(38, 700)
    w = d.textlength("one lookup", font=bold)
    d.rounded_rectangle((x - 8, 464 - cap_height(bold) - 10, x + w + 8, 475), 7, fill=(250, 196, 128, 255))
    d.text((x, 464), "one lookup", font=bold, fill=theme.ink, anchor="ls")
    # Outlined, so the marker is the only saffron fill.
    label = "≈ 50 ms lookups on Kindle"
    f = fonts.text(24, 600)
    d.rounded_rectangle((x0, y1 - 46, x0 + d.textlength(label, font=f) + 44, y1), 23,
                        outline=theme.accent, width=3)
    d.text((x0 + 22, y1 - 23), label, font=f, fill=theme.label, anchor="lm")
    # Opaque and square: the platforms round and crop the card themselves.
    c.im.convert("RGB").save(out, optimize=True)
    print(f"{out} ({out.stat().st_size:,} bytes)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--koreader", type=pathlib.Path,
                        default=pathlib.Path("/Applications/KOReader.app/Contents/koreader"))
    parser.add_argument("--db", type=pathlib.Path, default=ROOT / "test-artifacts/20260930/dpd-mobile.db")
    parser.add_argument("--fonts", type=pathlib.Path, help="folder with Inter.ttf and Vollkorn.ttf; downloaded if omitted")
    parser.add_argument("--shots", type=pathlib.Path, help="reuse captures from an earlier --keep run")
    parser.add_argument("--keep", type=pathlib.Path, help="also copy the captures here")
    parser.add_argument("--only", choices=("hero", "find", "deeper", "social"),
                        help="render just one image (capture still collects all screens)")
    parser.add_argument("--out", type=pathlib.Path, default=ROOT / "docs/images")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as directory:
        work = pathlib.Path(directory)
        fonts = args.fonts or work
        for name, url in FONTS.items():
            if not (fonts / name).exists():
                urllib.request.urlretrieve(url, fonts / name)
        shots = args.shots or capture(args.koreader, args.db.resolve(), work)
        for profile in PROFILES:
            captures = list((shots / profile).glob("*.png"))
            if not captures:
                raise ValueError(f"Missing {profile} captures; recapture with --keep")
            for path in captures:
                with Image.open(path) as im:
                    if im.size != (1264, 1680):
                        raise ValueError(f"{path}: expected Paperwhite resolution 1264x1680, got {im.size}")
        if args.keep:
            shutil.copytree(shots, args.keep, dirs_exist_ok=True)
        args.out.mkdir(parents=True, exist_ok=True)
        fonts = Fonts(fonts, HEADING)
        for name, render in (("hero", hero), ("find", find), ("deeper", deeper)):
            if args.only is None or args.only == name:
                for suffix, theme in THEMES.items():
                    render(shots, fonts, args.out / f"{name}{suffix}.png", theme)
        if args.only in (None, "social"):
            social(shots, fonts, args.out / "social-preview.png", THEMES[""])


if __name__ == "__main__":
    main()
