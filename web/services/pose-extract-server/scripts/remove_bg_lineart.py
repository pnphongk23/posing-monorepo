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
from pathlib import Path
import sys

import numpy as np
from PIL import Image

SUPPORTED_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff"}


def remove_white_background(
    src: Path,
    dst: Path,
    threshold: int = 250,
    softness: int = 24,
    strength: float = 1.0,
    preserve_color: bool = False,
) -> None:
    """
    Convert white / near-white pixels to transparency.

    For line-art, the default output color is black and the original line
    intensity is represented by alpha. This avoids white halos around
    anti-aliased strokes.

    Args:
        src: input image path
        dst: output PNG path
        threshold: pixels brighter than this are treated as background
        softness: width of the fade zone below threshold
        strength: multiplier for stroke opacity
        preserve_color: keep original RGB instead of forcing line color to black
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

    # Background mask with a soft transition.
    # threshold=250, softness=24 means:
    # >= 250       => fully transparent
    # <= 226       => line opacity based on darkness
    # between them => smoothly faded
    soft_start = max(0, threshold - softness)

    # Base alpha from "ink darkness".
    # This reconstructs anti-aliased gray strokes cleanly on any background.
    ink_alpha = (255.0 - luminance) / 255.0

    if softness > 0:
        fade = (threshold - luminance) / float(softness)
        fade = np.clip(fade, 0.0, 1.0)
    else:
        fade = (luminance < threshold).astype(np.float32)

    alpha = ink_alpha * fade * strength * original_alpha
    alpha = np.clip(alpha, 0.0, 1.0)

    # Kill tiny background noise.
    alpha[alpha < (2.0 / 255.0)] = 0.0

    out = np.zeros_like(arr, dtype=np.uint8)

    if preserve_color:
        out[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    else:
        # Black RGB + alpha gives the cleanest line-art result
        # and prevents white fringes around strokes.
        out[..., :3] = 0

    out[..., 3] = np.round(alpha * 255.0).astype(np.uint8)

    dst.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(out, "RGBA").save(dst, "PNG")


def process_path(
    input_path: Path,
    output_path: Path | None,
    threshold: int,
    softness: int,
    strength: float,
    preserve_color: bool,
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
        default=250,
        help="White cutoff 0-255. Lower removes more near-white pixels. Default: 250"
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
        help="Keep original RGB colors instead of converting strokes to black"
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
            preserve_color=args.preserve_color,
        )
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
