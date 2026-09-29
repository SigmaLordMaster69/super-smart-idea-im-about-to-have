"""Offline perspective preview of the generated world.

    python3 tools/render_view.py view.bin view.png

Ray-marches the height field dumped by tools/render_view.luau from a camera
just behind the road sample, shades it by terrain material, and draws trees
and road structures as depth-tested billboards. It is only a rough preview of
what the Roblox renderer will show.
"""
import struct
import sys

import numpy as np
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
IMG_W, IMG_H = 960, 540
data = open(src, "rb").read()
off = 0
W, step, x0, z0 = struct.unpack_from("<iiff", data, off)
off += 16
rec = np.dtype([("h", "<f4"), ("w", "<f4"), ("deck", "<f4"), ("mat", "<u2"), ("sp", "u1")])
grid = np.frombuffer(data, dtype=rec, offset=off, count=W * W).reshape(W, W)
off += rec.itemsize * W * W
(nprops,) = struct.unpack_from("<i", data, off)
off += 4
pdt = np.dtype([("x", "<f4"), ("y", "<f4"), ("z", "<f4"), ("h", "<f4"), ("r", "<f4"), ("kind", "<f4"), ("c", "u1", 3)])
props = np.frombuffer(data, dtype=pdt, offset=off, count=nprops)
off += pdt.itemsize * nprops
cx, cy, cz, lx, ly, lz = struct.unpack_from("<ffffff", data, off)

H = grid["h"].astype(np.float64)
WL = grid["w"].astype(np.float64)
DECK = grid["deck"].astype(np.float64)
MAT = grid["mat"]
SP = grid["sp"]
SURF = np.maximum(H, DECK)

COLORS = {
    1280: (104, 142, 66), 1284: (78, 118, 52), 1360: (122, 98, 72), 1344: (86, 72, 58),
    896: (122, 118, 112), 800: (96, 96, 100), 788: (56, 54, 56), 1296: (218, 200, 152),
    912: (178, 94, 58), 820: (208, 150, 98), 1392: (226, 196, 158), 1328: (240, 244, 250),
    1376: (60, 62, 66), 2048: (22, 96, 112),
}
albedo = np.zeros((W, W, 3))
for v, c in COLORS.items():
    albedo[MAT == v] = c
albedo[SP == 1] = (58, 60, 64)
albedo[SP == 2] = (235, 235, 230)
albedo[DECK > -9000] = (58, 60, 64)
albedo[SP == 4] = (176, 174, 168)

gz, gx = np.gradient(SURF, step)
normal = np.stack([-gx, np.ones_like(SURF), -gz], axis=-1)
normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
sun = np.array([0.45, 0.62, 0.35])
sun /= np.linalg.norm(sun)
lambert = np.clip(normal @ sun, 0, 1)
shade = albedo * (0.42 + 0.72 * lambert)[..., None]

# camera: behind and above the road sample, looking down the road
cam = np.array([cx, cy, cz])
target = np.array([lx, ly + 3, lz])
fwd = target - cam
fwd[1] = 0
fwd /= np.linalg.norm(fwd)
cam = cam - fwd * 24 + np.array([0, 11, 0])
f = target - cam
f /= np.linalg.norm(f)
right = np.cross(f, [0, 1, 0])
right /= np.linalg.norm(right)
up = np.cross(right, f)
fov = np.radians(70)
tan = np.tan(fov / 2)
xs = (np.arange(IMG_W) + 0.5) / IMG_W * 2 - 1
ys = 1 - (np.arange(IMG_H) + 0.5) / IMG_H * 2
px, py = np.meshgrid(xs * tan, ys * tan * IMG_H / IMG_W)
dirs = f[None, None] + px[..., None] * right + py[..., None] * up
dirs /= np.linalg.norm(dirs, axis=-1, keepdims=True)
D = dirs.reshape(-1, 3)
N = D.shape[0]


def sample(arr, x, z, nearest=False):
    gxp = (x - x0) / step - 0.5
    gzp = (z - z0) / step - 0.5
    inside = (gxp >= 0) & (gxp < W - 1) & (gzp >= 0) & (gzp < W - 1)
    gxp = np.clip(gxp, 0, W - 1.001)
    gzp = np.clip(gzp, 0, W - 1.001)
    i = gxp.astype(int)
    j = gzp.astype(int)
    if nearest:
        return arr[np.round(gzp).astype(int), np.round(gxp).astype(int)], inside
    tx = gxp - i
    tz = gzp - j
    v = (arr[j, i] * (1 - tx) + arr[j, i + 1] * tx) * (1 - tz) + (arr[j + 1, i] * (1 - tx) + arr[j + 1, i + 1] * tx) * tz
    return v, inside


