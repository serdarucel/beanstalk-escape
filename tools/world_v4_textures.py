"""Derive world-v4 textures from the approved A paintings using Pillow only.

Run from any directory: python <path>/world_v4_textures.py
This writes only the v4 assets, their manifest, and the requested preview board.
No game import, gameplay run, screenshot, or image-generation service is used.
"""

from __future__ import annotations

import colorsys
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "02-kod-eglence/assets/art/world/v4"
DESIGN = ROOT / "01-tasarim/dunya-v4"
PREVIEW = ROOT / "03-test/uygula-v4-20261018/doku-onizleme.png"
PERIOD = 183
BODY = 128
PAD = 2
CROWN_BOX = (620, 0, 1770, 360)
LOOPS = (280, 580, 880)
EXIT = 260
SKY = (66, 179, 238, 255)
RESAMPLE = Image.Resampling.LANCZOS


def green(rgb: tuple[int, ...]) -> bool:
    r, g, b = rgb[:3]
    return g > b * 1.12 and g > r * 1.05


def plant(rgb: tuple[int, ...]) -> bool:
    r, g, b = rgb[:3]
    # Warm yellow-green highlights belong to the plant, including its rim.
    return g > b * 1.12 and g > r * .72


def mix(a: tuple[int, ...], b: tuple[int, ...], t: float) -> tuple[int, ...]:
    return tuple(round(x * (1 - t) + y * t) for x, y in zip(a, b))


def cool_dark(rgb: tuple[int, ...]) -> tuple[int, int, int]:
    h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in rgb[:3]))
    # Preserve source brushwork; keep the structural tree cool and subdued.
    h = .35 + (h - .30) * .25
    return tuple(round(c * 255) for c in colorsys.hsv_to_rgb(h, s * .62, v * .65))


def straighten(source: Image.Image, box: tuple[int, int, int, int], width: int) -> Image.Image:
    """Rectify the painted silhouette row by row, discarding the sky matte."""
    left, top, right, bottom = box
    result = Image.new("RGB", (width, bottom - top))
    for y in range(top, bottom):
        xs = [x for x in range(left, right) if green(source.getpixel((x, y)))]
        if not xs:
            raise ValueError(f"No painted body in source row {y}")
        # Ignore antialiased blue/green mixed fringe before resampling.
        row = source.crop((min(xs) + 1, y, max(xs), y + 1)).resize((width, 1), RESAMPLE)
        result.paste(row, (0, y - top))
    return result


def soften_edges(image: Image.Image) -> Image.Image:
    """Replace painted contour strokes with nearby surface color, never black."""
    result = image.copy()
    w, h = image.size
    for y in range(h):
        for side in (0, 1):
            near = image.getpixel((16 if side == 0 else w - 17, y))
            for distance in range(10):
                x = distance if side == 0 else w - 1 - distance
                original = image.getpixel((x, y))
                # At the silhouette the color is 95% of the nearby inner surface.
                surface = tuple(round(c * .95) for c in near)
                result.putpixel((x, y), mix(surface, original, distance / 10))
    return result


def periodic(image: Image.Image, margin: int = 22) -> Image.Image:
    """Close the periodic boundary with a smooth, local source-color correction."""
    result = image.copy()
    w, h = image.size
    for x in range(w):
        first = image.getpixel((x, 0))
        last = image.getpixel((x, h - 1))
        middle = mix(first, last, .5)
        for d in range(margin):
            t = .5 + .5 * math.cos(math.pi * d / margin)
            for y, boundary in ((d, first), (h - 1 - d, last)):
                old = image.getpixel((x, y))
                result.putpixel((x, y), tuple(
                    max(0, min(255, round(c + (m - b) * t)))
                    for c, m, b in zip(old, middle, boundary)
                ))
    return result


