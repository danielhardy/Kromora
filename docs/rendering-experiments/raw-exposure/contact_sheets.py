#!/usr/bin/env python3
"""Make fixed-transform sheets from the diagnostic PNGs; no auto-normalization."""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw

p = argparse.ArgumentParser()
p.add_argument('directory', type=Path, help='renders/<source> directory')
args = p.parse_args()
for edr in (0, 1):
    for ev in (-2, 0, 2):
        paths = [args.directory / f'matched_{mode}_ev{ev}_edr{edr}.png' for mode in 'ABCD']
        images = [Image.open(path).convert('RGB') for path in paths]
        thumb_w, thumb_h = 360, 360
        sheet = Image.new('RGB', (thumb_w * 4, thumb_h + 40), '#202020')
        draw = ImageDraw.Draw(sheet)
        for col, (mode, im) in enumerate(zip('ABCD', images)):
            im.thumbnail((thumb_w, thumb_h))
            x = col * thumb_w + (thumb_w - im.width)//2
            sheet.paste(im, (x, 35))
            draw.text((col*thumb_w+8, 10), f'{mode}  EV {ev:+}  EDR {edr}  median matched', fill='white')
        sheet.save(args.directory / f'contact_ev{ev}_edr{edr}.jpg', quality=90)
