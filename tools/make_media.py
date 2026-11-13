"""Draws the addon's textures (white shapes on transparent, tinted in game).

Run from the repo root: python3 tools/make_media.py
Writes 64x64 32-bit TGA files to Forever21/Media/.
"""
from PIL import Image, ImageDraw

S = 256  # draw large, then shrink for smooth edges
OUT = 64
WHITE = (255, 255, 255, 255)


def save(img, name):
    img.resize((OUT, OUT), Image.LANCZOS).save(f"Forever21/Media/{name}.tga", rle=False)


def canvas():
    img = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    return img, ImageDraw.Draw(img)


def heart(d, flip=False):
    r = 58
    pts_y = lambda y: S - y if flip else y
    cy = 92
    for cx in (S / 2 - 52, S / 2 + 52):
        y0, y1 = sorted((pts_y(cy - r), pts_y(cy + r)))
        d.ellipse([cx - r, y0, cx + r, y1], fill=WHITE)
    d.polygon([(S / 2 - 108, pts_y(112)), (S / 2 + 108, pts_y(112)), (S / 2, pts_y(232))], fill=WHITE)


img, d = canvas()
heart(d)
save(img, "SuitHeart")

img, d = canvas()
d.polygon([(S / 2, 16), (S - 44, S / 2), (S / 2, S - 16), (44, S / 2)], fill=WHITE)
save(img, "SuitDiamond")

img, d = canvas()
heart(d, flip=True)  # an upside-down heart, shifted up, plus a stem
img = img.transform(img.size, Image.AFFINE, (1, 0, 0, 0, 1, 26))
d = ImageDraw.Draw(img)
d.polygon([(S / 2, 150), (S / 2 - 46, 244), (S / 2 + 46, 244)], fill=WHITE)
save(img, "SuitSpade")

img, d = canvas()
r = 50
for cx, cy in ((S / 2, 70), (S / 2 - 58, 142), (S / 2 + 58, 142)):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=WHITE)
d.rectangle([S / 2 - 22, 100, S / 2 + 22, 170], fill=WHITE)
d.polygon([(S / 2, 140), (S / 2 - 46, 244), (S / 2 + 46, 244)], fill=WHITE)
save(img, "SuitClub")

# A poker chip: solid disc with a ring of notches, tinted per value in game.
img, d = canvas()
d.ellipse([8, 8, S - 8, S - 8], fill=WHITE)
d.ellipse([52, 52, S - 52, S - 52], fill=(200, 200, 200, 255))
d.ellipse([64, 64, S - 64, S - 64], fill=WHITE)
for i in range(8):
    import math
    a = i * math.pi / 4
    x, y = S / 2 + math.cos(a) * 100, S / 2 + math.sin(a) * 100
    d.ellipse([x - 14, y - 14, x + 14, y + 14], fill=(170, 170, 170, 255))
save(img, "Chip")

# A soft round spot for the bet circle.
img, d = canvas()
d.ellipse([8, 8, S - 8, S - 8], outline=WHITE, width=14)
save(img, "Ring")
