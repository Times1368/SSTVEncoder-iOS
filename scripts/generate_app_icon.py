#!/usr/bin/env python3
"""Generate the app's Xcode asset catalog from a 1024 px source or placeholder."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Iterable, Sequence

from PIL import Image, ImageDraw, UnidentifiedImageError


ICON_SIZE = 1024
ICON_FILENAME = "AppIcon-1024.png"
REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = (
    REPOSITORY_ROOT
    / "SSTVEncoder"
    / "Resources"
    / "AppIconSource"
    / ICON_FILENAME
)
DEFAULT_OUTPUT = (
    REPOSITORY_ROOT
    / "SSTVEncoder"
    / "Resources"
    / "Generated"
    / "Assets.xcassets"
)


def _placeholder_icon() -> Image.Image:
    """Draw a deterministic opaque icon without embedding a binary asset."""

    image = Image.new("RGB", (ICON_SIZE, ICON_SIZE), (13, 29, 64))
    draw = ImageDraw.Draw(image)

    top = (31, 111, 235)
    bottom = (74, 25, 140)
    for y in range(ICON_SIZE):
        fraction = y / (ICON_SIZE - 1)
        color = tuple(
            round(start + (end - start) * fraction)
            for start, end in zip(top, bottom)
        )
        draw.line((0, y, ICON_SIZE, y), fill=color)

    card = (148, 148, 876, 876)
    draw.rounded_rectangle(card, radius=176, fill=(10, 22, 49), outline=(167, 214, 255), width=18)

    for offset, width, color in (
        (0, 44, (15, 39, 83)),
        (0, 27, (89, 211, 255)),
        (0, 11, (245, 252, 255)),
    ):
        points: list[tuple[float, float]] = []
        for x in range(226, 799, 4):
            phase = (x - 226) / 572 * math.tau * 3
            envelope = 0.72 + 0.28 * math.cos((x - 512) / 286 * math.pi)
            y = 512 + math.sin(phase) * 142 * envelope + offset
            points.append((x, y))
        draw.line(points, fill=color, width=width, joint="curve")

    for x in (216, 808):
        draw.ellipse((x - 30, 482, x + 30, 542), fill=(245, 252, 255))

    return image


def _load_source(source: Path) -> Image.Image:
    if not source.is_file():
        raise FileNotFoundError(f"AppIcon source does not exist: {source}")

    with Image.open(source) as candidate:
        candidate.load()
        if candidate.size != (ICON_SIZE, ICON_SIZE):
            raise ValueError(
                f"AppIcon source must be exactly {ICON_SIZE} x {ICON_SIZE} pixels; "
                f"found {candidate.width} x {candidate.height}"
            )
        return candidate.convert("RGB")


def generate_asset_catalog(*, source: Path | None, output: Path) -> Path:
    """Write an opaque single-size iOS AppIcon catalog and return its PNG path."""

    icon = _load_source(Path(source)) if source is not None else _placeholder_icon()
    output = Path(output)
    app_icon_set = output / "AppIcon.appiconset"
    app_icon_set.mkdir(parents=True, exist_ok=True)

    (output / "Contents.json").write_text(
        json.dumps(
            {"info": {"author": "xcode", "version": 1}},
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )
    (app_icon_set / "Contents.json").write_text(
        json.dumps(
            {
                "images": [
                    {
                        "filename": ICON_FILENAME,
                        "idiom": "universal",
                        "platform": "ios",
                        "size": "1024x1024",
                    }
                ],
                "info": {"author": "xcode", "version": 1},
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )

    icon_path = app_icon_set / ICON_FILENAME
    icon.save(icon_path, format="PNG", compress_level=9)
    return icon_path


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        help="optional opaque or transparent PNG, exactly 1024 x 1024 pixels",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help="generated Assets.xcassets directory",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    source = args.source
    if source is None and DEFAULT_SOURCE.is_file():
        source = DEFAULT_SOURCE
    try:
        icon_path = generate_asset_catalog(source=source, output=args.output)
    except (OSError, ValueError, UnidentifiedImageError) as exc:
        print(f"AppIcon generation failed: {exc}", file=sys.stderr)
        return 1

    origin = str(source) if source is not None else "deterministic placeholder"
    print(f"Generated {icon_path.resolve()} from {origin}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
