#!/usr/bin/env python3
"""Measure parity-critical geometry in a prototype reference and a simulator screenshot.

Both images are normalised to 780x1688 px (= 390x844 pt @2x) before measuring, so numbers are
directly comparable across a 2x prototype render and a 3x simulator capture.

Usage:
  ./measure-ui-parity.py shutter <image.png> [<image.png> ...]
  ./measure-ui-parity.py dock    <image.png> [...]
  ./measure-ui-parity.py card    <image.png> [...]
  ./measure-ui-parity.py brackets <image.png> [...]

Metrics:
  shutter   bounding box of the pink shutter disc (prototype #E89CAE)
  dock      top row of the bottom dock pill + fill colour of its left item
            (white = inactive per prototype, accent blue = wrongly highlighted)
  card      bounding box of the first pose card in a results grid
  brackets  extremes of the white camera framing-guide brackets

The numbers locate a discrepancy. They are never a verdict: open the images.
"""
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow not installed. Run: python3 -m pip install pillow")

NORM = (780, 1688)


def load(path):
    im = Image.open(path).convert("RGB").resize(NORM, Image.LANCZOS)
    return im, im.load()


def is_dark(p, t=90):
    return p[0] < t and p[1] < t and p[2] < t


def is_white(p, t=215):
    return p[0] > t and p[1] > t and p[2] > t


def pink_bbox(px, w, h):
    """Shutter disc only: it lives in the bottom rail, so ignore everything above it —
    otherwise skin tones in the camera photo match the pink tolerance."""
    xs, ys = [], []
    for y in range(int(h * 0.855), h):
        for x in range(w):
            r, g, b = px[x, y]
            if abs(r - 232) < 14 and abs(g - 156) < 16 and abs(b - 174) < 16:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return min(xs), min(ys), max(xs), max(ys)


def dock_rows(px, w, h):
    """Rows belonging to the bottom dock capsule.

    The pill's borders span ~0.85 of the screen width, while a pose card's border is only ~0.45w,
    so a 0.60w threshold separates the dock from the results grid below it.
    """
    rows = []
    for y in range(int(h * 0.55), h):
        run = best = 0
        for x in range(w):
            run = run + 1 if is_dark(px[x, y]) else 0
            best = max(best, run)
        if best > int(w * 0.60):
            rows.append(y)
    return rows


def dock_top(px, w, h):
    """Topmost row of the bottom dock pill, or None."""
    rows = dock_rows(px, w, h)
    return min(rows) if rows else None


