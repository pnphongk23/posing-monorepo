#!/usr/bin/env python3
"""Tone validator for the DL-B reference set (260913 parity gate).

Programmatic, no images opened by a human: for every tone-state reference, assert the
expected EXACT tone hex is present at or above a magnitude threshold; for white/empty/
loading surfaces assert no tone hex exceeds that threshold.

Tone contract (styles/tokens.css + styles/components/empty-state.css, verified in
docs/evidence/260913-parity-gate/dlb-region-checklist.md S2):
  error    #FFF4F5
  offline  #FED766   (warning shares this hex)
  warning  #FED766
  success  #B5E2B9

TRAP (checklist item 2, "Reference-side artifacts"): `--nb-color-warning-surface` and
`--nb-color-accent-yellow` are the SAME hex #FED766, so EVERY reference shows ~0.2-1%
#FED766 from the crown button / search chips even with no warning on screen. A warning
is therefore judged by MAGNITUDE, never by presence. Thresholds below are set from the
measured reference set (checklist F1: real warnings measure 5.9-15.1% of frame).

Usage:
  python3 scripts/validate-reference-states.py            # validate all
  python3 scripts/validate-reference-states.py <ref>...   # validate a subset

Exit 0 = all assertions hold; exit 1 = any mismatch (mismatches are listed, not fatal-first).
"""
import sys
from PIL import Image

REF_DIR = "docs/prototype/screenshots/reference"

# Magnitude threshold as a fraction of frame pixels, derived from the measured set:
# real tone surfaces measure 5.9%-15.1% (F1); ambient accent-yellow noise <= 0.96%.
# 3% sits cleanly between the two populations.
TONE_THRESHOLD = 0.03
# White/empty/loading surfaces: no tone hex may exceed this (noise ceiling + margin).
ABSENT_THRESHOLD = 0.02

TONE_HEX = {
    "error": (255, 244, 245),    # FFF4F5
    "offline": (254, 215, 102),  # FED766
    "warning": (254, 215, 102),  # FED766 (same hex as accent yellow — judge by magnitude)
    "success": (181, 226, 185),  # B5E2B9
}

# reference name -> (tone, expected-present) ; expected-present=False means the surface
# must NOT carry the tone above ABSENT_THRESHOLD (white/empty/loading surfaces, and the
# gallery-detail-v2 error states which use the page's own #EEE9E1 surface — finding F2).
EXPECTATIONS = {
    # error tone
    "poses-list-error": ("error", True),
    "search-error": ("error", True),
    "saved-list-error": ("error", True),
    "camera-picker-error": ("error", True),
    "pose-detail-unavailable": ("error", True),
    "pose-detail-saved-error": ("error", True),
    "gallery-detail-unavailable": ("error", True),
    "sign-in-failure": ("error", True),
    "gallery-detail-v2-missing": ("error", False),   # F2: renders #EEE9E1, 0% component tone (measured)
    "gallery-detail-v2-deleted": ("error", False),   # F2
    # offline / warning tone (#FED766)
    "camera-picker-offline": ("offline", True),
    "search-offline": ("offline", True),
    "saved-list-offline-no-cache": ("offline", True),
    "poses-list-refresh-error": ("warning", True),
    "saved-list-refresh-error": ("warning", True),
    "saved-list-offline-stale": ("warning", True),   # yellow banner, small surface
    # success tone
    "account-signed-out": ("success", True),
    "poses-list-deleted": ("success", True),
    # white/empty/loading surfaces — tone must stay below the noise ceiling
    "poses-list-empty": ("error", False),
    "poses-list-loading": ("error", False),
    "search-blank": ("error", False),
    "search-loading": ("error", False),
    "search-no-match": ("error", False),
    "saved-list-loading": ("error", False),
    "saved-list-empty": ("error", False),
    "camera-picker-loading": ("error", False),
    "camera-picker-no-match": ("error", False),
    "gallery-filter-empty": ("error", False),
    "gallery-detail-v2-loading": ("error", False),
}


def hex_fraction(path, rgb):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    target = im.tobytes()  # RGB, 3 bytes per pixel
    total = w * h
    count = 0
    for i in range(0, len(target), 3):
        if target[i] == rgb[0] and target[i + 1] == rgb[1] and target[i + 2] == rgb[2]:
            count += 1
    return count / total


def main():
    args = sys.argv[1:]
    names = args or sorted(EXPECTATIONS)
    failures = []
    for name in names:
        if name not in EXPECTATIONS:
            print(f"UNKNOWN reference: {name} (no expectation registered)")
            failures.append(name)
            continue
        tone, expected = EXPECTATIONS[name]
        rgb = TONE_HEX[tone]
        path = f"{REF_DIR}/{name}.png"
        frac = hex_fraction(path, rgb)
        pct = frac * 100
        threshold = TONE_THRESHOLD if expected else ABSENT_THRESHOLD
        ok = frac >= threshold if expected else frac < threshold
        status = "OK " if ok else "FAIL"
        want = f">= {threshold * 100:.0f}%" if expected else f"< {threshold * 100:.0f}%"
        print(f"{status} {name:32} {tone:8} {pct:6.2f}%  (want {want})")
        if not ok:
            failures.append(name)
    if failures:
        print(f"\n{len(failures)} tone mismatch(es): {', '.join(failures)}")
        sys.exit(1)
    print(f"\nAll {len(names)} tone assertions hold "
          f"(present-threshold {TONE_THRESHOLD * 100:.0f}%, absent-ceiling {ABSENT_THRESHOLD * 100:.0f}%).")


if __name__ == "__main__":
    main()
