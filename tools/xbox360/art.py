#!/usr/bin/env python3
"""The Xbox 360 version's art: box art, dashboard background, tile, icon and wordmark.

Everything here is drawn from scratch: gradients, blurred nebula blooms, a seeded star field, a faceted golden star
mark and a title set from a system font. No Nintendo artwork, logo or character is used or traced -- the palette and the
idea (space, a small golden star, deep blue) are the port's own, the same ones as assets/nebula-smg.svg.

    tools/xbox360/art.py                 # writes assets/xbox360/
    tools/xbox360/art.py --out DIR       # somewhere else
    tools/xbox360/art.py --seed 7        # another star field, same art

Sizes are the ones an Xbox 360 dashboard reads (Aurora / Freestyle / NXE):

    boxart.png       584x700   the cover
    background.png  1280x720   the title's dashboard background
    tile.png         219x300   the small tile beside the title in a list
    icon.png         100x100   the title's icon
    icon-64.png       64x64    the dashboard's own icon slot
    banner.png      1000x250   a wide header for a list view
    splash.png      1280x720   the title screen
    disc.png        1418x1418  a 12 cm disc label at 300 dpi
    wordmark.png    900x292    the title lockup, transparent
"""

from __future__ import annotations

import argparse
import json
import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

# ---- the palette (assets/nebula-smg.svg) ---------------------------------------------------------------------------

SKY_TOP = (18, 10, 51)
SKY_MID = (29, 11, 69)
SKY_BOTTOM = (7, 3, 15)
PURPLE = (179, 75, 255)
VIOLET = (122, 47, 242)
PINK = (255, 79, 163)
CYAN = (57, 215, 255)
GOLD_LIGHT = (255, 246, 196)
GOLD = (255, 212, 71)
AMBER = (255, 157, 28)
WHITE = (245, 248, 255)

FONT_CANDIDATES = (
    "/usr/share/fonts/google-noto/NotoSans-CondensedBlack.ttf",
    "/usr/share/fonts/open-sans/OpenSans-ExtraBold.ttf",
    "/usr/share/fonts/liberation-sans-fonts/LiberationSans-Bold.ttf",
    "/usr/share/fonts/abattis-cantarell-fonts/Cantarell-Bold.otf",
)


def font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size)


# ---- pieces -------------------------------------------------------------------------------------------------------


def sky(size: tuple[int, int], seed: int) -> Image.Image:
    """The vertical gradient the whole picture stands on, with a faint banding-free dither."""
    width, height = size
    image = Image.new("RGB", size)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / max(1, height - 1)
        if t < 0.55:
            k = t / 0.55
            colour = tuple(round(a + (b - a) * k) for a, b in zip(SKY_TOP, SKY_MID))
        else:
            k = (t - 0.55) / 0.45
            colour = tuple(round(a + (b - a) * k) for a, b in zip(SKY_MID, SKY_BOTTOM))
        draw.line([(0, y), (width, y)], fill=colour)
    # A 1/255 of noise kills the banding a gradient shows on a 720p panel at 8 bits a channel.
    rng = random.Random(seed ^ 0x5EED)
    noise = Image.new("L", size)
    noise.putdata([rng.randint(0, 2) for _ in range(width * height)])
    return ImageChops.add(image, Image.merge("RGB", (noise, noise, noise)))


def bloom(size: tuple[int, int], centre: tuple[float, float], radius: float, colour: tuple[int, int, int],
          strength: float) -> Image.Image:
    """One nebula cloud: a soft radial falloff of `colour` at `strength` opacity, as its own layer."""
    width, height = size
    layer = Image.new("L", size, 0)
    draw = ImageDraw.Draw(layer)
    steps = 26
    for i in range(steps, 0, -1):
        k = i / steps
        r = radius * k
        alpha = round(255 * strength * (1.0 - k) ** 2.1)
        draw.ellipse([centre[0] - r, centre[1] - r * 0.86, centre[0] + r, centre[1] + r * 0.86], fill=alpha)
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.16))
    tinted = Image.new("RGB", size, colour)
    return tinted, layer


def paste_bloom(image: Image.Image, centre, radius, colour, strength) -> None:
    tinted, layer = bloom(image.size, centre, radius, colour, strength)
    image.paste(tinted, (0, 0), layer)


