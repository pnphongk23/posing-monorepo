#!/usr/bin/env bash
# Builds a side-by-side prototype-vs-simulator comparison image and prints a diff metric.
#
# Usage: scripts/compare-prototype-screenshot.sh <reference.png> <actual.png> <out.png> [label-ref] [label-actual]
#
# The HTML prototype reference is 780x1688 (390x844 @2x); simulator screenshots from an
# iPhone 13 are 1170x2532 (390x844 @3x). Both are normalised to 600pt-wide panes so the
# panes are the same logical size and differences are meaningful.
set -euo pipefail

REF="${1:?reference png required}"
ACT="${2:?actual png required}"
OUT="${3:?output png required}"
LREF="${4:-PROTOTYPE}"
LACT="${5:-SIMULATOR}"

if [[ ! -f "$REF" ]]; then echo "missing reference: $REF" >&2; exit 2; fi
if [[ ! -f "$ACT" ]]; then echo "missing actual: $ACT" >&2; exit 2; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ImageMagick on macOS often has no default font configured; pick one that exists.
FONT_ARGS=()
for f in /System/Library/Fonts/Supplemental/Arial.ttf /System/Library/Fonts/Helvetica.ttc /System/Library/Fonts/SFNS.ttf; do
  if [[ -f "$f" ]]; then FONT_ARGS=(-font "$f"); break; fi
done

# Normalise both to the same logical size (390x844 pt) at 2x = 780x1688.
magick "$REF" -resize 780x1688! -bordercolor black -border 2 "$TMP/ref.png"
magick "$ACT" -resize 780x1688! -bordercolor black -border 2 "$TMP/act.png"

# Absolute-error metric on the normalised panes (0 = identical, 65535 = maximally different).
AE="$(magick compare -metric AE "$TMP/ref.png" "$TMP/act.png" null: 2>&1 || true)"
RMSE="$(magick compare -metric RMSE "$TMP/ref.png" "$TMP/act.png" null: 2>&1 || true)"
TOTAL=$(( 784 * 1692 ))

magick "$TMP/ref.png" "$TMP/act.png" +append "$TMP/pair.png"
magick "${FONT_ARGS[@]}" "$TMP/pair.png" \
  -background '#222222' -gravity north -splice 0x44 -fill white -pointsize 26 \
  -annotate +0+10 "LEFT: $LREF   |   RIGHT: $LACT" \
  "$OUT"

echo "comparison -> $OUT"
echo "AE (differing pixels @780x1688): $AE / $TOTAL"
echo "RMSE (normalised 0..1): $RMSE"
echo
echo "REMINDER: a numeric metric is only a hint. Open the image and verify each region:"
echo "  size/position of buttons, border thickness, shadow offset+hardness, radii,"
echo "  colours, spacing, grid column count, dock presence, text weight/case."