def padded(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    # One soft coverage pixel, with surface RGB retained under transparency.
    for y in range(rgba.height):
        for x in (0, rgba.width - 1):
            rgba.putpixel((x, y), (*rgba.getpixel((x, y))[:3], 210))
    result = Image.new("RGBA", (image.width + PAD * 2, image.height))
    result.paste(rgba, (PAD, 0))
    return result


def vine_tile(portrait: Image.Image) -> tuple[Image.Image, int]:
    clean = straighten(portrait, (175, 600, 320, 1150), BODY)
    # 183 px is the measured twist repeat in this clean left-hand vine.
    # Use the best source boundary within that region instead of a guessed cut.
    def error(y: int) -> float:
        return sum(abs(a - b)
                   for x in range(6, BODY - 6, 3)
                   for a, b in zip(clean.getpixel((x, y)), clean.getpixel((x, y + PERIOD - 1))))
    start = min(range(550 - PERIOD + 1), key=error)
    tile = clean.crop((0, start, BODY, start + PERIOD))
    return padded(periodic(soften_edges(tile))), start


def trunk_tile(landscape: Image.Image) -> Image.Image:
    sample = straighten(landscape, (1100, 0, 1230, 80), 192)
    sample = sample.resize((192, 256), RESAMPLE)
    sample.putdata([cool_dark(rgb) for rgb in sample.get_flattened_data()])
    return padded(periodic(soften_edges(sample), 32))


def matte_crown(landscape: Image.Image) -> Image.Image:
    source = landscape.crop(CROWN_BOX).convert("RGB")
    result = Image.new("RGBA", source.size)
    foreground = Image.new("L", source.size)
    paint = ImageDraw.Draw(foreground)
    # Follow the actual wraps rather than tinting rectangular lane bands.
    for points in (
        [(850, 85), (880, 58), (905, 52), (937, 76), (953, 155),
         (964, 360), (837, 360), (835, 174)],
        [(943, 67), (967, 68), (982, 98), (973, 147), (948, 169), (931, 106)],
        [(1134, 122), (1165, 109), (1191, 120), (1220, 157),
         (1260, 240), (1260, 360), (1110, 360), (1120, 225)],
        [(1475, 62), (1508, 54), (1536, 72), (1555, 132),
         (1565, 280), (1435, 280), (1432, 180)],
    ):
        paint.polygon([(x - CROWN_BOX[0], y) for x, y in points], fill=255)
    paint.rectangle((0, 0, 840 - CROWN_BOX[0], source.height), fill=255)
    paint.rectangle((1590 - CROWN_BOX[0], 0, source.width, source.height), fill=255)
    foreground = foreground.filter(ImageFilter.GaussianBlur(7))
    for y in range(source.height):
        for x in range(source.width):
            rgb = source.getpixel((x, y))
            if not plant(rgb):
                continue
            gx = x + CROWN_BOX[0]
            # Remove the central sprout; keep foliage only at the branch tips.
            if 1230 < gx < 1400 and y < 115:
                continue
            color = mix(cool_dark(rgb), rgb, foreground.getpixel((x, y)) / 255)
            result.putpixel((x, y), (*color, 255))
    # Decontaminate and soften the outer sky boundary without a drawn stroke.
    old = result.copy()
    for y in range(1, source.height - 1):
        for x in range(1, source.width - 1):
            if old.getpixel((x, y))[3] == 0:
                continue
            if any(old.getpixel((x + dx, y + dy))[3] == 0
                   for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))):
                nearby = [old.getpixel((x + dx, y + dy))[:3]
                          for dx, dy in ((-3, 0), (3, 0), (0, -3), (0, 3))
                          if 0 <= x + dx < source.width and 0 <= y + dy < source.height
                          and old.getpixel((x + dx, y + dy))[3] == 255]
                if nearby:
                    color = tuple(round(sum(c[i] for c in nearby) / len(nearby)) for i in range(3))
                    result.putpixel((x, y), (*color, 200))
    return result


def crown_image(landscape: Image.Image, vine: Image.Image) -> Image.Image:
    crown = matte_crown(landscape)
    # Replace the exit zone (including the right-hand coin) with the clean
    # extracted rope. The wrap-over attachments above this zone stay painted.
    starts = (200, 242, 140)
    for center, start in zip(LOOPS, starts):
        # Source silhouette at the point where the wrap becomes a vertical rope.
        source_center = (900, 1195, 1498)[LOOPS.index(center)] - CROWN_BOX[0]
        for y in range(start, crown.height):
            blend = min(1., (y - start) / 38)
            target_center = round(source_center * (1 - blend) + center * blend)
            fade = max(0., min(1., (EXIT + 40 - y) / 40))
            # Keep the supporting bough outside the actual rope silhouette.
            for x in range(center - 70, center + 71):
                old = crown.getpixel((x, y))
                sx = x - target_center + vine.width // 2
                if 0 <= sx < vine.width:
                    fresh = vine.getpixel((sx, (y - EXIT) % vine.height))
                else:
                    fresh = (0, 0, 0, 0)
                # Blend premultiplied colors, so transparent padding cannot
                # darken the live vine or leave remnants of the source coin.
                oa, na = old[3] * (1 - blend), fresh[3] * blend
                alpha = oa + na
                rgb = tuple(round((old[i] * oa + fresh[i] * na) / alpha)
                            if alpha else 0 for i in range(3))
                crown.putpixel((x, y), (*rgb, round(alpha * fade)))
    # Below the bough only the three exit ropes remain. The game supplies the
    # continuous trunk behind the crown; its top portion here retains A's paint.
    for y in range(250, crown.height):
        for x in range(crown.width):
            if all(abs(x - c) > 75 for c in LOOPS):
                crown.putpixel((x, y), (0, 0, 0, 0))
    return crown


