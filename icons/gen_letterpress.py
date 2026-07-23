#!/usr/bin/env python3
"""Generate editor empty-state letterpress SVGs from the brand logo."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

THEMES = {
    "letterpress-light.svg": {
        "fill": "#B2B2B2",
        "opacity": "0.1",
        "gid": "kianggo_grey_light_letterpress",
    },
    "letterpress-dark.svg": {
        "fill": "#B2B2B2",
        "opacity": "0.3",
        "gid": "kianggo_grey_dark_letterpress",
    },
    "letterpress-hcLight.svg": {
        "fill": "#B2B2B2",
        "opacity": None,
        "gid": "kianggo_grey_hc_light_letterpress",
    },
    "letterpress-hcDark.svg": {
        "fill": "#3C3C3C",
        "opacity": None,
        "gid": "kianggo_grey_hc_dark_letterpress",
    },
}


def render(source: str, fill: str, gid: str, opacity: str | None) -> str:
    out = source
    out = re.sub(r'fill="#020403"', f'fill="{fill}"', out)
    out = out.replace('width="100" height="100"', 'width="40" height="40"')
    out = out.replace('id="kianggo"', 'id="logo"')
    attrs = f'id="{gid}"'
    if opacity:
        attrs += f' opacity="{opacity}"'
    out = out.replace('id="Layer_1"', attrs, 1)
    return out


def generate(quality: str) -> list[Path]:
    src = ROOT / "icons" / quality / "codium_cnl.svg"
    if not src.is_file():
        raise FileNotFoundError(src)

    source = src.read_text(encoding="utf-8")
    out_dir = (
        ROOT
        / "src"
        / quality
        / "src"
        / "vs"
        / "workbench"
        / "browser"
        / "parts"
        / "editor"
        / "media"
    )
    out_dir.mkdir(parents=True, exist_ok=True)

    written: list[Path] = []
    for name, cfg in THEMES.items():
        path = out_dir / name
        path.write_text(
            render(source, cfg["fill"], cfg["gid"], cfg["opacity"]),
            encoding="utf-8",
        )
        written.append(path)
    return written


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-i",
        "--insider",
        action="store_true",
        help="Generate for insider quality",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Generate for both stable and insider",
    )
    args = parser.parse_args()

    qualities = ["stable", "insider"] if args.all else ["insider" if args.insider else "stable"]
    for quality in qualities:
        for path in generate(quality):
            print(f"wrote {path} ({path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
