#!/usr/bin/env python3
"""Compose a replaceable SVG/PNG logo inside the three static Astral forms.

Examples:
  python3 scripts/compose-astral-logo.py
  python3 scripts/compose-astral-logo.py --logo /path/to/company.svg --name company
The generated SVGs are standalone and embed both the mascot PNG and logo.
"""
import argparse
import base64
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
KIT = ROOT / "design/mascot/astral-v2/morph-kit"


def data_url(data, mime):
    return f"data:{mime};base64," + base64.b64encode(data).decode("ascii")


def logo_url(path):
    data = path.read_bytes()
    if path.suffix.lower() == ".svg":
        node = ET.fromstring(data)
        if node.tag.split("}")[-1] != "svg":
            raise ValueError("Expected an SVG root")
        # Match the approved monochrome OpenAI version on dark glass.
        text = data.decode("utf-8").replace("currentColor", "#f4f7fb")
        return data_url(text.encode("utf-8"), "image/svg+xml")
    if path.suffix.lower() == ".png" and data.startswith(b"\x89PNG\r\n\x1a\n"):
        return data_url(data, "image/png")
    raise ValueError("Use a transparent SVG or PNG logo")


def compose(shape, config, logo, name, output):
    body = data_url((KIT / config["exports"]["480"]).read_bytes(), "image/png")
    placement = config["logo"]
    cx, cy = placement["x"] * 240, placement["y"] * 240
    w, h = placement["width"] * 240, placement["height"] * 240
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240" width="240" height="240">
<title>Astral {shape} · {name}</title>
<image width="240" height="240" href="{body}"/>
<image x="{cx-w/2:g}" y="{cy-h/2:g}" width="{w:g}" height="{h:g}" preserveAspectRatio="xMidYMid meet" opacity=".93" href="{logo}"/>
<defs><linearGradient id="glass-wash" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#cdeaff" stop-opacity=".16"/><stop offset=".55" stop-color="#bacdff" stop-opacity="0"/><stop offset="1" stop-color="#edf7ff" stop-opacity=".08"/></linearGradient></defs>
<ellipse cx="{cx:g}" cy="{cy:g}" rx="{w*.61:g}" ry="{h*.64:g}" fill="url(#glass-wash)"/>
</svg>
'''
    path = output / f"astral-{shape}-{name}.svg"
    path.write_text(svg, encoding="utf-8")
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--logo", type=Path, help="Company / agent SVG or PNG")
    parser.add_argument("--name", default="company", help="Lowercase output identifier")
    parser.add_argument("--output", type=Path, default=KIT / "examples")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", args.name):
        parser.error("--name must contain lowercase Latin letters, digits and hyphens")
    plan = json.loads((KIT / "animation-blueprint.json").read_text())
    providers = {args.name: args.logo} if args.logo else {
        name: KIT / "logos" / f"{name}.svg" for name in ("openai", "claude", "gemini")}
    args.output.mkdir(parents=True, exist_ok=True)
    count = 0
    for name, logo in providers.items():
        encoded = logo_url(logo)
        for shape, config in plan["forms"].items():
            compose(shape, config, encoded, name, args.output)
            count += 1
    print(f"Saved {count} standalone SVG compositions to {args.output}")


if __name__ == "__main__":
    main()
