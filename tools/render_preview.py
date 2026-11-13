"""Draws the JSON layouts from tools/preview.lua into PNGs (approximate look)."""
import json, sys, glob, os
from PIL import Image, ImageDraw, ImageFont

out = sys.argv[1]
SCALE = 2
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SIZES = {"GameFontNormal": 12, "GameFontNormalSmall": 10, "GameFontNormalLarge": 16,
         "GameFontHighlight": 12, "GameFontHighlightSmall": 10, "GameFontDisableSmall": 10}
import re

def col(c, a=1.0):
    return tuple(int(max(0, min(1, x)) * 255) for x in c[:3]) + (int(a * 255),)

for path in sorted(glob.glob(os.path.join(out, "*.json"))):
    items = json.load(open(path))
    # crop to the window: the first item is the wood background
    x0, y0, w0, h0 = items[0]["rect"]
    H = 800
    img = Image.new("RGBA", (int(w0 * SCALE), int(h0 * SCALE)), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    def box(rect):
        l, b, w, h = rect
        return [(l - x0) * SCALE, (y0 + h0 - (b + h)) * SCALE, (l - x0 + w) * SCALE, (y0 + h0 - b) * SCALE]
    for it in items:
        r = box(it["rect"])
        if it.get("button"):
            en = it.get("enabled", True)
            d.rounded_rectangle(r, radius=6, fill=(120, 16, 10, 255) if en else (70, 50, 50, 255), outline=(30, 10, 5, 255), width=2)
        elif it.get("close"):
            d.rounded_rectangle(r, radius=6, fill=(140, 20, 10, 255))
            d.text(((r[0] + r[2]) / 2, (r[1] + r[3]) / 2), "X", font=ImageFont.truetype(FONT, 22), fill="white", anchor="mm")
        elif it["kind"] == "Texture":
            if it.get("fill"):
                f = it["fill"]
                layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
                ImageDraw.Draw(layer).rectangle(r, fill=col(f, f[3]))
                img.alpha_composite(layer)
            elif it.get("path"):
                name = it["path"].split("\\")[-1]
                src = f"Forever21/Media/{name}.tga"
                if os.path.exists(src):
                    t = Image.open(src).convert("RGBA").resize((max(1, int(r[2] - r[0])), max(1, int(r[3] - r[1]))))
                    tint = it.get("tint") or [1, 1, 1, 1]
                    px = t.load()
                    for yy in range(t.height):
                        for xx in range(t.width):
                            p = px[xx, yy]
                            px[xx, yy] = (int(p[0] * tint[0]), int(p[1] * tint[1]), int(p[2] * tint[2]), int(p[3] * tint[3]))
                    img.alpha_composite(t, (int(r[0]), int(r[1])))
            d = ImageDraw.Draw(img)
        elif it["kind"] == "FontString" and it.get("text"):
            raw = it["text"]
            size = SIZES.get(it.get("font"), 12) * SCALE
            font = ImageFont.truetype(FONT, size)
            m = re.match(r"\|c(..)(..)(..)(..)(.*?)\|r(.*)", raw)
            color = col(it.get("color") or [1, 1, 1])
            if m:
                color = (int(m.group(2), 16), int(m.group(3), 16), int(m.group(4), 16), 255)
                raw = m.group(5) + m.group(6)
            d.text(((r[0] + r[2]) / 2, (r[1] + r[3]) / 2), raw, font=font, fill=color, anchor="mm")
    img.convert("RGB").save(path.replace(".json", ".png"))
    print("rendered", path.replace(".json", ".png"))
