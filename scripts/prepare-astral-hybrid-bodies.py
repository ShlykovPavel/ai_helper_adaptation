#!/usr/bin/env python3
"""
Generate clean 3D master bodies without baked eyes for Astral Hybrid (Orb, Cube, Wisp).

Removes the baked white eye capsules and cyan glow from the 3D rendered frames
using harmonic Laplace surface inpainting and Hermite feathering, preserving the
surrounding translucent glass body material and lighting.

Generates:
  - astral-{orb,cube,wisp}-480.png (480x480 RGBA)
  - astral-{orb,cube,wisp}-240.png (240x240 RGBA, Lanczos)
and places them in both design/mascot/astral-v2/ and NotchBuddy/Resources/Mascots/AstralHybrid/.
"""

import math
import os
import sys
from pathlib import Path
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent

FORMS = {
    "orb": {
        "source": REPO_ROOT / "design/mascot/astral-v2/morph-kit/frames/astral-orb-480.png",
        "eyes": [
            {"cx": 200, "cy": 193, "rx": 28, "ry": 42},
            {"cx": 280, "cy": 193, "rx": 28, "ry": 42},
        ],
        "check_bbox": (175, 155, 305, 235),
    },
    "cube": {
        "source": REPO_ROOT / "design/mascot/astral-v2/morph-kit/frames/astral-cube-480.png",
        "eyes": [
            {"cx": 196, "cy": 190, "rx": 28, "ry": 42},
            {"cx": 281, "cy": 190, "rx": 28, "ry": 42},
        ],
        "check_bbox": (172, 150, 305, 230),
    },
    "wisp": {
        "source": REPO_ROOT / "design/mascot/astral-v2/morph-kit/frames/astral-wisp-480.png",
        "eyes": [
            {"cx": 208, "cy": 252, "rx": 26, "ry": 33},
            {"cx": 272, "cy": 252, "rx": 26, "ry": 33},
        ],
        "check_bbox": (185, 222, 295, 282),
    },
}

DEST_DIRS = [
    REPO_ROOT / "design/mascot/astral-v2",
    REPO_ROOT / "NotchBuddy/Resources/Mascots/AstralHybrid",
]


def inpaint_eye_regions(
    im_src: Image.Image,
    eyes: list[dict[str, int | float]],
    feather: float = 2.5,
    iterations: int = 120,
    omega: float = 1.45,
) -> Image.Image:
    """
    Seamlessly inpaint eye regions using Laplace's equation (\\Delta u = 0) with
    Dirichlet boundary conditions sampled from the authentic surrounding glass body.
    """
    im = im_src.copy()
    w, h = im.size
    orig_pixels = im.load()

    for eye in eyes:
        cx, cy, rx, ry = eye["cx"], eye["cy"], eye["rx"], eye["ry"]
        d = max(0.0, ry - rx)

        box_x0 = max(0, int(cx - rx - feather - 4))
        box_x1 = min(w - 1, int(cx + rx + feather + 4))
        box_y0 = max(0, int(cy - ry - feather - 4))
        box_y1 = min(h - 1, int(cy + ry + feather + 4))

        gw = box_x1 - box_x0 + 1
        gh = box_y1 - box_y0 + 1

        mask = [[0 for _ in range(gw)] for _ in range(gh)]
        dist_grid = [[0.0 for _ in range(gw)] for _ in range(gh)]

        for y in range(gh):
            gy = box_y0 + y
            y_clamp = max(cy - d, min(cy + d, float(gy)))
            for x in range(gw):
                gx = box_x0 + x
                dist = math.sqrt((gx - cx) ** 2 + (gy - y_clamp) ** 2)
                dist_grid[y][x] = dist
                if dist <= rx:
                    mask[y][x] = 1

        for ch_idx in range(4):
            val_grid = [
                [
                    float(orig_pixels[box_x0 + x, box_y0 + y][ch_idx])
                    for x in range(gw)
                ]
                for y in range(gh)
            ]

            # Bilateral linear interpolation from unmasked borders as smooth initial guess
            for y in range(gh):
                gy = box_y0 + y
                left_val, right_val = None, None
                for x in range(gw):
                    gx = box_x0 + x
                    if mask[y][x] == 0:
                        left_val = val_grid[y][x]
                    else:
                        break
                for x in range(gw - 1, -1, -1):
                    gx = box_x0 + x
                    if mask[y][x] == 0:
                        right_val = val_grid[y][x]
                    else:
                        break
                if left_val is not None and right_val is not None:
                    for x in range(gw):
                        if mask[y][x] == 1:
                            val_grid[y][x] = (left_val + right_val) / 2.0

            # Successive Over-Relaxation (SOR) solving Laplace's equation:
            # 4 * u(x, y) - u(x+1, y) - u(x-1, y) - u(x, y+1) - u(x, y-1) = 0
            for _ in range(iterations):
                for y in range(1, gh - 1):
                    row = val_grid[y]
                    row_u = val_grid[y - 1]
                    row_d = val_grid[y + 1]
                    for x in range(1, gw - 1):
                        if mask[y][x] == 1:
                            target = 0.25 * (
                                row[x - 1] + row[x + 1] + row_u[x] + row_d[x]
                            )
                            row[x] += omega * (target - row[x])

            # Write back inpainted values with Hermite smoothstep feathering at the outer boundary
            for y in range(gh):
                gy = box_y0 + y
                for x in range(gw):
                    gx = box_x0 + x
                    dist = dist_grid[y][x]
                    if dist <= rx - feather:
                        p = list(orig_pixels[gx, gy])
                        p[ch_idx] = int(round(max(0.0, min(255.0, val_grid[y][x]))))
                        orig_pixels[gx, gy] = tuple(p)
                    elif dist <= rx + feather:
                        t = (dist - (rx - feather)) / (2.0 * feather)
                        w_blend = t * t * (3.0 - 2.0 * t)
                        inpainted_val = val_grid[y][x]
                        orig_val = float(orig_pixels[gx, gy][ch_idx])
                        final_val = (1.0 - w_blend) * inpainted_val + w_blend * orig_val
                        p = list(orig_pixels[gx, gy])
                        p[ch_idx] = int(round(max(0.0, min(255.0, final_val))))
                        orig_pixels[gx, gy] = tuple(p)

    return im