tHit = np.full(N, np.inf)
kind = np.zeros(N, dtype=int)  # 0 sky, 1 ground, 2 water
active = np.ones(N, dtype=bool)
t = np.full(N, 1.5)
prev = t.copy()
maxT = W * step * 0.95
while active.any():
    idx = np.nonzero(active)[0]
    p = cam + D[idx] * t[idx, None]
    s, inside = sample(SURF, p[:, 0], p[:, 2])
    w, _ = sample(WL, p[:, 0], p[:, 2], nearest=True)
    hitG = (p[:, 1] <= s) & inside
    hitW = (p[:, 1] <= w) & (w > s) & inside & ~hitG
    for hitmask, k in ((hitG, 1), (hitW, 2)):
        hi = idx[hitmask]
        if len(hi):
            # refine by bisection
            a, b = prev[hi], t[hi]
            for _ in range(6):
                m = (a + b) / 2
                pm = cam + D[hi] * m[:, None]
                if k == 1:
                    sm, _ = sample(SURF, pm[:, 0], pm[:, 2])
                else:
                    sm, _ = sample(WL, pm[:, 0], pm[:, 2], nearest=True)
                below = pm[:, 1] <= sm
                b = np.where(below, m, b)
                a = np.where(below, a, m)
            tHit[hi] = b
            kind[hi] = k
            active[hi] = False
    still = idx[~(hitG | hitW)]
    prev[still] = t[still]
    t[still] += 0.8 + t[still] * 0.006
    active[still[t[still] > maxT]] = False

img = np.zeros((N, 3))
sky_t = np.clip(D[:, 1] * 2.2, 0, 1)
sky = np.array([200, 214, 230]) * (1 - sky_t[:, None]) + np.array([108, 150, 206]) * sky_t[:, None]
img[:] = sky
g = kind == 1
pg = cam + D[g] * tHit[g, None]
gxi = np.clip(np.round((pg[:, 0] - x0) / step - 0.5).astype(int), 0, W - 1)
gzi = np.clip(np.round((pg[:, 2] - z0) / step - 0.5).astype(int), 0, W - 1)
img[g] = shade[gzi, gxi]
wmask = kind == 2
fres = np.clip(1 - np.abs(D[wmask, 1]) * 2.5, 0, 1) ** 2
img[wmask] = np.array([28, 92, 108]) * (1 - fres[:, None] * 0.7) + sky[wmask] * fres[:, None] * 0.7
depth = np.where(kind > 0, tHit, np.inf)
fog = 1 - np.exp(-np.clip(np.where(kind > 0, tHit, 1e9), 0, 1e9) / 750.0) ** 1.0
fog = np.clip(fog * 0.85, 0, 0.85)
img = img * (1 - fog[:, None]) + np.array([198, 212, 228]) * fog[:, None]
img = img.reshape(IMG_H, IMG_W, 3)
zbuf = depth.reshape(IMG_H, IMG_W)

# billboards, far to near
def project(pt):
    v = pt - cam
    z = v @ f
    if z <= 1:
        return None
    sx = (v @ right) / (z * tan)
    sy = (v @ up) / (z * tan * IMG_H / IMG_W)
    return (sx + 1) / 2 * IMG_W, (1 - sy) / 2 * IMG_H, z


order = np.argsort(-np.linalg.norm(np.stack([props["x"], props["y"], props["z"]], axis=1) - cam, axis=1))
for i in order:
    pr = props[i]
    base = np.array([pr["x"], pr["y"], pr["z"]])
    top = base + np.array([0, pr["h"], 0])
    a, b = project(base), project(top)
    if a is None or b is None:
        continue
    z = a[2]
    if z > maxT:
        continue
    half = pr["r"] / (z * tan) * IMG_W / 2
    x_a, y_base, y_top = a[0], a[1], b[1]
    xl, xr = int(max(0, x_a - half)), int(min(IMG_W, x_a + half + 1))
    yt, yb = int(max(0, y_top)), int(min(IMG_H, y_base + 1))
    if xl >= xr or yt >= yb:
        continue
    color = np.array(pr["c"], dtype=float)
    fz = min(0.85, 0.85 * (1 - np.exp(-z / 750.0)))
    col = color * (1 - fz) + np.array([198, 212, 228]) * fz
    region = zbuf[yt:yb, xl:xr]
    yy, xx = np.mgrid[yt:yb, xl:xr]
    if pr["kind"] == 0:
        # tree: canopy ellipse over the upper part plus a trunk line
        cyy = y_top + (y_base - y_top) * 0.45
        ry = (y_base - y_top) * 0.5
        mask = ((xx - x_a) / max(half, 0.5)) ** 2 + ((yy - cyy) / max(ry, 0.5)) ** 2 <= 1
        trunk = (np.abs(xx - x_a) <= max(half * 0.12, 0.5)) & (yy > cyy)
        shadecol = col * (0.75 + 0.25 * ((xx - x_a) / max(half, 1)))[..., None]
        m = (mask | trunk) & (region > z - 2)
        img[yt:yb, xl:xr][m] = np.where(trunk[m][:, None], np.array([70, 52, 40]) * (1 - fz), shadecol[m])
        region[m] = z
    else:
        m = region > z - 2
        img[yt:yb, xl:xr][m] = col
        region[m] = z

Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(dst)
print(f"rendered {dst}")
