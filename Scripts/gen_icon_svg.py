#!/usr/bin/env python3
"""Generate the icon SVGs from a pixel-art sprite grid.

The Claude Code character is a chunky pixel creature: a coral rounded body,
two dark eyes, two little feet. We combine it with a pixel "usage meter"
(segmented bar, partly filled) to match the app (claude-usage-bar).

Outputs (into Assets/icon/):
  AppIcon.svg        the chosen theme (what make_icons.sh rasterizes)
  AppIcon-dark.svg   dark "terminal" squircle variant
  AppIcon-light.svg  light "cream" squircle variant

The menu-bar status-item glyph is NOT generated here — the app draws it live
(Clawd + a usage gauge that fills to the real percentage) in ClawdGlyph.swift.
The sprite below is mirrored there; keep the two in sync if the character changes.

Edit the SPRITE grid / colours here, then run Scripts/make_icons.sh.
"""
from pathlib import Path

# --- sprite: '.' transparent, 'B' body (coral), 'E' eye (dark) ---------------
SPRITE = [
    ".BBBBBBBBBBB.",
    "BBBBBBBBBBBBB",
    "BBBEEBBBEEBBB",
    "BBBEEBBBEEBBB",
    "BBBEEBBBEEBBB",
    "BBBBBBBBBBBBB",
    "BBBBBBBBBBBBB",
    "BBBBBBBBBBBBB",
    "BBBBBBBBBBBBB",
    "..BB.....BB..",
    "..BB.....BB..",
]
COLS = len(SPRITE[0])
ROWS = len(SPRITE)

# --- palette -----------------------------------------------------------------
BODY = "#C1714E"   # terracotta / coral
EYE = "#2A201B"    # dark warm brown
METER_FILL = "#E08A63"

THEMES = {
    "dark":  {"bg_top": "#302B26", "bg_bot": "#191512", "meter_empty": "#FFFFFF", "meter_empty_op": 0.22},
    "light": {"bg_top": "#F5EEE4", "bg_bot": "#E7D3C0", "meter_empty": "#3A2A20", "meter_empty_op": 0.22},
}

CANVAS = 1024
INSET = 100
BODY_SIZE = CANVAS - 2 * INSET   # 824
RADIUS = 185


def sprite_rects(x0, y0, px, body_fill, eye_fill=None, skip_eyes=False):
    """Emit <rect> for each sprite cell. If skip_eyes, eye cells are left
    transparent (used for the monochrome template so eyes read as holes)."""
    out = []
    for r, row in enumerate(SPRITE):
        for c, ch in enumerate(row):
            if ch == ".":
                continue
            x = x0 + c * px
            y = y0 + r * px
            if ch == "E":
                if skip_eyes:
                    continue
                fill = eye_fill
            else:
                fill = body_fill
            # +0.5 overlap kills hairline seams between cells when rasterized
            out.append(
                f'<rect x="{x:.2f}" y="{y:.2f}" width="{px+0.5:.2f}" '
                f'height="{px+0.5:.2f}" fill="{fill}"/>'
            )
    return "\n  ".join(out)


def meter(cx_center, y, total_w, height, segments=5, filled=3, fill=METER_FILL,
          empty="#FFFFFF", empty_op=0.14):
    gap = 16
    seg_w = (total_w - gap * (segments - 1)) / segments
    x = cx_center - total_w / 2
    out = []
    for i in range(segments):
        sx = x + i * (seg_w + gap)
        if i < filled:
            out.append(f'<rect x="{sx:.2f}" y="{y}" width="{seg_w:.2f}" '
                       f'height="{height}" rx="7" fill="{fill}"/>')
        else:
            out.append(f'<rect x="{sx:.2f}" y="{y}" width="{seg_w:.2f}" '
                       f'height="{height}" rx="7" fill="{empty}" '
                       f'fill-opacity="{empty_op}"/>')
    return "\n  ".join(out)


def build_app_svg(theme_name):
    t = THEMES[theme_name]
    px = 40
    sprite_w = COLS * px          # 520
    sprite_h = ROWS * px          # 440
    gap = 40
    meter_h = 54
    group_h = sprite_h + gap + meter_h
    group_top = CANVAS / 2 - group_h / 2
    x0 = (CANVAS - sprite_w) / 2
    y0 = group_top
    meter_y = y0 + sprite_h + gap
    cells = sprite_rects(x0, y0, px, BODY, EYE)
    bars = meter(CANVAS / 2, meter_y, sprite_w, meter_h, segments=5, filled=3,
                 empty=t["meter_empty"], empty_op=t["meter_empty_op"])
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}" shape-rendering="crispEdges">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{t['bg_top']}"/>
      <stop offset="1" stop-color="{t['bg_bot']}"/>
    </linearGradient>
  </defs>
  <rect x="{INSET}" y="{INSET}" width="{BODY_SIZE}" height="{BODY_SIZE}" rx="{RADIUS}" fill="url(#bg)"/>
  {cells}
  {bars}
</svg>
'''


def main():
    out = Path(__file__).resolve().parent.parent / "Assets" / "icon"
    out.mkdir(parents=True, exist_ok=True)
    dark = build_app_svg("dark")
    light = build_app_svg("light")
    (out / "AppIcon-dark.svg").write_text(dark)
    (out / "AppIcon-light.svg").write_text(light)
    (out / "AppIcon.svg").write_text(dark)   # default; swap after review
    print("wrote AppIcon.svg (=dark), AppIcon-dark.svg, AppIcon-light.svg")


if __name__ == "__main__":
    main()
