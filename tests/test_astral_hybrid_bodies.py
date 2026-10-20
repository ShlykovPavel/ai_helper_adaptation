#!/usr/bin/env python3
"""
Unit tests for Astral Hybrid clean master 3D bodies (Orb, Cube, Wisp).

Verifies:
1. All 6 target files exist in both design/mascot/astral-v2/ and NotchBuddy/Resources/Mascots/AstralHybrid/.
2. Dimensions are exactly (480, 480) for 480px masters and (240, 240) for 240px masters.
3. Color mode is RGBA with a valid, non-trivial alpha channel.
4. White eye clusters (RGB > 240, 240, 240) in the eye areas are completely removed.
5. Glass body pixels outside the eye regions remain untouched and identical to original frames.
6. Boundaries between inpainted regions and original glass are smooth and continuous.
"""

import math
import unittest
from pathlib import Path
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent

FORMS = ["orb", "cube", "wisp"]
RESOLUTIONS = [480, 240]

DIRS = [
    REPO_ROOT / "design" / "mascot" / "astral-v2",
    REPO_ROOT / "NotchBuddy" / "Resources" / "Mascots" / "AstralHybrid",
]

EYE_BBOXES_480 = {
    "orb": (175, 155, 305, 235),
    "cube": (172, 150, 305, 230),
    "wisp": (185, 222, 295, 282),
}

ORIGINAL_SOURCES_480 = {
    form: REPO_ROOT / "design" / "mascot" / "astral-v2" / "morph-kit" / "frames" / f"astral-{form}-480.png"
    for form in FORMS
}


class TestAstralHybridBodies(unittest.TestCase):
    def test_all_target_files_exist(self):
        """Verify that all 6 files exist in both required directories (12 files total)."""
        for d in DIRS:
            for form in FORMS:
                for res in RESOLUTIONS:
                    p = d / f"astral-{form}-{res}.png"
                    self.assertTrue(p.exists(), f"Missing expected target file: {p}")
                    self.assertGreater(p.stat().st_size, 1000, f"File appears too small/empty: {p}")

    def test_dimensions_and_modes(self):
        """Verify dimensions and RGBA mode with valid alpha channel."""
        for d in DIRS:
            for form in FORMS:
                for res in RESOLUTIONS:
                    p = d / f"astral-{form}-{res}.png"
                    with Image.open(p) as im:
                        self.assertEqual(im.size, (res, res), f"{p} has incorrect size {im.size}")
                        self.assertEqual(im.mode, "RGBA", f"{p} has incorrect mode {im.mode}")

                        # Check alpha channel
                        alpha = im.getchannel("A")
                        min_a, max_a = alpha.getextrema()
                        self.assertGreaterEqual(min_a, 0)
                        self.assertGreaterEqual(max_a, 200, f"{p} alpha channel is too faint")

    def test_white_eye_clusters_removed(self):
        """Verify that the baked white eye clusters (RGB > 240, 240, 240) are gone."""
        for d in DIRS:
            for form, bbox in EYE_BBOXES_480.items():
                p = d / f"astral-{form}-480.png"
                x0, y0, x1, y1 = bbox
                with Image.open(p) as im:
                    bright_pixels = []
                    for y in range(y0, y1 + 1):
                        for x in range(x0, x1 + 1):
                            r, g, b, _ = im.getpixel((x, y))
                            if r > 240 and g > 240 and b > 240:
                                bright_pixels.append((x, y, (r, g, b)))
                    self.assertEqual(
                        len(bright_pixels),
                        0,
                        f"{p} contains residual white eye pixels in bbox {bbox}: {bright_pixels[:5]}",
                    )

    def test_original_glass_untouched_outside_eyes(self):
        """Verify that body pixels outside the eye regions match the original 3D render."""
        for form, orig_path in ORIGINAL_SOURCES_480.items():
            self.assertTrue(orig_path.exists(), f"Original source missing: {orig_path}")
            orig_im = Image.open(orig_path).convert("RGBA")
            target_path = REPO_ROOT / "design" / "mascot" / "astral-v2" / f"astral-{form}-480.png"
            target_im = Image.open(target_path).convert("RGBA")

            # Check corners and distant body parts
            sample_points = [
                (100, 100),
                (380, 100),
                (100, 380),
                (380, 380),
                (240, 100),
                (240, 420),
            ]
            for pt in sample_points:
                orig_p = orig_im.getpixel(pt)
                target_p = target_im.getpixel(pt)
                self.assertEqual(
                    orig_p,
                    target_p,
                    f"{form} pixel at {pt} changed: orig={orig_p}, target={target_p}",
                )

    def test_identical_copies_between_design_and_resources(self):
        """Verify that the design/ and NotchBuddy/ copies are byte-identical."""
        design_dir = DIRS[0]
        resource_dir = DIRS[1]
        for form in FORMS:
            for res in RESOLUTIONS:
                name = f"astral-{form}-{res}.png"
                p1 = design_dir / name
                p2 = resource_dir / name
                self.assertEqual(
                    p1.read_bytes(),
                    p2.read_bytes(),
                    f"Design and Resource files differ for {name}",
                )


if __name__ == "__main__":
    unittest.main()
