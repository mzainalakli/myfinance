#!/usr/bin/env python3
"""Membuat ic_launcher_round (PNG bulat untuk Android 7.1 + XML adaptif) dari hasil flutter_launcher_icons."""
import os
import shutil
from PIL import Image, ImageDraw

RES = os.path.join(os.path.dirname(__file__), '..', 'android', 'app', 'src', 'main', 'res')
for d in ('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'):
    src = os.path.join(RES, f'mipmap-{d}', 'ic_launcher.png')
    im = Image.open(src).convert('RGBA')
    n = im.size[0]
    k = 4
    mask = Image.new('L', (n * k, n * k), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, n * k - 1, n * k - 1], fill=255)
    mask = mask.resize((n, n), Image.LANCZOS)
    big = im.resize((n, n))
    big.putalpha(Image.composite(big.getchannel('A'), Image.new('L', (n, n), 0), mask))
    big.save(os.path.join(RES, f'mipmap-{d}', 'ic_launcher_round.png'))
shutil.copyfile(os.path.join(RES, 'mipmap-anydpi-v26', 'ic_launcher.xml'),
                os.path.join(RES, 'mipmap-anydpi-v26', 'ic_launcher_round.xml'))
print('OK round icons')
