from PIL import Image, ImageDraw, ImageFont
import math

S, SS = 1024, 4
N = S * SS
FONT = "/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf"

def px(v): return v * SS

def arc(cx, cy, r, a0, a1, steps=64):
    return [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)))
            for a in [a0 + (a1 - a0) * i / steps for i in range(steps + 1)]]

def cup_body(top_y, bot_y, top_x0, top_x1, bot_x0, bot_x1, r):
    """Tapered cup with rounded bottom corners.

    Corner arcs begin where the sloped side actually sits at bot_y - r.
    Anchoring them to the bottom width instead leaves a visible notch.
    """
    t = (bot_y - r - top_y) / (bot_y - top_y)
    sx0 = top_x0 + (bot_x0 - top_x0) * t
    sx1 = top_x1 + (bot_x1 - top_x1) * t

    pts = [(top_x0, top_y), (top_x1, top_y), (sx1, bot_y - r)]
    pts += arc(sx1 - r, bot_y - r, r, 0, 90)
    pts += arc(sx0 + r, bot_y - r, r, 90, 180)
    return pts

def render(bg, cup, coin_fill, glyph, out):
    """`cup` is the cup body colour; the coin is `coin_fill` with a `glyph`
    dollar sign. Swapping those three is what turns the app icon into the
    light-background mark."""
    img = Image.new("RGB", (N, N), bg)
    d = ImageDraw.Draw(img)

    # Lid tab
    d.rounded_rectangle([px(474), px(196), px(550), px(238)], radius=px(14), fill=cup)
    # Lid
    d.rounded_rectangle([px(346), px(230), px(678), px(302)], radius=px(26), fill=cup)

    # Body, separated from the lid by a thin gap so the lid reads as a lid
    d.polygon(
        [(px(x), px(y)) for x, y in
         cup_body(top_y=316, bot_y=760, top_x0=364, top_x1=660,
                  bot_x0=418, bot_x1=606, r=38)],
        fill=cup,
    )

    cx, cy, r = px(512), px(524), px(108)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=coin_fill)

    font = ImageFont.truetype(FONT, px(150))
    b = d.textbbox((0, 0), "$", font=font)
    d.text((cx - (b[0] + b[2]) / 2, cy - (b[1] + b[3]) / 2), "$", font=font, fill=glyph)

    img.resize((S, S), Image.LANCZOS).save(out, "PNG")
    print("wrote", out)

CORAL = "#D85A30"

# iOS / Android app icon — coral ground, white cup
render(CORAL, "#FFFFFF", CORAL, "#FFFFFF", "AppIcon-1024.png")

# iOS dark appearance — deeper ground so it sits back on a dark Home Screen
render("#7A2E14", "#FFF4EE", "#7A2E14", "#FFF4EE", "AppIcon-1024-dark.png")

# iOS tinted — iOS applies its own hue, so ship luminance only
render("#3A3A38", "#F2F2F0", "#3A3A38", "#F2F2F0", "AppIcon-1024-tinted.png")

# Light background — favicon, web header. Inverted: coral cup on white.
render("#FFFFFF", CORAL, "#FFFFFF", CORAL, "Logo-light-1024.png")
