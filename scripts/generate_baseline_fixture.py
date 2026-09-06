#!/usr/bin/env python3
"""Generate the deterministic 320 x 256 RGB test card used by T02/T22."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


WIDTH = 320
HEIGHT = 256
TOP_HEIGHT = 192
BAR_COLORS = (
    (228, 236, 248),
    (255, 216, 74),
    (47, 211, 230),
    (52, 207, 106),
    (224, 82, 198),
    (255, 74, 61),
    (47, 107, 255),
    (6, 10, 20),
)


def make_testcard() -> Image.Image:
    image = Image.new("RGB", (WIDTH, HEIGHT))
    pixels = image.load()
    bar_width = WIDTH // len(BAR_COLORS)

    for y in range(HEIGHT):
        for x in range(WIDTH):
            bar = min(x // bar_width, len(BAR_COLORS) - 1)
            red, green, blue = BAR_COLORS[bar]
            if y >= TOP_HEIGHT:
                # The lower band is deliberately asymmetric so a vertical flip
                # changes every baseline hash instead of going unnoticed.
                scale = 0.18 + 0.52 * (x / (WIDTH - 1))
                red = round(red * scale)
                green = round(green * scale)
                blue = round(blue * scale)
            pixels[x, y] = (red, green, blue)

    return image


def generate(output: Path) -> Path:
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    image = make_testcard()
    image.save(output, format="PNG", compress_level=9, optimize=False)
    with Image.open(output) as verification:
        verification.load()
        if verification.mode != "RGB" or verification.size != (WIDTH, HEIGHT):
            raise RuntimeError(
                f"unexpected fixture {verification.mode} {verification.size}"
            )
    return output


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        default=Path("Tests/Fixtures/testcard.png"),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    path = generate(args.output)
    print(f"Generated {path.resolve()} ({WIDTH} x {HEIGHT}, RGB).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
