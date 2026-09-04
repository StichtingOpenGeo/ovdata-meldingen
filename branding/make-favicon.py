#!/usr/bin/env python3
"""
Builds the forum's favicon from the ovdata banner artwork.

The banner is a wide lockup: a bus, a red "before" badge, arrows, a green
"after" badge, and a train. Only the green badge is wanted, and it cannot
simply be cropped out — the green arrow's tip and the train's nose fall inside
its bounding box, and the dark arrowhead physically touches the ring, so
connected-component filtering alone leaves it attached.

    python3 make-favicon.py ../ovdata.png out/

Needs Pillow. If you would rather not install it:

    docker run --rm -u "$(id -u):$(id -g)" -v "$PWD/..:/w" -w /w/branding \
        python:3-slim sh -c 'pip install --quiet Pillow && python make-favicon.py ../ovdata.png out/'
"""
import math
import os
import sys
from collections import deque

from PIL import Image, ImageDraw

SRC = sys.argv[1] if len(sys.argv) > 1 else '../ovdata.png'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'out'

# The green badge, located in the 1920x612 banner.
BOX = (1005, 5, 1602, 612)
CENTRE = (1303 - 1005, 308 - 5)
RADIUS = 298


def is_green(p):
    r, g, b, a = p
    return a > 100 and g > 100 and r < 130 and b < 130


def components(px, w, h):
    """Every 8-connected run of opaque pixels, largest first."""
    opaque = [[px[x, y][3] > 100 for y in range(h)] for x in range(w)]
    seen = [[False] * h for _ in range(w)]
    out = []
    for sx in range(w):
        for sy in range(h):
            if opaque[sx][sy] and not seen[sx][sy]:
                q = deque([(sx, sy)])
                seen[sx][sy] = True
                pts = []
                while q:
                    x, y = q.popleft()
                    pts.append((x, y))
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            nx, ny = x + dx, y + dy
                            if 0 <= nx < w and 0 <= ny < h and opaque[nx][ny] and not seen[nx][ny]:
                                seen[nx][ny] = True
                                q.append((nx, ny))
                out.append(pts)
    return sorted(out, key=len, reverse=True)


def main():
    crop = Image.open(SRC).convert('RGBA').crop(BOX)
    w, h = crop.size
    px = crop.load()
    cx, cy = CENTRE

    # Measure the ring rather than assuming it, sampling angles clear of both
    # the arrow (left) and the speech tail (lower left).
    samples = []
    for deg in (0, 20, 40, 300, 320, 340):
        a = math.radians(deg)
        for r in range(RADIUS - 60, RADIUS + 3):
            x, y = int(cx + r * math.cos(a)), int(cy + r * math.sin(a))
            if 0 <= x < w and 0 <= y < h and is_green(px[x, y]):
                samples.append((r, px[x, y]))
    r_in, r_out = min(r for r, _ in samples), max(r for r, _ in samples)
    colours = [c for _, c in samples]
    green = max(set(colours), key=colours.count)

    # Keep the ring, plus anything whose centroid is well inside it: the bus
    # and the tick. The train and the arrow fail that test.
    comps = components(px, w, h)
    keep = [comps[0]]
    for p in comps[1:]:
        mx = sum(x for x, _ in p) / len(p)
        my = sum(y for _, y in p) / len(p)
        if math.hypot(mx - cx, my - cy) < RADIUS - 40:
            keep.append(p)

    badge = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    bp = badge.load()
    for p in keep:
        for x, y in p:
            # Beyond the interior, only green belongs — this is what finally
            # sheds the arrowhead fused to the ring.
            if math.hypot(x - cx, y - cy) < RADIUS - 40 or is_green(px[x, y]):
                bp[x, y] = px[x, y]

    # Losing the arrowhead takes a bite out of the ring; fill the band back in.
    for x in range(w):
        for y in range(h):
            if r_in <= math.hypot(x - cx, y - cy) <= r_out and bp[x, y][3] < 100:
                bp[x, y] = green

    # Drop the speech tail. It is charming at 512px and mush at 16px, where it
    # also costs the bus about 15% of its diameter.
    disc = Image.new('L', (w, h), 0)
    ImageDraw.Draw(disc).ellipse(
        [cx - r_out - 1, cy - r_out - 1, cx + r_out + 1, cy + r_out + 1], fill=255)
    badge.putalpha(Image.composite(badge.split()[3], Image.new('L', (w, h), 0), disc))
    badge = badge.crop(badge.getbbox())

    side = int(max(badge.size) * 1.02)
    square = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    square.paste(badge, ((side - badge.size[0]) // 2, (side - badge.size[1]) // 2), badge)

    # A white disc behind the ring: the bus is near-black, and the badge's
    # interior is transparent, so on a dark browser theme it would disappear.
    backing = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    inset = int(side * 0.03)
    ImageDraw.Draw(backing).ellipse([inset, inset, side - inset, side - inset],
                                    fill=(255, 255, 255, 255))
    icon = Image.alpha_composite(backing, square)

    os.makedirs(OUT, exist_ok=True)
    icon.save(os.path.join(OUT, 'icon-source.png'))
    square.save(os.path.join(OUT, 'icon-source-transparent.png'))
    for n in (512, 192, 180, 64, 48, 32, 16):
        icon.resize((n, n), Image.LANCZOS).save(os.path.join(OUT, 'icon-%d.png' % n))
    icon.resize((256, 256), Image.LANCZOS).save(
        os.path.join(OUT, 'favicon.ico'), sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])
    print('wrote %s: %s' % (OUT, ', '.join(sorted(os.listdir(OUT)))))


if __name__ == '__main__':
    main()
