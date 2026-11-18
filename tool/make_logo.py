#!/usr/bin/env python3
"""Membuat sumber logo (PNG 1024x1024) ke assets/branding/. Opsional: Anda bisa menimpa file PNG itu
dengan logo sendiri dan lewati skrip ini. Perlu Pillow:  pip install pillow
Logo asli: koin putih dengan panah naik; tanpa teks (nama aplikasi bebas diganti)."""
import math
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'branding')
S = 4096            # kanvas kerja (supersampling 4x)
N = 1024            # ukuran akhir
K = S / N
FG_SCALE = 1.65
TEAL = (15, 118, 110, 255)       # sama dengan warna aksen aplikasi (Tk.seed)
TOP, BOTTOM = (22, 148, 138), (10, 92, 86)


def px(v):
    return int(round(v * K))


def gradient():
    im = Image.new('RGB', (S, S))
    d = ImageDraw.Draw(im)
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))
    return im


def symbol(scale=1.0, coin=(255, 255, 255, 255), arrow=TEAL, cut_arrow=False):
    """Koin + panah naik, di tengah. Pada scale=1 diameter koin 540 dari 1024."""
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = 512
    r = 270 * scale
    d.ellipse([px(c - r), px(c - r), px(c + r), px(c + r)], fill=coin)
    pts = [(350, 620), (450, 520), (520, 585), (660, 440)]
    pts = [(c + (x - c) * scale, c + (y - c) * scale) for x, y in pts]
    w = px(54 * scale)
    layer = Image.new('L', (S, S), 0)
    ld = ImageDraw.Draw(layer)
    ld.line([(px(x), px(y)) for x, y in pts], fill=255, width=w, joint='curve')
    for x, y in pts:  # ujung bulat
        ld.ellipse([px(x) - w // 2, px(y) - w // 2, px(x) + w // 2, px(y) + w // 2], fill=255)
    (x0, y0), (x1, y1) = pts[-2], pts[-1]
    L = math.hypot(x1 - x0, y1 - y0)
    ux, uy = (x1 - x0) / L, (y1 - y0) / L
    vx, vy = -uy, ux
    tip = (x1 + ux * 52 * scale, y1 + uy * 52 * scale)
    b1 = (x1 - ux * 8 * scale + vx * 62 * scale, y1 - uy * 8 * scale + vy * 62 * scale)
    b2 = (x1 - ux * 8 * scale - vx * 62 * scale, y1 - uy * 8 * scale - vy * 62 * scale)
    ld.polygon([(px(tip[0]), px(tip[1])), (px(b1[0]), px(b1[1])), (px(b2[0]), px(b2[1]))], fill=255)
    if cut_arrow:   # monokrom: panah = lubang transparan pada koin
        alpha = im.getchannel('A')
        alpha.paste(0, mask=layer)
        im.putalpha(alpha)
    else:
        im.paste(Image.new('RGBA', (S, S), arrow), mask=layer)
    return im


def down(im):
    return im.resize((N, N), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    bg = gradient()
    down(bg).save(os.path.join(OUT, 'icon_background.png'))
    # Foreground/monokrom memenuhi ±87% kanvas karena flutter_launcher_icons memberi inset 16%
    # (hasil akhir: simbol ±64% dari kanvas adaptive, di dalam area aman 66%).
    down(symbol(scale=FG_SCALE)).save(os.path.join(OUT, 'icon_foreground.png'))
    down(symbol(scale=FG_SCALE, coin=(255, 255, 255, 255), cut_arrow=True)).save(os.path.join(OUT, 'icon_monochrome.png'))
    # ikon penuh (Android < 8 dan pratinjau): kotak membulat + simbol sedikit lebih besar
    full = bg.convert('RGBA')
    full.alpha_composite(symbol(scale=1.25))
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.225), fill=255)
    full.putalpha(mask)
    down(full).save(os.path.join(OUT, 'icon.png'))
    print('OK ->', os.path.abspath(OUT))


if __name__ == '__main__':
    main()
