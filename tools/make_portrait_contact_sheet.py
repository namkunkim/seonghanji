#!/usr/bin/env python3
"""Build deterministic P0-04 comparison sheets from FLUX/SDXL PNG masters."""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def font(size: int):
    for path in ("C:/Windows/Fonts/malgun.ttf", "C:/Windows/Fonts/arial.ttf"):
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root", type=Path, help="directory containing flux/ and sdxl/")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--thumb-width", type=int, default=320)
    args = ap.parse_args()

    arts = [f"ART-C{i}" for i in range(901, 912)]
    tw, th = args.thumb_width, args.thumb_width * 5 // 4
    label_h, header_h, gap = 34, 54, 12
    sheet_w = gap * 3 + tw * 2
    sheet_h = header_h + len(arts) * (th + label_h + gap) + gap
    title_font, label_font = font(24), font(18)

    def build(grayscale: bool, filename: str):
        sheet = Image.new("RGB", (sheet_w, sheet_h), "#17191d")
        draw = ImageDraw.Draw(sheet)
        draw.text((gap + tw // 2, 12), "FLUX.1 schnell", font=title_font,
                  anchor="ma", fill="white")
        draw.text((gap * 2 + tw + tw // 2, 12), "SDXL 1.0", font=title_font,
                  anchor="ma", fill="white")
        for row, art in enumerate(arts):
            y = header_h + row * (th + label_h + gap)
            for col, model in enumerate(("flux", "sdxl")):
                x = gap + col * (tw + gap)
                src = args.root / model / f"{art}.png"
                image = Image.open(src).convert("RGB").resize((tw, th), Image.Resampling.LANCZOS)
                if grayscale:
                    image = image.convert("L").convert("RGB")
                sheet.paste(image, (x, y))
                draw.text((x + tw // 2, y + th + 5), art, font=label_font,
                          anchor="ma", fill="#e8e8e8")
        args.out.mkdir(parents=True, exist_ok=True)
        sheet.save(args.out / filename, format="PNG", optimize=True)

    build(False, "contact-sheet-320.png")
    build(True, "contact-sheet-320-grayscale.png")


if __name__ == "__main__":
    main()
