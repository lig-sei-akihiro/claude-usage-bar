#!/usr/bin/env python3
"""Mock the status item: tinted template glyph + '72%' on light & dark menu bars."""
import subprocess, os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.abspath(__file__))
GLYPH = os.path.join(ROOT, "scratchpad-glyph.png")
# render template at 2x menu-bar height (~18pt -> 36px)
subprocess.run(["rsvg-convert", "-h", "36", "-a",
                os.path.join(ROOT, "Assets/icon/MenuBar.svg"), "-o", GLYPH], check=True)
glyph = Image.open(GLYPH).convert("RGBA")
gw, gh = glyph.size
alpha = glyph.split()[3]

def font(sz):
    for p in ["/System/Library/Fonts/SFNSMono.ttf",
              "/System/Library/Fonts/Menlo.ttc",
              "/System/Library/Fonts/Supplemental/Arial.ttf"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()

def strip(bg, fg, label_col):
    W, H = 260, 52
    im = Image.new("RGBA", (W, H), bg)
    tinted = Image.new("RGBA", (gw, gh), fg)
    x, y = 24, (H - gh)//2
    im.paste(tinted, (x, y), alpha)               # tint via template alpha
    d = ImageDraw.Draw(im)
    d.text((x + gw + 12, H//2), "72%", font=font(26), fill=label_col, anchor="lm")
    return im

light = strip((246,246,246,255), (26,26,26,255), (30,30,30,255))
dark  = strip((42,42,42,255), (235,235,235,255), (235,235,235,255))
out = Image.new("RGBA", (260, 116), (255,255,255,0))
out.paste(light, (0, 0)); out.paste(dark, (0, 60))
out.save(os.path.join(ROOT, "scratchpad-menubar-mock.png"))
print("wrote scratchpad-menubar-mock.png", out.size)