def dock_probe(px, w, h):
    rows = dock_rows(px, w, h)
    if not rows:
        return None, None, None
    top, bottom = min(rows), max(rows)
    fill = px[int(w * 0.20), min(h - 1, (top + bottom) // 2)]
    return top, bottom, fill


def card_bbox(px, w, h):
    """First pose card in a results grid, measured COLUMN-FIRST.

    Vertical border columns are the reliable signal: they are long, they exclude the phone
    frame's own left/right border (x<6 / x>774), and they immediately give the column width,
    the gutter and both screen insets. Only then are the horizontal borders searched *between*
    those columns to get the height. A row-first scan is unreliable here — the dock pill and
    the frame border are long horizontal dark runs too.

    Returns (left, top, right, bottom, gutter, right_inset_pt) or None.
    """
    y0, y1 = int(h * 0.30), int(h * 0.70)
    cols = []
    for x in range(6, w - 6):
        run = best = 0
        for y in range(y0, y1):
            run = run + 1 if is_dark(px[x, y]) else 0
            best = max(best, run)
        if best > int((y1 - y0) * 0.45):
            cols.append(x)
    if len(cols) < 2:
        return None
    groups = []
    for x in cols:
        if groups and x - groups[-1][-1] <= 4:
            groups[-1].append(x)
        else:
            groups.append([x])
    edges = [(g[0], g[-1]) for g in groups]
    left, right = edges[0][0], edges[1][1]
    gutter = (edges[2][0] - edges[1][1] - 1) if len(edges) > 2 else None
    right_inset_pt = (w - 1 - edges[3][1]) / 2 if len(edges) > 3 else None

    rows = []
    for y in range(int(h * 0.25), h):
        run = best = 0
        for x in range(left, right + 1):
            run = run + 1 if is_dark(px[x, y]) else 0
            best = max(best, run)
        if best > int((right - left) * 0.80):
            rows.append(y)
    if len(rows) < 2:
        return None
    groups_r = []
    for y in rows:
        if groups_r and y - groups_r[-1][-1] <= 4:
            groups_r[-1].append(y)
        else:
            groups_r.append([y])
    top = groups_r[0][0]
    bottom = next((g[-1] for g in groups_r[1:] if 100 < g[0] - top < 800), max(rows))
    return left, top, right, bottom, gutter, right_inset_pt


def bracket_extremes(px, w, h):
    """Camera framing-guide brackets.

    Locates the BOTTOM pair first (nothing white down there to confuse it), then looks straight
    up those two columns for the top arms. Measuring the whole frame instead would also catch
    the white close/tools buttons, which sit in the same horizontal band as the top brackets.
    """
    band_y0, band_y1 = int(h * 0.68), int(h * 0.85)
    xs = []
    for y in range(band_y0, band_y1):
        for x in range(int(w * 0.08), int(w * 0.92)):
            if is_white(px[x, y]):
                xs.append(x)
    if len(xs) < 20:
        return None
    xs.sort()
    left, right = xs[0], xs[-1]

    def topmost_in_columns(cx0, cx1):
        # Start below the status bar: its time/battery glyphs are white as well and would be
        # reported as the "top bracket".
        for y in range(int(h * 0.075), band_y1):
            for x in range(max(0, cx0), min(w, cx1)):
                if is_white(px[x, y]):
                    return y
        return None

    y_top_left = topmost_in_columns(left, left + 60)
    y_top_right = topmost_in_columns(right - 60, right)
    y_top = min([v for v in (y_top_left, y_top_right) if v is not None] or [None]) \
        if (y_top_left or y_top_right) else None
    return left, right, y_top, max(y for y in range(band_y0, band_y1)
                                   if any(is_white(px[x, y]) for x in (left, right)))


def report(metric, path):
    im, px = load(path)
    w, h = im.size
    tag = path.split("/")[-1]
    if metric == "shutter":
        bb = pink_bbox(px, w, h)
        if not bb:
            print(f"shutter   {tag:34} NOT FOUND (no pink disc)")
            return
        print(f"shutter   {tag:34} bbox={bb}  size={bb[2]-bb[0]+1}x{bb[3]-bb[1]+1}px "
              f"({(bb[2]-bb[0]+1)/2:.1f}x{(bb[3]-bb[1]+1)/2:.1f}pt)  centre=({(bb[0]+bb[2])//2},{(bb[1]+bb[3])//2})")
    elif metric == "dock":
        top, bottom, fill = dock_probe(px, w, h)
        if top is None:
            print(f"dock      {tag:34} NOT FOUND (no dock pill above the bottom margin)")
            return
        print(f"dock      {tag:34} pill rows {top}..{bottom}  height={bottom-top+1}px "
              f"= {(bottom-top+1)/2:.1f}pt  gap below={h-bottom}px ({(h-bottom)/2:.1f}pt)  "
              f"left-item fill={fill}")
    elif metric == "card":
        bb = card_bbox(px, w, h)
        if not bb:
            print(f"card      {tag:34} NOT FOUND (is the grid populated?)")
            return
        left, top, right, bottom, gutter, right_inset = bb
        ww, hh = right - left + 1, bottom - top + 1
        g = f"{gutter/2:.1f}pt" if gutter else "n/a"
        ri = f"{right_inset:.1f}pt" if right_inset is not None else "n/a"
        print(f"card      {tag:34} {ww/2:.1f}x{hh/2:.1f}pt  h/w={hh/ww:.2f}  "
              f"left inset {left/2:.1f}pt  gutter {g}  right inset {ri}")
    elif metric == "brackets":
        bb = bracket_extremes(px, w, h)
        if not bb:
            print(f"brackets  {tag:34} NOT FOUND")
            return
        print(f"brackets  {tag:34} x {bb[0]}..{bb[1]} (insets {bb[0]/w*100:.1f}% / {(w-bb[1])/w*100:.1f}%)  "
              f"y {bb[2]}..{bb[3]}  box {bb[1]-bb[0]}x{bb[3]-bb[2]}px")
    else:
        sys.exit(f"unknown metric: {metric}")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    metric = sys.argv[1]
    for path in sys.argv[2:]:
        report(metric, path)


if __name__ == "__main__":
    main()