def verify_image(path: Path, expected_size: tuple[int, int], check_bbox: tuple[int, int, int, int] | None = None) -> list[str]:
    """Verify that the generated image satisfies all visual and structural requirements."""
    errors = []
    if not path.exists():
        return [f"File not found: {path}"]

    try:
        im = Image.open(path)
        im.load()
    except Exception as e:
        return [f"Cannot open {path}: {e}"]

    if im.size != expected_size:
        errors.append(f"{path}: expected size {expected_size}, got {im.size}")

    if im.mode != "RGBA":
        errors.append(f"{path}: expected mode RGBA, got {im.mode}")

    # Check alpha channel validity
    alpha_extrema = im.getchannel("A").getextrema()
    if alpha_extrema[1] < 200:
        errors.append(f"{path}: invalid alpha channel, max alpha is {alpha_extrema[1]}")

    # Check that white eye clusters (RGB > 240, 240, 240) are gone in check_bbox
    if check_bbox and expected_size == (480, 480):
        x0, y0, x1, y1 = check_bbox
        bright_count = 0
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                r, g, b, _ = im.getpixel((x, y))
                if r > 240 and g > 240 and b > 240:
                    bright_count += 1
        if bright_count > 0:
            errors.append(
                f"{path}: found {bright_count} residual white eye pixels (RGB > 240) in bbox {check_bbox}"
            )

    return errors


def main() -> int:
    print("=== Generating Astral Hybrid Master Bodies (Orb, Cube, Wisp) ===")
    for dest_dir in DEST_DIRS:
        dest_dir.mkdir(parents=True, exist_ok=True)

    generated_files: list[tuple[Path, tuple[int, int], tuple[int, int, int, int] | None]] = []

    for name, config in FORMS.items():
        src_path: Path = config["source"]
        if not src_path.exists():
            print(f"Error: Source file missing: {src_path}", file=sys.stderr)
            return 1

        print(f"\nProcessing {name.upper()} from {src_path.relative_to(REPO_ROOT)}...")
        src_im = Image.open(src_path).convert("RGBA")

        # Inpaint at 480x480
        body_480 = inpaint_eye_regions(src_im, config["eyes"])

        # Lanczos downscale to 240x240
        body_240 = body_480.resize((240, 240), Image.Resampling.LANCZOS)

        # Save to both design/ and NotchBuddy resources
        for dest_dir in DEST_DIRS:
            out_480 = dest_dir / f"astral-{name}-480.png"
            out_240 = dest_dir / f"astral-{name}-240.png"

            body_480.save(out_480, "PNG", optimize=True)
            body_240.save(out_240, "PNG", optimize=True)

            print(f"  Saved: {out_480.relative_to(REPO_ROOT)} ({out_480.stat().st_size} bytes)")
            print(f"  Saved: {out_240.relative_to(REPO_ROOT)} ({out_240.stat().st_size} bytes)")

            generated_files.append((out_480, (480, 480), config["check_bbox"]))
            generated_files.append((out_240, (240, 240), None))

    print("\n=== Verifying Generated Bodies ===")
    all_errors = []
    for file_path, size, bbox in generated_files:
        errs = verify_image(file_path, size, bbox)
        if errs:
            all_errors.extend(errs)
        else:
            print(f"  PASS: {file_path.relative_to(REPO_ROOT)} [size={size}, RGBA, clean eye bbox]")

    if all_errors:
        print("\nVerification FAILED:", file=sys.stderr)
        for err in all_errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print("\nAll 6 target files generated and verified successfully in both directories.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