def star_field(size: tuple[int, int], seed: int, count: int) -> Image.Image:
    """Points of light: mostly faint, a few bright, in the picture's own size."""
    width, height = size
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    rng = random.Random(seed)
    for _ in range(count):
        x = rng.uniform(0, width)
        y = rng.uniform(0, height)
        # Three quarters of the field is a single pixel of dim light; the rest steps up to a soft glow.
        roll = rng.random()
        if roll < 0.72:
            value = rng.randint(70, 150)
            draw.point((x, y), fill=(value, value, min(255, value + 30), 200))
            continue
        radius = rng.uniform(0.7, 2.0) * (width / 720.0)
        value = rng.randint(170, 255)
        draw.ellipse([x - radius, y - radius, x + radius, y + radius],
                     fill=(value, value, min(255, value + 20), rng.randint(190, 255)))
    return layer.filter(ImageFilter.GaussianBlur(0.6 * (width / 720.0)))


def sparkle(size: tuple[int, int], centre: tuple[float, float], arm: float, colour, seed: int = 0) -> Image.Image:
    """A four-point star: two crossed needles with a hot core, the way a bright star photographs."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    x, y = centre
    core = max(1.4, arm * 0.10)
    for length, width_, alpha in ((arm, max(0.8, arm * 0.030), 90), (arm * 0.62, max(1.0, arm * 0.055), 150),
                                  (arm * 0.34, max(1.2, arm * 0.085), 220)):
        horizontal = [x - length, y - width_, x + length, y + width_]
        vertical = [x - width_, y - length, x + width_, y + length]
        draw.ellipse(horizontal, fill=colour + (alpha,))
        draw.ellipse(vertical, fill=colour + (alpha,))
    draw.ellipse([x - core * 2.2, y - core * 2.2, x + core * 2.2, y + core * 2.2], fill=WHITE + (255,))
    return layer.filter(ImageFilter.GaussianBlur(max(0.5, arm * 0.012)))


def star_mark(size: int, arms: int = 5) -> Image.Image:
    """The port's mark: a faceted golden star with a bright core, drawn as polygons -- no character, no face.

    A five-pointed star whose points are cut into facets by a lighter plane down the middle, so it reads as a solid
    object lit from the upper left rather than a flat sticker.
    """
    scale = 4
    side = size * scale
    image = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    centre = side / 2.0
    outer = side * 0.47
    inner = outer * 0.44
    points = []
    for i in range(arms * 2):
        angle = -math.pi / 2.0 + i * math.pi / arms
        radius = outer if i % 2 == 0 else inner
        points.append((centre + math.cos(angle) * radius, centre + math.sin(angle) * radius))
    draw.polygon(points, fill=GOLD_LIGHT + (255,))
    # The lit half: the same star clipped to the upper-left of the vertical axis and filled with the light gold.
    lit = Image.new("L", (side, side), 0)
    ImageDraw.Draw(lit).polygon(points, fill=255)
    left = Image.new("L", (side, side), 0)
    ImageDraw.Draw(left).polygon(points, fill=200)
    ImageDraw.Draw(left).polygon(
        [(centre, centre - outer * 1.2), (centre + outer * 1.2, centre + outer * 1.2),
         (centre, centre + outer * 1.2)], fill=0)
    lit = ImageChops.subtract(lit, left)
    gradient = Image.new("RGBA", (side, side), AMBER + (255,))
    highlight = Image.new("RGBA", (side, side), GOLD + (255,))
    mask = ImageChops.multiply(lit, Image.new("L", (side, side), 255))
    gradient.paste(highlight, (0, 0), mask.filter(ImageFilter.GaussianBlur(side * 0.10)))
    image.alpha_composite(gradient)
    # The core: a hot spot where the light gathers.
    core = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    cd = ImageDraw.Draw(core)
    for r, a in ((side * 0.20, 70), (side * 0.11, 140), (side * 0.05, 235)):
        cd.ellipse([centre - r, centre - r, centre + r, centre + r], fill=WHITE + (a,))
    image.alpha_composite(core.filter(ImageFilter.GaussianBlur(side * 0.03)))
    # A dark rim keeps the star readable on the gold-lit sky.
    outline = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    ImageDraw.Draw(outline).line(points + [points[0]], fill=(60, 26, 4, 150), width=max(1, side // 90))
    image.alpha_composite(outline)
    return image.resize((size, size), Image.LANCZOS)


def planet(size: tuple[int, int], centre: tuple[float, float], radius: float,
           body: tuple[int, int, int], band: tuple[int, int, int], alpha: int = 255) -> Image.Image:
    """A gas giant's limb, banded and lit from the upper left -- the arc along the bottom of the cover."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    x, y = centre
    ball = Image.new("RGBA", (int(radius * 2) + 2, int(radius * 2) + 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(ball)
    draw.ellipse([1, 1, radius * 2, radius * 2], fill=body + (alpha,))
    bands = Image.new("RGBA", ball.size, (0, 0, 0, 0))
    bd = ImageDraw.Draw(bands)
    for i in range(14):
        t = i / 14.0
        top = 1 + t * radius * 2
        height = radius * 2 / 14.0 * 0.75
        shade = tuple(round(a + (b - a) * (0.35 + 0.5 * math.sin(t * 7.0))) for a, b in zip(body, band))
        bd.rectangle([1, top, radius * 2, top + height], fill=shade + (110,))
    ball.alpha_composite(bands.filter(ImageFilter.GaussianBlur(radius * 0.02)))
    # The terminator: unlit at the lower right.
    shadow = Image.new("L", ball.size, 0)
    sd = ImageDraw.Draw(shadow)
    sd.ellipse([radius * 0.35, radius * 0.35, radius * 2.4, radius * 2.4], fill=255)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius * 0.10))
    dark = Image.new("RGBA", ball.size, (2, 1, 8, 215))
    ball.paste(dark, (0, 0), shadow)
    # Rim light along the upper-left limb.
    rim = Image.new("RGBA", ball.size, (0, 0, 0, 0))
    ImageDraw.Draw(rim).arc([1, 1, radius * 2, radius * 2], 150, 330, fill=CYAN + (120,),
                            width=max(2, int(radius * 0.02)))
    ball.alpha_composite(rim.filter(ImageFilter.GaussianBlur(radius * 0.01)))
    layer.alpha_composite(ball, (int(x - radius), int(y - radius)))
    return layer