def font(size: int) -> ImageFont.ImageFont:
    for path in ("C:/Windows/Fonts/arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size=size)


def paste_tiles(canvas: Image.Image, tile: Image.Image, center: int, top: int, count: int) -> None:
    for i in range(count):
        canvas.alpha_composite(tile, (center - tile.width // 2, top + i * tile.height))


def preview(vine: Image.Image, trunk: Image.Image, crown: Image.Image, reference: Image.Image) -> Image.Image:
    board = Image.new("RGBA", (2400, 1300), SKY)
    draw = ImageDraw.Draw(board)
    for text, xy in (("A / vine x3", (30, 30)), ("B / trunk x3", (230, 30)),
                     ("C / world slice - 2x", (510, 30)), ("Approved A reference", (1710, 30))):
        draw.text(xy, text, font=font(24), fill="#173b39")
    paste_tiles(board, vine, 104, 110, 3)
    paste_tiles(board, trunk, 330, 110, 3)
    # Source pixels already equal 2x world units: body 128/192, lane gap 300.
    crown_x, crown_y = 500, 110
    middle = crown_x + LOOPS[1]
    paste_tiles(board, trunk, middle, crown_y, 3)
    for center in LOOPS:
        paste_tiles(board, vine, crown_x + center, crown_y + EXIT, 4)
    board.alpha_composite(crown, (crown_x, crown_y))
    ref = reference.convert("RGBA").resize((660, 297), RESAMPLE)
    board.alpha_composite(ref, (1710, 110))
    draw.text((1710, 440), "Vine: 64 / trunk: 96 world units\nLanes: -150 / 0 / +150\nCrown fade: 40 source pixels\nAsset preview only; gameplay not run", font=font(22), fill="#173b39", spacing=12)
    return board.convert("RGB")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    landscape = Image.open(DESIGN / "A-yatay.png").convert("RGB")
    portrait = Image.open(DESIGN / "A-dikey.png").convert("RGB")
    vine, start = vine_tile(portrait)
    trunk = trunk_tile(landscape)
    crown = crown_image(landscape, vine)
    ART.mkdir(parents=True, exist_ok=True)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    entries = {}
    recipes = {
        "vine_tile": {"file": "01-tasarim/dunya-v4/A-dikey.png", "crop_rect_xyxy": [175, 600, 320, 1150],
                      "rectified_period_rows": [start, start + PERIOD], "body_width_px": BODY, "period_px": PERIOD,
                      "operations": "sky matte; row rectification; edge color replacement; periodic boundary blend; 2px padding"},
        "trunk_tile": {"file": "01-tasarim/dunya-v4/A-yatay.png", "crop_rect_xyxy": [1100, 0, 1230, 80],
                       "body_width_px": 192, "operations": "row rectification; resize; cool/dark/desaturate; periodic blend; 2px padding"},
        "crown": {"file": "01-tasarim/dunya-v4/A-yatay.png", "crop_rect_xyxy": list(CROWN_BOX),
                  "loop_centers_x_px": list(LOOPS), "branch_y_px": 116, "trunk_center_x_px": 580,
                  "vine_exit_y_px": EXIT, "vine_fade_end_y_px": EXIT + 40,
                  "operations": "green extraction; central sprout removal; cool/dark bough; clean vine exits replace coin; 40px alpha fade"},
    }
    for name, im in (("vine_tile", vine), ("trunk_tile", trunk), ("crown", crown)):
        path = ART / f"{name}.png"
        im.save(path)
        recipe = recipes[name].copy()
        placement = {key: recipe.pop(key) for key in list(recipe)
                     if key.endswith("_px")}
        entries[name] = {"file": path.name, "size_px": list(im.size), "width_px": im.width,
                         "height_px": im.height, "sha256": sha(path), "source": recipe, **placement}
    board = preview(vine, trunk, crown, landscape)
    board.save(PREVIEW)
    # This is the single requested fast check: produce and reopen the board.
    with Image.open(PREVIEW) as saved:
        assert PREVIEW.is_file() and saved.size == (2400, 1300)
        preview_size = list(saved.size)
    manifest = {
        "schema_version": 1, "date": "2026-10-18", "generator": "tools/world_v4_textures.py",
        "provenance": "Pillow derivation of owner-selected A paintings; no new generated artwork; source rights unchanged",
        "license": "Derived from supplied project A images; no additional third-party license introduced",
        "sources": {name: {"size_px": list(im.size), "sha256": sha(DESIGN / name)}
                    for name, im in (("A-yatay.png", landscape), ("A-dikey.png", portrait))},
        **entries,
        "placement": {"pixels_per_world_unit": 2, "lane_centers_world": [-150, 0, 150],
                      "vine_body_width_world": 64, "trunk_body_width_world": 96,
                      "tile_origin": "top-left; silhouette starts at x=2", "crown_origin": "top-left",
                      "join": "draw trunk, then vines starting at crown y=260, then crown; match vine phase 0 there"},
        "preview": {"file": PREVIEW.relative_to(ROOT).as_posix(), "size_px": preview_size, "sha256": sha(PREVIEW)},
        "quick_check": {"preview_exists": True, "preview_size_px": preview_size},
        "known_limitations": ["Gameplay integration and runtime acceptance belong to the separate implementation brief.",
                              "Branch surface y=116 is the central placement anchor; the painted bough is curved.",
                              "Crown is cropped at the top as in A; intended for top-of-scene placement."],
    }
    (ART / "v4_manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"preview": str(PREVIEW), "exists": PREVIEW.is_file(), "size_px": preview_size,
                      "assets": {key: {"size_px": value["size_px"], "sha256": value["sha256"]}
                                 for key, value in entries.items()}}, indent=2))


if __name__ == "__main__":
    main()
