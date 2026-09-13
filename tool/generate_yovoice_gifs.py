#!/usr/bin/env python3
"""Generate the original, first-party GIF pack bundled with YO Voice."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets" / "gifs" / "yovoice"
MANIFEST = OUTPUT / "manifest.json"
FONT_PATH = ROOT / "assets" / "fonts" / "InterVariable.ttf"
WIDTH, HEIGHT = 320, 200
FRAMES = 12

REACTIONS = (
    ("yoLove01", "LOVE", (255, 75, 169), "heart"),
    ("yoLol001", "LOL", (255, 194, 70), "smile"),
    ("yoWow001", "WOW!", (116, 98, 255), "burst"),
    ("yoYes001", "YES!", (43, 213, 150), "check"),
    ("yoNo0001", "NOPE", (255, 91, 110), "cross"),
    ("yoHey001", "HEY!", (64, 190, 255), "wave"),
    ("yoThx001", "THANKS", (177, 113, 255), "sparkle"),
    ("yoClap01", "BRAVO", (255, 151, 66), "clap"),
    ("yoParty1", "PARTY", (245, 78, 226), "confetti"),
    ("yoHug001", "HUG", (255, 111, 156), "hug"),
    ("yoFire01", "FIRE", (255, 103, 48), "flame"),
    ("yoCool01", "COOL", (50, 211, 220), "glasses"),
    ("yoMorn01", "MORNING", (255, 188, 73), "sun"),
    ("yoNight1", "GOOD NIGHT", (113, 126, 255), "moon"),
    ("yoMic001", "ON AIR", (184, 82, 255), "mic"),
    ("yoWin001", "WE WON", (64, 220, 153), "trophy"),
)


def mix(a: int, b: int, amount: float) -> int:
    return round(a + (b - a) * amount)


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT_PATH), size)


def heart(draw: ImageDraw.ImageDraw, x: float, y: float, s: float, fill):
    points = []
    for step in range(101):
        t = math.tau * step / 100
        px = 16 * math.sin(t) ** 3
        py = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        points.append((x + px * s / 32, y - py * s / 32))
    draw.polygon(points, fill=fill)


def draw_icon(draw: ImageDraw.ImageDraw, kind: str, cx: float, cy: float, size: float, color):
    w = max(3, round(size * 0.09))
    box = (cx - size / 2, cy - size / 2, cx + size / 2, cy + size / 2)
    if kind == "heart":
        heart(draw, cx, cy + 2, size * 1.25, color)
    elif kind == "smile":
        draw.ellipse(box, outline=color, width=w)
        draw.ellipse((cx - 13, cy - 10, cx - 7, cy - 4), fill=color)
        draw.ellipse((cx + 7, cy - 10, cx + 13, cy - 4), fill=color)
        draw.arc((cx - 18, cy - 8, cx + 18, cy + 19), 12, 168, fill=color, width=w)
    elif kind == "burst":
        for index in range(10):
            angle = math.tau * index / 10
            draw.line((cx + math.cos(angle) * size * .28, cy + math.sin(angle) * size * .28,
                       cx + math.cos(angle) * size * .52, cy + math.sin(angle) * size * .52), fill=color, width=w)
        draw.ellipse((cx - 7, cy - 7, cx + 7, cy + 7), fill=color)
    elif kind == "check":
        draw.line((cx - 20, cy, cx - 6, cy + 15, cx + 23, cy - 18), fill=color, width=w + 2, joint="curve")
    elif kind == "cross":
        draw.line((cx - 18, cy - 18, cx + 18, cy + 18), fill=color, width=w + 2)
        draw.line((cx + 18, cy - 18, cx - 18, cy + 18), fill=color, width=w + 2)
    elif kind == "wave":
        for offset in (-12, 0, 12):
            draw.arc((cx - 24 + offset, cy - 22, cx + 4 + offset, cy + 22), 285, 75, fill=color, width=w)
    elif kind == "sparkle":
        for angle in (0, math.pi / 2):
            draw.line((cx - math.cos(angle) * 25, cy - math.sin(angle) * 25,
                       cx + math.cos(angle) * 25, cy + math.sin(angle) * 25), fill=color, width=w)
        draw.ellipse((cx - 5, cy - 5, cx + 5, cy + 5), fill=color)
    elif kind == "clap":
        draw.arc((cx - 27, cy - 23, cx + 7, cy + 24), 270, 80, fill=color, width=w)
        draw.arc((cx - 7, cy - 23, cx + 27, cy + 24), 100, 270, fill=color, width=w)
        draw.line((cx - 29, cy - 29, cx - 39, cy - 39), fill=color, width=w)
        draw.line((cx + 29, cy - 29, cx + 39, cy - 39), fill=color, width=w)
    elif kind == "confetti":
        for index in range(9):
            angle = math.tau * index / 9
            x = cx + math.cos(angle) * size * .42
            y = cy + math.sin(angle) * size * .36
            draw.rounded_rectangle((x - 3, y - 7, x + 3, y + 7), radius=2, fill=color)
        draw.polygon((cx - 14, cy + 20, cx + 2, cy - 16, cx + 19, cy + 20), outline=color)
    elif kind == "hug":
        draw.ellipse((cx - 22, cy - 20, cx - 4, cy - 2), outline=color, width=w)
        draw.ellipse((cx + 4, cy - 20, cx + 22, cy - 2), outline=color, width=w)
        draw.arc((cx - 29, cy - 7, cx + 29, cy + 30), 185, 355, fill=color, width=w)
    elif kind == "flame":
        draw.polygon((cx, cy - 29, cx + 20, cy - 2, cx + 13, cy + 24,
                      cx, cy + 30, cx - 17, cy + 20, cx - 20, cy - 4), fill=color)
        draw.ellipse((cx - 7, cy + 2, cx + 7, cy + 23), fill=(255, 238, 170, 255))
    elif kind == "glasses":
        draw.rounded_rectangle((cx - 29, cy - 13, cx - 3, cy + 7), radius=6, outline=color, width=w)
        draw.rounded_rectangle((cx + 3, cy - 13, cx + 29, cy + 7), radius=6, outline=color, width=w)
        draw.line((cx - 3, cy - 5, cx + 3, cy - 5), fill=color, width=w)
        draw.arc((cx - 18, cy - 2, cx + 18, cy + 25), 15, 165, fill=color, width=w)
    elif kind == "sun":
        draw.ellipse((cx - 16, cy - 16, cx + 16, cy + 16), fill=color)
        for index in range(8):
            angle = math.tau * index / 8
            draw.line((cx + math.cos(angle) * 23, cy + math.sin(angle) * 23,
                       cx + math.cos(angle) * 33, cy + math.sin(angle) * 33), fill=color, width=w)
    elif kind == "moon":
        draw.ellipse(box, fill=color)
        draw.ellipse((cx - size * .05, cy - size * .31, cx + size * .55, cy + size * .27), fill=(22, 22, 53, 255))
    elif kind == "mic":
        draw.rounded_rectangle((cx - 12, cy - 25, cx + 12, cy + 9), radius=12, outline=color, width=w)
        draw.arc((cx - 22, cy - 8, cx + 22, cy + 25), 0, 180, fill=color, width=w)
        draw.line((cx, cy + 25, cx, cy + 34), fill=color, width=w)
        draw.line((cx - 12, cy + 34, cx + 12, cy + 34), fill=color, width=w)
    elif kind == "trophy":
        draw.polygon((cx - 18, cy - 22, cx + 18, cy - 22, cx + 12, cy + 7,
                      cx + 4, cy + 15, cx - 4, cy + 15, cx - 12, cy + 7), fill=color)
        draw.arc((cx - 31, cy - 20, cx - 7, cy + 5), 80, 280, fill=color, width=w)
        draw.arc((cx + 7, cy - 20, cx + 31, cy + 5), 260, 100, fill=color, width=w)
        draw.line((cx, cy + 15, cx, cy + 27), fill=color, width=w)
        draw.line((cx - 14, cy + 28, cx + 14, cy + 28), fill=color, width=w)


def frame_for(label: str, accent, kind: str, index: int) -> Image.Image:
    phase = math.tau * index / FRAMES
    base = Image.new("RGBA", (WIDTH, HEIGHT), (8, 8, 22, 255))
    pixels = base.load()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            diagonal = (x / WIDTH * .65) + (y / HEIGHT * .35)
            glow = max(0.0, 1 - math.hypot(x - 255, y - 35) / 280)
            pixels[x, y] = (
                mix(8, accent[0], .09 + glow * .16),
                mix(8, accent[1], .09 + glow * .16),
                mix(22, accent[2], .12 + glow * .22 + diagonal * .03),
                255,
            )

    glow_layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_layer)
    pulse = 1 + .10 * math.sin(phase)
    gx, gy = 72 + 11 * math.cos(phase), 78 + 8 * math.sin(phase)
    radius = 55 * pulse
    glow_draw.ellipse((gx - radius, gy - radius, gx + radius, gy + radius), fill=(*accent, 96))
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(24))
    base = Image.alpha_composite(base, glow_layer)

    draw = ImageDraw.Draw(base)
    for orbit in range(3):
        angle = phase + orbit * math.tau / 3
        ox = 160 + math.cos(angle) * (126 - orbit * 18)
        oy = 100 + math.sin(angle) * (70 - orbit * 9)
        dot = 3 + orbit
        draw.ellipse((ox - dot, oy - dot, ox + dot, oy + dot), fill=(*accent, 120 + orbit * 30))

    card_y = round(30 + math.sin(phase) * 3)
    draw.rounded_rectangle((24, card_y, 296, card_y + 140), radius=32,
                           fill=(12, 12, 34, 225), outline=(*accent, 180), width=2)
    icon_fill = tuple(mix(12, channel, .16) for channel in accent) + (255,)
    draw.rounded_rectangle((38, card_y + 14, 106, card_y + 82), radius=22,
                           fill=icon_fill, outline=(*accent, 255), width=1)
    draw_icon(draw, kind, 72, card_y + 48, 54 * pulse, (248, 246, 255, 255))

    size = 46 if len(label) <= 6 else 34 if len(label) <= 8 else 28
    face = font(size)
    bounds = draw.textbbox((0, 0), label, font=face)
    text_width = bounds[2] - bounds[0]
    available = 168
    while text_width > available and size > 20:
        size -= 1
        face = font(size)
        bounds = draw.textbbox((0, 0), label, font=face)
        text_width = bounds[2] - bounds[0]
    tx = 122 + (available - text_width) / 2
    ty = card_y + 40 - (bounds[3] - bounds[1]) / 2
    shadow = max(1, round(2 + math.sin(phase)))
    draw.text((tx + shadow, ty + shadow), label, font=face, fill=(0, 0, 0, 120))
    draw.text((tx, ty), label, font=face, fill=(250, 249, 255, 255))

    small = font(12)
    draw.text((122, card_y + 94), "YO VOICE ORIGINAL", font=small, fill=(*accent, 225))
    draw.rounded_rectangle((122, card_y + 116, 258, card_y + 121), radius=3, fill=(44, 43, 66, 255))
    progress = 122 + round(136 * (index + 1) / FRAMES)
    draw.rounded_rectangle((122, card_y + 116, progress, card_y + 121), radius=3, fill=(*accent, 220))
    return base.convert("P", palette=Image.Palette.ADAPTIVE, colors=128)


def load_pillow() -> None:
    global Image, ImageDraw, ImageFilter, ImageFont
    try:
        from PIL import Image, ImageDraw, ImageFilter, ImageFont
    except ModuleNotFoundError:
        raise SystemExit(
            "Generating the pack requires Pillow 12.3.0. Install the pinned "
            "tool dependency with: python3 -m pip install -r "
            "tool/requirements-yovoice-gifs.txt\n"
            "Validation needs no dependency: python3 "
            "tool/generate_yovoice_gifs.py --check"
        ) from None


def generate() -> None:
    load_pillow()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    expected = set()
    files = []
    for gif_id, label, accent, kind in REACTIONS:
        path = OUTPUT / f"{gif_id}.gif"
        expected.add(path.name)
        frames = [frame_for(label, accent, kind, index) for index in range(FRAMES)]
        frames[0].save(
            path,
            save_all=True,
            append_images=frames[1:],
            duration=85,
            loop=0,
            disposal=2,
            optimize=True,
        )
        payload = path.read_bytes()
        files.append({
            "id": gif_id,
            "file": path.name,
            "bytes": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest(),
        })
    for stale in OUTPUT.glob("*.gif"):
        if stale.name not in expected:
            stale.unlink()
    MANIFEST.write_text(json.dumps({
        "schemaVersion": 1,
        "generator": "tool/generate_yovoice_gifs.py",
        "width": WIDTH,
        "height": HEIGHT,
        "frames": FRAMES,
        "files": files,
    }, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def check() -> None:
    try:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"Invalid or missing {MANIFEST.relative_to(ROOT)}: {error}") from error

    expected_ids = [entry[0] for entry in REACTIONS]
    files = manifest.get("files")
    if manifest.get("schemaVersion") != 1:
        raise SystemExit("GIF manifest schemaVersion is not supported.")
    if manifest.get("generator") != "tool/generate_yovoice_gifs.py":
        raise SystemExit("GIF manifest generator path is stale.")
    if (
        not isinstance(files, list)
        or any(not isinstance(entry, dict) for entry in files)
        or [entry.get("id") for entry in files] != expected_ids
    ):
        raise SystemExit("GIF manifest ids do not match the generator catalog.")
    if (manifest.get("width"), manifest.get("height"), manifest.get("frames")) != (
        WIDTH, HEIGHT, FRAMES
    ):
        raise SystemExit("GIF manifest dimensions or frame count are stale.")

    expected_names = {f"{gif_id}.gif" for gif_id in expected_ids}
    actual_names = {path.name for path in OUTPUT.glob("*.gif")}
    if actual_names != expected_names:
        raise SystemExit(
            f"GIF asset set differs from manifest: missing={sorted(expected_names - actual_names)}, "
            f"unexpected={sorted(actual_names - expected_names)}"
        )

    for entry in files:
        if entry.get("file") != f"{entry['id']}.gif":
            raise SystemExit(f"GIF manifest filename is invalid for {entry['id']}.")
        path = OUTPUT / entry["file"]
        payload = path.read_bytes()
        if payload[:6] not in (b"GIF87a", b"GIF89a") or len(payload) < 10:
            raise SystemExit(f"{path.relative_to(ROOT)} is not a GIF file.")
        width, height = struct.unpack("<HH", payload[6:10])
        if (width, height) != (WIDTH, HEIGHT):
            raise SystemExit(
                f"{path.relative_to(ROOT)} is {width}x{height}; expected {WIDTH}x{HEIGHT}."
            )
        frames = payload.count(b"\x21\xf9\x04")
        if frames != FRAMES:
            raise SystemExit(
                f"{path.relative_to(ROOT)} has {frames} frames; expected {FRAMES}."
            )
        digest = hashlib.sha256(payload).hexdigest()
        if digest != entry.get("sha256") or len(payload) != entry.get("bytes"):
            raise SystemExit(f"{path.relative_to(ROOT)} does not match manifest.json.")
    print(f"OK: {len(files)} YO Voice GIFs, {FRAMES} frames each, manifest verified.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="validate committed GIFs and checksums without importing Pillow",
    )
    arguments = parser.parse_args()
    if arguments.check:
        check()
    else:
        generate()


if __name__ == "__main__":
    main()