# ---- type ---------------------------------------------------------------------------------------------------------


def tracked_text(draw: ImageDraw.ImageDraw, xy, text: str, fnt, fill, tracking: float = 0.0) -> tuple[int, int]:
    """`text` with letter spacing, left-aligned at `xy`; returns the drawn width and height."""
    x, y = xy
    for letter in text:
        draw.text((x, y), letter, font=fnt, fill=fill)
        x += draw.textlength(letter, font=fnt) + tracking
    box = draw.textbbox((0, 0), text, font=fnt)
    return round(x - xy[0]), box[3] - box[1]


def wordmark(width: int, lines: list[tuple[str, int]], tracking: float = 0.14, plate: str | None = None,
             padding: int = 46) -> Image.Image:
    """The title lockup, transparent and cropped to its ink: stacked lines in a gold gradient, a violet halo behind,
    a thin rule and an optional plate under them. The width is the image's; the height follows from the type."""
    scratch = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    measure = ImageDraw.Draw(scratch)

    def advance(text: str, fnt) -> float:
        return sum(measure.textlength(c, font=fnt) for c in text) + tracking * fnt.size * len(text)

    rows: list[tuple[str, ImageFont.FreeTypeFont, int, int]] = []  # text, font, ink width, top
    cursor = padding
    for text, size_px in lines:
        fnt = font(size_px)
        box = fnt.getbbox(text)
        rows.append((text, fnt, round(advance(text, fnt)), cursor - box[1]))
        cursor += round((box[3] - box[1]) * 1.16)
    plate_font = font(max(14, lines[-1][1] // 3))
    plate_top = cursor + round(lines[-1][1] * 0.10)
    rule_y = plate_top - round(lines[-1][1] * 0.26)
    plate_width = round(advance(plate, plate_font)) if plate is not None else 0
    height = (plate_top + round(plate_font.size * 1.5) if plate is not None else cursor) + padding

    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    mask = Image.new("L", (width, height), 0)
    mdraw = ImageDraw.Draw(mask)
    for text, fnt, ink, top in rows:
        tracked_text(mdraw, ((width - ink) / 2, top), text, fnt, 255, tracking * fnt.size)
    if plate is not None:
        tracked_text(mdraw, ((width - plate_width) / 2, plate_top), plate, plate_font, 255, tracking * plate_font.size)

    ink = mask.getbbox()
    if ink is None:
        return image

    # The glass: a gold gradient across the letters' own extent, clipped by the mask.
    gradient = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(gradient)
    top, bottom = ink[1], ink[3]
    for y in range(top, bottom + 1):
        t = (y - top) / max(1, bottom - top)
        if t < 0.42:
            colour = tuple(round(a + (b - a) * (t / 0.42)) for a, b in zip(WHITE, GOLD_LIGHT))
        elif t < 0.78:
            colour = tuple(round(a + (b - a) * ((t - 0.42) / 0.36)) for a, b in zip(GOLD_LIGHT, GOLD))
        else:
            colour = tuple(round(a + (b - a) * ((t - 0.78) / 0.22)) for a, b in zip(GOLD, AMBER))
        gdraw.line([(0, y), (width, y)], fill=colour + (255,))
    gold = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    gold.paste(gradient, (0, 0), mask)

    # The bevel: the letters again, dropped two pixels, in near-black.
    drop = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ddraw = ImageDraw.Draw(drop)
    for text, fnt, ink_w, line_top in rows:
        tracked_text(ddraw, ((width - ink_w) / 2, line_top + max(2, fnt.size // 24)), text, fnt,
                     (34, 12, 2, 200), tracking * fnt.size)
    if plate is not None:
        ddraw.text(((width - plate_width) / 2, plate_top + 2), plate, font=plate_font, fill=(0, 0, 0, 170))

    # The halo: violet then cyan, under everything.
    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    halo = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    halo.paste(PURPLE + (160,), (0, 0), mask.filter(ImageFilter.GaussianBlur(max(5, lines[0][1] // 9))))
    halo.paste(CYAN + (80,), (0, 0), mask.filter(ImageFilter.GaussianBlur(max(9, lines[0][1] // 5))))
    out.alpha_composite(halo)
    out.alpha_composite(drop.filter(ImageFilter.GaussianBlur(max(1, lines[0][1] // 48))))
    if plate is not None:
        rd = ImageDraw.Draw(out)
        inset = width // 14
        rd.line([(inset, rule_y), (width - inset, rule_y)], fill=GOLD + (120,), width=2)
        tracked_text(rd, ((width - plate_width) / 2, plate_top), plate, plate_font, (226, 232, 255, 235),
                     tracking * plate_font.size)
    out.alpha_composite(gold)
    return out.crop((0, max(0, ink[1] - padding // 2), width, min(height, ink[3] + padding // 2)))


def badge(size: tuple[int, int], label: str, sub: str) -> Image.Image:
    """The little plate at the bottom of the cover: the platform and what the build is."""
    width, height = size
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle([0, 0, width - 1, height - 1], radius=height // 4,
                           fill=(9, 5, 22, 190), outline=CYAN + (120,), width=2)
    f1 = font(max(12, height // 2 - 2))
    f2 = font(max(10, height // 3))
    text_w = sum(draw.textlength(c, font=f1) for c in label)
    x = (width - text_w) / 2
    y = height * 0.10
    for letter in label:
        draw.text((x, y), letter, font=f1, fill=WHITE + (255,))
        x += draw.textlength(letter, font=f1) + height * 0.06
    sub_w = sum(draw.textlength(c, font=f2) for c in sub)
    x = (width - sub_w) / 2
    for letter in sub:
        draw.text((x, height * 0.58), letter, font=f2, fill=CYAN + (230,))
        x += draw.textlength(letter, font=f2) + height * 0.05
    return image


def stars_on(image: Image.Image, seed: int, density: float = 1.0, big: int = 3) -> None:
    """The field plus the handful of needles a night sky has, all above the blooms."""
    width, height = image.size
    field = star_field((width, height), seed, round(width * height / 2600 * density))
    image.alpha_composite(field) if image.mode == "RGBA" else image.paste(field, (0, 0), field)
    rng = random.Random(seed + 991)
    for _ in range(big):
        centre = (rng.uniform(width * 0.08, width * 0.92), rng.uniform(height * 0.06, height * 0.55))
        arm = rng.uniform(width, width * 2.2) * 0.045
        spark = sparkle((width, height), centre, arm, rng.choice([WHITE, GOLD_LIGHT, CYAN]))
        if image.mode == "RGBA":
            image.alpha_composite(spark)
        else:
            image.paste(spark, (0, 0), spark)


def galaxy_picture(size: tuple[int, int], seed: int, horizon: float = 0.86) -> Image.Image:
    """The shared scene: sky, three blooms, a star field, a star mark and a planet's limb. `horizon` is where the planet
    cuts in, 1.0 for none."""
    width, height = size
    image = sky(size, seed).convert("RGBA")
    rng = random.Random(seed)
    paste_bloom(image, (width * rng.uniform(0.18, 0.34), height * rng.uniform(0.20, 0.34)),
                width * rng.uniform(0.45, 0.60), PINK, 0.24)
    paste_bloom(image, (width * rng.uniform(0.62, 0.82), height * rng.uniform(0.10, 0.26)),
                width * rng.uniform(0.40, 0.58), VIOLET, 0.40)
    paste_bloom(image, (width * rng.uniform(0.40, 0.60), height * rng.uniform(0.42, 0.60)),
                width * rng.uniform(0.50, 0.70), PURPLE, 0.28)
    paste_bloom(image, (width * 0.86, height * 0.78), width * 0.34, CYAN, 0.18)
    stars_on(image, seed, 1.0, 3)
    if horizon < 1.0:
        radius = width * 0.78
        limb = planet(size, (width * 0.52, height * horizon + radius * 0.62), radius,
                      (28, 32, 86), (86, 58, 140))
        image.alpha_composite(limb)
        # The atmosphere along the top of the limb.
        glow = Image.new("RGBA", size, (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.ellipse([width * 0.52 - radius, height * horizon + radius * 0.62 - radius,
                    width * 0.52 + radius, height * horizon + radius * 0.62 + radius],
                   outline=CYAN + (110,), width=max(2, int(width * 0.006)))
        image.alpha_composite(glow.filter(ImageFilter.GaussianBlur(width * 0.012)))
    return image


# ---- the plates ---------------------------------------------------------------------------------------------------


def draw_boxart(seed: int) -> Image.Image:
    width, height = 584, 700
    image = galaxy_picture((width, height), seed, horizon=0.82)
    mark = star_mark(round(width * 0.38))
    image.alpha_composite(mark, ((width - mark.width) // 2, round(height * 0.045)))
    # The title sits in the lower half, over the dark limb, with the platform plate clear of its tail.
    title = wordmark(width - 40, [("SUPER", 78), ("MARIO", 78), ("GALAXY", 86)],
                     tracking=0.09, plate="N E B U L A   E D I T I O N")
    plate = badge((round(width * 0.58), 58), "XBOX 360", "720P 60  -  512 MB")
    tail = plate.height + 26
    image.alpha_composite(title, ((width - title.width) // 2, height - tail - title.height))
    image.alpha_composite(plate, ((width - plate.width) // 2, height - tail + 4))
    return image.convert("RGB")


def draw_background(seed: int) -> Image.Image:
    width, height = 1280, 720
    image = galaxy_picture((width, height), seed, horizon=1.0)
    # The right side is the art; the left is where the dashboard puts its text and the eye needs quiet.
    shade = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for x in range(0, width // 2):
        alpha = round(150 * (1.0 - x / (width / 2)) ** 1.4)
        sd.line([(x, 0), (x, height)], fill=(4, 2, 12, alpha))
    image.alpha_composite(shade)
    mark = star_mark(300)
    image.alpha_composite(mark, (round(width * 0.62), round(height * 0.16)))
    title = wordmark(660, [("SUPER MARIO", 62), ("GALAXY", 116)], tracking=0.05,
                     plate="N E B U L A   E D I T I O N")
    image.alpha_composite(title, (56, round(height * 0.26)))
    plate = badge((300, 66), "XBOX 360", "720P 60  -  RGH / JTAG")
    image.alpha_composite(plate, (60, height - 120))
    return image.convert("RGB")


def draw_tile(seed: int) -> Image.Image:
    width, height = 219, 300
    image = galaxy_picture((width, height), seed, horizon=0.96)
    mark = star_mark(round(width * 0.46))
    image.alpha_composite(mark, (round(width * 0.27), round(height * 0.04)))
    title = wordmark(width - 24, [("SUPER", 34), ("MARIO", 34), ("GALAXY", 38)], tracking=0.04)
    image.alpha_composite(title, ((width - title.width) // 2, round(height * 0.52)))
    return image.convert("RGB")


def draw_banner(seed: int) -> Image.Image:
    width, height = 1000, 250
    image = galaxy_picture((width, height), seed, horizon=1.0)
    mark = star_mark(170)
    image.alpha_composite(mark, (width - 240, 40))
    title = wordmark(600, [("SUPER MARIO", 40), ("GALAXY", 74)], tracking=0.05,
                     plate="N E B U L A   E D I T I O N")
    image.alpha_composite(title, (48, round((height - title.height) / 2)))
    return image.convert("RGB")


def draw_splash(seed: int) -> Image.Image:
    """The title screen: the same scene, the title centred, room under it for the game's own prompt."""
    width, height = 1280, 720
    image = galaxy_picture((width, height), seed, horizon=0.86)
    mark = star_mark(240)
    image.alpha_composite(mark, ((width - mark.width) // 2, round(height * 0.06)))
    title = wordmark(760, [("SUPER", 62), ("MARIO", 62), ("GALAXY", 96)], tracking=0.09,
                     plate="N E B U L A   E D I T I O N")
    image.alpha_composite(title, ((width - title.width) // 2, round(height * 0.42)))
    return image.convert("RGB")


def draw_disc(seed: int) -> Image.Image:
    """The label for a 12 cm disc at 300 dpi: the mark, the title's arc and the platform plate, inside the ring a drive
    reads by hand."""
    size = 1418
    image = galaxy_picture((size, size), seed, horizon=1.0)
    # The hub: nothing prints inside the disc's centre hole or on the ring around it.
    draw = ImageDraw.Draw(image)
    centre = size / 2.0
    for radius, colour in ((size * 0.125, (6, 3, 14, 255)), (size * 0.145, (10, 6, 24, 255))):
        draw.ellipse([centre - radius, centre - radius, centre + radius, centre + radius], fill=colour)
    mark = star_mark(round(size * 0.34))
    image.alpha_composite(mark, (round(centre - mark.width / 2), round(centre - mark.height / 2)))
    title = wordmark(round(size * 0.62), [("SUPER MARIO", 58), ("GALAXY", 92)], tracking=0.06,
                     plate="N E B U L A   E D I T I O N")
    image.alpha_composite(title, (round(centre - title.width / 2), round(size * 0.10)))
    plate = badge((round(size * 0.34), 66), "XBOX 360", "RGH / JTAG  -  720P")
    image.alpha_composite(plate, (round(centre - plate.width / 2), round(size * 0.84)))
    return image.convert("RGB")


def draw_icon(seed: int, size: int) -> Image.Image:
    image = galaxy_picture((size, size), seed, horizon=1.0)
    mark = star_mark(round(size * 0.74))
    image.alpha_composite(mark, ((size - mark.width) // 2, (size - mark.height) // 2))
    return image.convert("RGB")


def write_manifest(out: Path, files: dict[str, dict]) -> None:
    manifest = {
        "name": "Super Mario Galaxy - Nebula Edition (Xbox 360)",
        "title_id": "4E4E4542",
        "media_id": "4E4542554C41",
        "generated_by": "tools/xbox360/art.py",
        "files": files,
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default=str(Path(__file__).resolve().parents[2] / "assets" / "xbox360"))
    parser.add_argument("--seed", type=int, default=360)
    args = parser.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    seed = args.seed

    plates: dict[str, tuple[Image.Image, str]] = {
        "boxart.png": (draw_boxart(seed), "584x700, the cover"),
        "background.png": (draw_background(seed + 1), "1280x720, the dashboard background"),
        "tile.png": (draw_tile(seed + 2), "219x300, the list tile"),
        "banner.png": (draw_banner(seed + 3), "1000x250, a wide header"),
        "icon.png": (draw_icon(seed + 4, 100), "100x100, the title icon"),
        "icon-64.png": (draw_icon(seed + 4, 64), "64x64, the dashboard's icon slot"),
        "splash.png": (draw_splash(seed + 5), "1280x720, the title screen"),
        "disc.png": (draw_disc(seed + 6), "1418x1418, a 12 cm disc label at 300 dpi"),
    }
    files: dict[str, dict] = {}
    for name, (image, note) in plates.items():
        image.save(out / name, optimize=True)
        files[name] = {"size": list(image.size), "note": note}

    mark = wordmark(900, [("SUPER MARIO", 86), ("GALAXY", 132)], tracking=0.05,
                    plate="N E B U L A   E D I T I O N")
    mark.save(out / "wordmark.png", optimize=True)
    files["wordmark.png"] = {"size": list(mark.size), "note": "the title lockup, transparent"}

    write_manifest(out, files)
    for name, meta in files.items():
        print(f"{name:18} {meta['size'][0]:>4}x{meta['size'][1]:<4} {meta['note']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
