#!/usr/bin/env python3
"""
remove_bg_lineart.py

Remove a white / near-white background from line-art images and export
a PNG with a real alpha channel.

Typical use:
    python remove_bg_lineart.py input.png -o output.png

Batch folder:
    python remove_bg_lineart.py ./input_folder -o ./output_folder

Stronger lines:
    python remove_bg_lineart.py input.png -o output.png --strength 1.6

Requirements:
    pip install pillow numpy
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path
import sys

import numpy as np
from PIL import Image

SUPPORTED_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff"}


def remove_white_background(
    src: Path,
    dst: Path,
    threshold: int = 245,
    softness: int = 24,
    strength: float = 1.0,
    preserve_color: bool = True,  # deprecated compatibility parameter; ignored
) -> None:
    """Remove near-white pixels, preserving visible RGB and line strength.

    Alpha is foreground confidence: the tolerance band from
    ``threshold - softness`` through ``threshold`` maps linearly from opaque
    to transparent. Source alpha is applied once (never multiplied by a
    second darkness term), preserving anti-aliased strokes. ``preserve_color``
    is deprecated and ignored; RGB is always preserved.
    """
    img = Image.open(src).convert("RGBA")
    arr = np.asarray(img).astype(np.float32)

    rgb = arr[..., :3]
    original_alpha = arr[..., 3] / 255.0

    # Perceived brightness (0 = black, 255 = white)
    luminance = (
        0.2126 * rgb[..., 0]
        + 0.7152 * rgb[..., 1]
        + 0.0722 * rgb[..., 2]
    )

    if softness > 0:
        # Do not multiply by darkness as well: that double-attenuates faint
        # anti-aliased strokes and was the cause of the nearly empty output.
        alpha = np.clip((threshold - luminance) / float(softness), 0.0, 1.0)
    else:
        alpha = (luminance < threshold).astype(np.float32)
    alpha = np.clip(alpha * strength * original_alpha, 0.0, 1.0)
    alpha[alpha < (2.0 / 255.0)] = 0.0

    alpha8 = np.round(alpha * 255.0).astype(np.uint8)
    strong = alpha8 >= 160
    strong_pixels = int(np.count_nonzero(strong))
    max_alpha = int(alpha8.max())

    # Quality gate: 0.0005% of pixels is the minimum area-aware coverage,
    # with an absolute floor of 8. Noise pixels must also form one connected
    # (8-neighbor) ink component of at least 8 pixels whose bbox spans 5px.
    # This accepts sparse but continuous pose strokes while rejecting eight
    # scattered dark pixels in a 1MP image. max_alpha protects against faint
    # technically-valid output. Thresholds are absolute because source pose
    # images are commonly 1024px and legitimate strokes remain continuous.
    area = alpha8.shape[0] * alpha8.shape[1]
    min_strong_pixels = max(8, int(np.ceil(area * 0.000005)))
    visited = np.zeros_like(strong, dtype=bool)
    largest_component = 0
    largest_span = 0
    height, width = strong.shape
    for y, x in zip(*np.nonzero(strong)):
        if visited[y, x]:
            continue
        queue = deque([(int(y), int(x))])
        visited[y, x] = True
        count = 0
        min_y = max_y = int(y)
        min_x = max_x = int(x)
        while queue:
            cy, cx = queue.popleft()
            count += 1
            min_y, max_y = min(min_y, cy), max(max_y, cy)
            min_x, max_x = min(min_x, cx), max(max_x, cx)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = cy + dy, cx + dx
                    if (0 <= ny < height and 0 <= nx < width
                            and not visited[ny, nx] and strong[ny, nx]):
                        visited[ny, nx] = True
                        queue.append((ny, nx))
        largest_component = max(largest_component, count)
        largest_span = max(largest_span, max(max_y - min_y, max_x - min_x) + 1)

    min_span = max(5, int(np.ceil(np.sqrt(area) * 0.005)))
    if (strong_pixels < min_strong_pixels or max_alpha < 192
            or largest_component < 8 or largest_span < min_span):
        raise ValueError(
            "line-art quality gate failed: output contains no meaningful ink "
            f"(strong_pixels={strong_pixels}, min_strong_pixels={min_strong_pixels}, "
            f"largest_component={largest_component}, largest_span={largest_span}, "
            f"min_span={min_span}, max_alpha={max_alpha})"
        )

    # Always retain source RGB; transparent-pixel RGB is harmless and keeps
    # visible anti-aliased colors lossless.
    out = np.zeros_like(arr, dtype=np.uint8)
    out[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    out[..., 3] = alpha8

    dst.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(out, "RGBA").save(dst, "PNG")


def process_path(
    input_path: Path,
    output_path: Path | None,
    threshold: int,
    softness: int,
    strength: float,
    preserve_color: bool,  # deprecated compatibility parameter; ignored
) -> None:
    if input_path.is_file():
        if input_path.suffix.lower() not in SUPPORTED_EXTS:
            raise ValueError(f"Unsupported image format: {input_path.suffix}")

        if output_path is None:
            output_path = input_path.with_name(f"{input_path.stem}_transparent.png")
        elif output_path.suffix.lower() != ".png":
            output_path = output_path.with_suffix(".png")

        remove_white_background(
            input_path,
            output_path,
            threshold=threshold,
            softness=softness,
            strength=strength,
            preserve_color=preserve_color,
        )
        print(f"OK: {input_path} -> {output_path}")
        return

    if input_path.is_dir():
        if output_path is None:
            output_path = input_path.with_name(f"{input_path.name}_transparent")

        output_path.mkdir(parents=True, exist_ok=True)

        files = [
            p for p in input_path.rglob("*")
            if p.is_file() and p.suffix.lower() in SUPPORTED_EXTS
        ]

        if not files:
            print("No supported images found.", file=sys.stderr)
            return

        for src in files:
            relative = src.relative_to(input_path)
            dst = output_path / relative
            dst = dst.with_suffix(".png")

            remove_white_background(
                src,
                dst,
                threshold=threshold,
                softness=softness,
                strength=strength,
                preserve_color=preserve_color,
            )
            print(f"OK: {src} -> {dst}")

        print(f"\nProcessed {len(files)} image(s).")
        return

    raise FileNotFoundError(f"Input not found: {input_path}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Remove white background from line-art and export real transparent PNG."
    )
    parser.add_argument(
        "input",
        type=Path,
        help="Input image or folder"
    )
    parser.add_argument(
        "-o", "--output",
        type=Path,
        default=None,
        help="Output PNG or output folder"
    )
    parser.add_argument(
        "--threshold",
        type=int,
        default=245,
        help="White cutoff 0-255. Lower removes more near-white pixels. Default: 245"
    )
    parser.add_argument(
        "--softness",
        type=int,
        default=24,
        help="Soft transition width near the white cutoff. Default: 24"
    )
    parser.add_argument(
        "--strength",
        type=float,
        default=1.0,
        help="Line opacity multiplier. Example: 1.5 for stronger strokes. Default: 1.0"
    )
    parser.add_argument(
        "--preserve-color",
        action="store_true",
        help="Retained for compatibility; source RGB is always preserved"
    )
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    if not 0 <= args.threshold <= 255:
        parser.error("--threshold must be between 0 and 255")

    if not 0 <= args.softness <= 255:
        parser.error("--softness must be between 0 and 255")

    if args.strength <= 0:
        parser.error("--strength must be greater than 0")

    try:
        process_path(
            args.input,
            args.output,
            threshold=args.threshold,
            softness=args.softness,
            strength=args.strength,
            preserve_color=True,
        )
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
