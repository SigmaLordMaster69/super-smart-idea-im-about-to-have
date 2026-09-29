"""Render the binary dump from tools/render_map.luau as a shaded PNG.

    python3 tools/render_map.py map.bin map.png
"""
import struct
import sys

import numpy as np
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
W, H, step, x0, z0 = struct.unpack_from("<iiiff", data, 0)
rec = np.dtype([("h", "<f4"), ("w", "<f4"), ("t", "u1"), ("hint", "u1"), ("f", "u1"), ("sp", "u1")])
arr = np.frombuffer(data, dtype=rec, offset=struct.calcsize("<iiiff"), count=W * H).reshape(H, W)

h = arr["h"].astype(np.float64)
water = arr["w"].astype(np.float64)
t = arr["t"]
hint = arr["hint"]
sp = arr["sp"]

gy, gx = np.gradient(h, step)
slope = np.hypot(gx, gy)
# hillshade, light from the north-west
light = np.array([-1.0, -1.0, 1.4])
light /= np.linalg.norm(light)
nx, ny, nz = -gx, -gy, np.ones_like(h)
norm = np.sqrt(nx * nx + ny * ny + nz * nz)
shade = np.clip((nx * light[0] + ny * light[1] + nz * light[2]) / norm, 0, 1)

TYPE_COLORS = {
    1: (132, 176, 82),  # meadow
    2: (74, 128, 60),  # forest
    3: (104, 132, 84),  # mountains
    4: (112, 150, 88),  # coast
    5: (190, 112, 70),  # canyon
    6: (86, 138, 72),  # lake
    7: (96, 146, 76),  # river valley
}
img = np.zeros((H, W, 3), dtype=np.float64)
for k, c in TYPE_COLORS.items():
    img[t == k] = c
rock = slope > 0.9
img[rock] = (120, 116, 110)
img[(t == 5) & rock] = (170, 88, 58)
img[hint == 3] = (222, 206, 150)  # beach
img[hint == 4] = (96, 92, 90)  # cliff
img[(h > 285) & (slope < 1.1)] = (240, 244, 248)  # snow

img *= (0.35 + 0.75 * shade)[..., None]

wet = water > h + 0.2
depth = np.clip(water - h, 0, 60) / 60
wc = np.stack([30 + 40 * (1 - depth), 90 + 60 * (1 - depth), 140 + 50 * (1 - depth)], axis=-1)
img[wet] = wc[wet]

img[sp == 1] = (40, 40, 44)
img[sp == 2] = (230, 40, 40)
img[sp == 3] = (250, 210, 40)
img[sp == 4] = (255, 255, 255)

img = np.clip(img, 0, 255).astype(np.uint8)
# flip so +z points down like the Roblox top view
Image.fromarray(img).save(dst)
print(f"{W}x{H} step {step}: h {h.min():.0f}..{h.max():.0f}, water cells {wet.mean() * 100:.1f}%")
