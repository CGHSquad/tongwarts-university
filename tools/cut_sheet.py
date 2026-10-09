#!/usr/bin/env python3
"""
cut_sheet.py - cut a UI asset sheet drawn on flat magenta (#FF00FF) into
separate transparent PNGs.

Usage:
  python3 cut_sheet.py SHEET.png OUT_DIR [--prefix combat] [--names names.txt]
                       [--grow 25] [--min-size 48] [--pad 6]
                       [--lo 70] [--hi 150] [--key FF00FF]

What it does:
  1. Keys out the magenta background with a soft edge and removes magenta
     fringing (despill) so edges don't look pink.
  2. Finds each separate part. Pieces closer together than --grow pixels are
     treated as ONE part (keeps glows and small pieces together).
  3. Saves each part as a cropped transparent PNG, in reading order
     (left to right, top to bottom): PREFIX_01.png, PREFIX_02.png, ...
     If --names is given (one name per line, same order as the sheet), files
     are named from that list instead.
  4. Writes OUT_DIR/_preview.png: the sheet with each part's number on it,
     so you can match numbers to names before renaming.

Requires: numpy, pillow, scipy.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi


def parse_key(hexstr):
    hexstr = hexstr.lstrip("#")
    return np.array([int(hexstr[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)


def key_out(rgb, key, lo, hi):
    """Return (rgba uint8, alpha float) with soft magenta removal + despill."""
    f = rgb.astype(np.float32)
    dist = np.sqrt(((f - key) ** 2).sum(axis=2))
    alpha = np.clip((dist - lo) / max(hi - lo, 1e-3), 0.0, 1.0)
    a3 = alpha[..., None]
    # Remove the key colour's contribution from partly transparent pixels.
    safe = np.maximum(a3, 1e-3)
    clean = (f - (1.0 - a3) * key) / safe
    clean = np.where(a3 > 0.02, clean, 0.0)
    clean = np.clip(clean, 0, 255)
    out = np.dstack([clean, alpha * 255.0]).astype(np.uint8)
    return out, alpha


def reading_order(boxes):
    """Sort boxes (y0, x0, y1, x1) into rows, then left to right."""
    idx = sorted(range(len(boxes)), key=lambda i: (boxes[i][0] + boxes[i][2]) / 2)
    rows, row_cy, row_h = [], [], []
    for i in idx:
        y0, x0, y1, x1 = boxes[i]
        cy, h = (y0 + y1) / 2, (y1 - y0)
        if rows and abs(cy - row_cy[-1]) <= 0.6 * max(row_h[-1], h):
            rows[-1].append(i)
            n = len(rows[-1])
            row_cy[-1] = (row_cy[-1] * (n - 1) + cy) / n
            row_h[-1] = max(row_h[-1], h)
        else:
            rows.append([i])
            row_cy.append(cy)
            row_h.append(h)
    order = []
    for r in rows:
        order.extend(sorted(r, key=lambda i: (boxes[i][1] + boxes[i][3]) / 2))
    return order


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sheet")
    ap.add_argument("out_dir")
    ap.add_argument("--prefix", default="part")
    ap.add_argument("--names", help="text file, one output name per line, in sheet reading order")
    ap.add_argument("--grow", type=int, default=25, help="merge pieces closer than this many px (default 25)")
    ap.add_argument("--min-size", type=int, default=48, help="ignore specks smaller than this (px, default 48)")
    ap.add_argument("--pad", type=int, default=6, help="transparent padding around each part (default 6)")
    ap.add_argument("--lo", type=float, default=70, help="colour distance fully transparent below this")
    ap.add_argument("--hi", type=float, default=150, help="colour distance fully opaque above this")
    ap.add_argument("--key", default="FF00FF", help="background colour hex (default FF00FF)")
    args = ap.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    img = Image.open(args.sheet).convert("RGB")
    rgb = np.array(img)
    rgba, alpha = key_out(rgb, parse_key(args.key), args.lo, args.hi)

    solid = alpha > 0.5
    solid = ndi.binary_opening(solid, iterations=1)  # drop single-pixel noise
    r = max(args.grow, 1)
    grown = ndi.binary_dilation(solid, structure=np.ones((3, 3), bool), iterations=r)
    labels, n = ndi.label(grown)
    slices = ndi.find_objects(labels)

    boxes, keep = [], []
    H, W = alpha.shape
    for lab, sl in enumerate(slices, start=1):
        if sl is None:
            continue
        # Bounding box of the real (un-grown) pixels inside this component.
        comp = solid[sl] & (labels[sl] == lab)
        if not comp.any():
            continue
        ys, xs = np.where(comp)
        y0, y1 = ys.min() + sl[0].start, ys.max() + sl[0].start + 1
        x0, x1 = xs.min() + sl[1].start, xs.max() + sl[1].start + 1
        if (y1 - y0) < args.min_size and (x1 - x0) < args.min_size:
            continue
        boxes.append((y0, x0, y1, x1))
        keep.append(lab)

    if not boxes:
        sys.exit("No parts found. Check that the background is flat magenta, or lower --min-size / --lo.")

    order = reading_order(boxes)
    names = None
    if args.names:
        with open(args.names) as fh:
            names = [ln.strip() for ln in fh if ln.strip()]
        if len(names) != len(order):
            print(f"WARNING: {len(names)} names for {len(order)} parts found. "
                  f"Extra parts use '{args.prefix}_NN'; extra names are ignored.")

    preview = img.copy()
    draw = ImageDraw.Draw(preview)
    for rank, i in enumerate(order, start=1):
        y0, x0, y1, x1 = boxes[i]
        lab = keep[i]
        pad = args.pad
        cy0, cx0 = max(y0 - pad, 0), max(x0 - pad, 0)
        cy1, cx1 = min(y1 + pad, H), min(x1 + pad, W)
        crop = rgba[cy0:cy1, cx0:cx1].copy()
        # Blank anything that belongs to a different part (neighbour overlap).
        other = (labels[cy0:cy1, cx0:cx1] != lab) & (labels[cy0:cy1, cx0:cx1] != 0)
        crop[other] = 0
        name = names[rank - 1] if names and rank - 1 < len(names) else f"{args.prefix}_{rank:02d}"
        Image.fromarray(crop, "RGBA").save(os.path.join(args.out_dir, f"{name}.png"))
        draw.rectangle([x0, y0, x1, y1], outline=(0, 255, 0), width=3)
        draw.rectangle([x0, y0, x0 + 46, y0 + 26], fill=(0, 0, 0))
        draw.text((x0 + 6, y0 + 6), f"{rank:02d}", fill=(255, 255, 0))
    preview.save(os.path.join(args.out_dir, "_preview.png"))
    print(f"Saved {len(order)} parts to {args.out_dir} (see _preview.png for the numbering).")


if __name__ == "__main__":
    main()
