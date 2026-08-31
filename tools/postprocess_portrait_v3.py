#!/usr/bin/env python3
"""Deterministic P0-04 v3 background tint and vignette pass."""

import argparse
import hashlib
import json
import math
from collections import deque
from pathlib import Path

from PIL import Image

TINTS = {"ART-C903": "#2E3A4C", "ART-C906": "#3B352B", "ART-C910": "#43262A"}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rgb(hex_color: str):
    return tuple(int(hex_color[i:i + 2], 16) for i in (1, 3, 5))


def background_mask(image: Image.Image, tolerance: int = 54):
    """Flood-fill edge-connected pixels similar to the neutral corner samples."""
    im = image.convert("RGB")
    w, h = im.size
    px = im.load()
    samples = [px[x, y] for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1))]
    ref = tuple(sorted(c[i] for c in samples)[len(samples) // 2] for i in range(3))
    limit = tolerance * tolerance
    seen = bytearray(w * h)
    queue = deque()
    for x in range(w):
        queue.append((x, 0)); queue.append((x, h - 1))
    for y in range(h):
        queue.append((0, y)); queue.append((w - 1, y))
    while queue:
        x, y = queue.popleft()
        pos = y * w + x
        if seen[pos]:
            continue
        p = px[x, y]
        if sum((p[i] - ref[i]) ** 2 for i in range(3)) > limit:
            continue
        seen[pos] = 1
        if x: queue.append((x - 1, y))
        if x + 1 < w: queue.append((x + 1, y))
        if y: queue.append((x, y - 1))
        if y + 1 < h: queue.append((x, y + 1))
    return seen


def process(src: Path, dst: Path, tint_hex: str):
    im = Image.open(src).convert("RGB")
    if im.size != (896, 1120):
        raise ValueError(f"{src}: expected 896x1120, got {im.size}")
    mask = background_mask(im)
    px = im.load(); target = rgb(tint_hex); w, h = im.size
    cx, cy = (w - 1) / 2, (h - 1) / 2
    max_r = math.hypot(cx, cy)
    for y in range(h):
        for x in range(w):
            if not mask[y * w + x]:
                continue
            old = px[x, y]
            lum = max(0.72, min(1.18, sum(old) / (3 * 64)))
            edge = math.hypot(x - cx, y - cy) / max_r
            vignette = 1.0 - 0.18 * max(0.0, min(1.0, edge ** 1.7))
            px[x, y] = tuple(max(0, min(255, round(c * lum * vignette))) for c in target)
    dst.parent.mkdir(parents=True, exist_ok=True)
    im.save(dst, "PNG", optimize=True)
    return sum(mask) / (w * h)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw_root", type=Path, help="directory containing flux/ and sdxl/")
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()
    rows = []
    for model in ("flux", "sdxl"):
        for art, tint in TINTS.items():
            src = args.raw_root / model / f"{art}.png"
            dst = args.out / model / f"{art}.png"
            ratio = process(src, dst, tint)
            rows.append({"art": art, "model": model, "source": str(src), "source_sha256": sha256(src),
                         "out": str(dst), "sha256": sha256(dst), "tint": tint,
                         "background_mask_ratio": round(ratio, 6), "postprocess": "edge-flood tint + radial -18% vignette"})
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "postprocess-manifest.jsonl").write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")


if __name__ == "__main__":
    main()
