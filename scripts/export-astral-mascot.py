#!/usr/bin/env python3
"""Export the approved idle mascot without regenerating its artwork.

Requires macOS sips. Run from any working directory:
  python3 scripts/export-astral-mascot.py
  python3 scripts/export-astral-mascot.py --check
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import zlib

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "design/mascot/astral-v2"
MASTER = ASSETS / "astral-idle-master.png"
NORMALIZED = ASSETS / "astral-idle-normalized.png"
MANIFEST = ASSETS / "sizes.json"
SCALES = (1, 1.5, 2, 3, 4)
# Square crop around the approved silhouette. No paint, colour or alpha edits.
CROP = {"x": 119, "y": 133, "width": 1016, "height": 1016}
GROUPS = [
    {"surface": "macOS: mini agents, notch, pills, Hub header",
     "sizes": [12, 16, 18, 20, 22, 24, 26, 28],
     "sources": ["NotchBuddy/Sources/App/IslandRootView.swift",
                 "NotchBuddy/Sources/App/IslandViewContent.swift",
                 "NotchBuddy/Sources/App/SpotifyViews.swift",
                 "NotchBuddy/Sources/App/BotCanvasView.swift",
                 "NotchBuddy/Sources/App/FlowHub.swift",
                 "NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift"]},
    {"surface": "macOS / Windows: island layout body diameters",
     "sizes": [20, 44, 46, 50, 52, 56, 58, 62, 66],
     "sources": ["NotchBuddy/Sources/CoucouKit/IslandTypes.swift",
                 "windows/src/core/layout.ts"]},
    {"surface": "macOS / Windows: raster ceilings of expanded canvas sizes (diameter / 0.6)",
     "sizes": [44, 74, 77, 84, 87, 94, 97, 104, 110],
     "sources": ["NotchBuddy/Sources/App/IslandRootView.swift",
                 "NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift",
                 "windows/src/island/island.ts"]},
    {"surface": "macOS: Hub cast, empty states, hero, desktop panel",
     "sizes": [28, 40, 42, 44, 46, 48, 50, 52, 54, 56, 58, 60, 62, 66, 70, 96, 120],
     "sources": ["NotchBuddy/Sources/App/FlowHubMochis.swift",
                 "NotchBuddy/Sources/App/FlowHubNotes.swift",
                 "NotchBuddy/Sources/App/DesktopMochiLogic.swift"]},
    {"surface": "Windows: mini grid and service pills",
     "sizes": [13, 24],
     "sources": ["windows/src/island/island.ts", "windows/src/views/views.ts",
                 "windows/src/views/spotify.ts"]},
    {"surface": "iOS: fixed mascot slots and padded content sizes",
     "sizes": [18, 24, 26, 28, 30, 32, 34, 36, 40, 44, 48, 52, 56, 64, 76, 84, 88],
     "sources": ["NotchBuddy/Sources/Phone/HomeView.swift",
                 "NotchBuddy/Sources/Phone/ApprovalCard.swift",
                 "NotchBuddy/Sources/Phone/AboutView.swift",
                 "NotchBuddy/Sources/Phone/KitPreviewView.swift",
                 "NotchBuddy/Sources/Phone/LinkTestView.swift",
                 "NotchBuddy/Sources/Phone/SearchAndSpotlight.swift",
                 "NotchBuddy/Sources/Phone/SessionDetailView.swift",
                 "NotchBuddy/Sources/Phone/ServiceViews.swift",
                 "NotchBuddy/Sources/Phone/TurnShare.swift"]},
    {"surface": "iOS: fixed Widget / Live Activity slots and padded content",
     "sizes": [20, 22, 24, 32, 34, 40, 44, 52, 56],
     "sources": ["NotchBuddy/Sources/Widgets/CoucouWidgets.swift",
                 "NotchBuddy/Sources/Widgets/MochiLiveActivity.swift"]},
    {"surface": "Android: Compose screens, overlay and sheets",
     "sizes": [34, 40, 52, 84, 96, 108, 112, 120, 132],
     "sources": ["android/app/src/main/kotlin/com/coucou/android/ui/IslandOverlay.kt",
                 "android/app/src/main/kotlin/com/coucou/android/ui/HomePanel.kt",
                 "android/app/src/main/kotlin/com/coucou/android/ui/PairingScreen.kt",
                 "android/app/src/main/kotlin/com/coucou/android/ui/SessionScreen.kt",
                 "android/app/src/main/kotlin/com/coucou/android/ui/Sheets.kt",
                 "android/app/src/main/kotlin/com/coucou/android/ui/WardrobeScreen.kt",
                 "android/app/src/main/kotlin/com/coucou/android/ui/ChatScreen.kt"]},
    {"surface": "Android: list, glance, mood, alert, solo and large widgets",
     "sizes": [36, 64, 72, 84, 96, 104, 120, 140, 150, 170],
     "sources": ["android/app/src/main/kotlin/com/coucou/android/app/ListWidget.kt",
                 "android/app/src/main/kotlin/com/coucou/android/app/GlanceWidget.kt",
                 "android/app/src/main/kotlin/com/coucou/android/app/MoodWidget.kt",
                 "android/app/src/main/kotlin/com/coucou/android/app/WaitingAlertWidget.kt",
                 "android/app/src/main/kotlin/com/coucou/android/app/TodayWidget.kt",
                 "android/app/src/main/kotlin/com/coucou/android/app/SoloWidget.kt",
                 "android/app/src/main/kotlin/com/coucou/android/app/MochiBigWidget.kt"]},
    {"surface": "Declared hero limit and future animation frame canvas (single still only)",
     "sizes": [160, 240],
     "sources": ["NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift",
                 "NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/SpriteSheetAnimator.swift",
                 "windows/src/mascot/sprite-animator.ts"]},
]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect_png(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Not a PNG: {path}")
    width, height, depth, color, compression, filter_method, interlace = struct.unpack(
        ">IIBBBBB", data[16:29])
    if (depth, color, compression, filter_method, interlace) != (8, 6, 0, 0, 0):
        raise ValueError(f"Expected non-interlaced RGBA8: {path}")
    offset, compressed = 8, bytearray()
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        crc = struct.unpack(">I", data[offset + 8 + length:offset + 12 + length])[0]
        if zlib.crc32(kind + payload) & 0xffffffff != crc:
            raise ValueError(f"PNG chunk checksum failed: {path}")
        if kind == b"IDAT":
            compressed.extend(payload)
        offset += length + 12
        if kind == b"IEND":
            break
    if len(zlib.decompress(compressed)) != height * (width * 4 + 1):
        raise ValueError(f"Invalid pixel data: {path}")
    return width, height


def run_sips(*args):
    subprocess.run(["sips", *map(str, args)], check=True, capture_output=True, text=True)


def expected_variants():
    sizes = sorted({size for group in GROUPS for size in group["sizes"]})
    for size in sizes:
        for scale in SCALES:
            suffix = "" if scale == 1 else f"@{scale:g}x"
            yield size, scale, math.ceil(size * scale), f"png/astral-idle-{size}{suffix}.png"


def check():
    manifest = json.loads(MANIFEST.read_text())
    assert manifest["master_sha256"] == sha256(MASTER), "Master changed"
    assert manifest["normalized_sha256"] == sha256(NORMALIZED), "Normalized source changed"
    assert inspect_png(NORMALIZED) == (CROP["width"], CROP["height"])
    expected = list(expected_variants())
    assert len(manifest["variants"]) == len(expected), "Incomplete export manifest"
    for item, (size, scale, pixels, filename) in zip(manifest["variants"], expected):
        assert (item["logical_size"], item["scale"], item["file"]) == (size, scale, filename)
        path = ASSETS / filename
        assert inspect_png(path) == (pixels, pixels), path
        assert sha256(path) == item["sha256"], path
    for group in GROUPS:
        for source in group["sources"]:
            assert (ROOT / source).is_file(), source
    print(f"Verified {len(expected)} RGBA PNG exports, all dimensions, checksums and source paths.")


def export():
    master_before = sha256(MASTER)
    assert inspect_png(MASTER) == (1254, 1254)
    (ASSETS / "png").mkdir(exist_ok=True)
    run_sips("-c", CROP["height"], CROP["width"], "--cropOffset", CROP["y"], CROP["x"],
             MASTER, "--out", NORMALIZED)
    variants = []
    for size, scale, pixels, filename in expected_variants():
        path = ASSETS / filename
        run_sips("-z", pixels, pixels, NORMALIZED, "--out", path)
        variants.append({"logical_size": size, "scale": scale, "pixels": [pixels, pixels],
                         "file": filename, "sha256": sha256(path)})
    assert sha256(MASTER) == master_before, "Export modified the approved master"
    manifest = {
        "schema": 1, "state": "idle", "core": False, "master": MASTER.name,
        "master_sha256": master_before, "normalized": NORMALIZED.name,
        "normalized_sha256": sha256(NORMALIZED), "normalization_crop": CROP,
        "logical_sizes": sorted({size for group in GROUPS for size in group["sizes"]}),
        "scales": list(SCALES), "groups": GROUPS,
        "notes": [
            "Static assets only. Native app renderers are unchanged.",
            "1x/2x/3x: Apple or web; Android mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi: 1x/1.5x/2x/3x/4x.",
            "Pixel sides are rounded up for fractional density scales.",
            "Transparent square exports share one crop and baseline; use aspect fit, no stretching.",
            "Continuously resized and spring-animated surfaces use the next larger raster or 240@4x.",
            "A 240px still is not a multi-frame sprite sheet and must not use the astral_idle strip filename.",
            "Zero-opacity hidden placeholders need no image. Tinted/monochrome widget art is not included."
        ], "variants": variants
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    check()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify existing exports without rewriting them")
    if parser.parse_args().check:
        check()
    else:
        export()
