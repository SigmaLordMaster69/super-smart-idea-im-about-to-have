"""Contact sheets of the props dumped by tools/render_props.luau.

    lune run tools/render_props props.json
    python3 tools/render_props.py props.json outdir [sheet ...]
    python3 tools/render_props.py props.json outdir --match "pine s3*,curve right" --cell 400
    python3 tools/render_props.py new.json outdir --before old.json --match "..." --views 1 --flow

Sheets: trees_<season>, plants_<season>, rocks, signs, road. --match draws
only the named items (a trailing * matches a prefix, otherwise any name
containing a fragment); --before puts the same items from an older dump
next to them.

A small software rasteriser for Roblox primitives: blocks, wedges,
cylinders and balls, with simple sun + sky lighting, SurfaceGui text
(TextScaled is emulated with a bold sans font) and thin outlines. Every item
is drawn from two or three angles. Pixels where two differently coloured
parts share the same plane are striped magenta, which is where Roblox would
flicker (z-fighting).
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

SS = 2  # supersampling factor
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
CAPTION_FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
SUN = np.array([-0.45, 0.78, -0.43])
SUN /= np.linalg.norm(SUN)
SKY_TOP = np.array([150, 186, 228], float)
SKY_BOTTOM = np.array([214, 226, 238], float)
GROUND = np.array([150, 164, 120], float)
ZFIGHT = np.array([255, 0, 200], float)
NEON_BOOST = 1.25

_font_cache = {}


def font(size, path=FONT_PATH):
    key = (path, size)
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(path, size)
    return _font_cache[key]


# ---------------------------------------------------------------------------
# Geometry: each part becomes a list of convex polygons (local, unit shape)
# ---------------------------------------------------------------------------
def _box_polys():
    v = np.array([[x, y, z] for x in (-0.5, 0.5) for y in (-0.5, 0.5) for z in (-0.5, 0.5)])
    idx = lambda x, y, z: (x > 0) * 4 + (y > 0) * 2 + (z > 0)
    faces = [
        [idx(1, 0, 0), idx(1, 1, 0), idx(1, 1, 1), idx(1, 0, 1)],
        [idx(0, 0, 0), idx(0, 0, 1), idx(0, 1, 1), idx(0, 1, 0)],
        [idx(0, 1, 0), idx(0, 1, 1), idx(1, 1, 1), idx(1, 1, 0)],
        [idx(0, 0, 0), idx(1, 0, 0), idx(1, 0, 1), idx(0, 0, 1)],
        [idx(0, 0, 1), idx(1, 0, 1), idx(1, 1, 1), idx(0, 1, 1)],
        [idx(0, 0, 0), idx(0, 1, 0), idx(1, 1, 0), idx(1, 0, 0)],
    ]
    return [v[f] for f in faces]


def _wedge_polys():
    # Roblox WedgePart: full back face at +Z, slope facing -Z (Front) and up
    b0, b1, b2, b3 = [-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0.5, -0.5, 0.5], [-0.5, -0.5, 0.5]
    t0, t1 = [-0.5, 0.5, 0.5], [0.5, 0.5, 0.5]
    faces = [[b0, b1, b2, b3], [b3, b2, t1, t0], [b1, t1, b2], [b0, b3, t0], [b0, t0, t1, b1]]
    return [np.array(f, float) for f in faces]


def _corner_wedge_polys():
    # CornerWedgePart: apex above the (+X, -Z) corner
    b = [[-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0.5, -0.5, 0.5], [-0.5, -0.5, 0.5]]
    apex = [0.5, 0.5, -0.5]
    faces = [b, [b[0], b[1], apex], [b[1], b[2], apex], [b[2], b[3], apex], [b[3], b[0], apex]]
    return [np.array(f, float) for f in faces]


BOX, WEDGE, CORNER = _box_polys(), _wedge_polys(), _corner_wedge_polys()


def part_triangles(p):
    """World-space triangles (n,3,3) and per-vertex normals (n,3,3)."""
    sx, sy, sz = p["z"]
    f = p["f"]
    pos = np.array(f[0:3], float)
    rot = np.array(f[3:12], float).reshape(3, 3)
    shape = p["s"]
    tris, norms = [], []
    if shape in ("Cylinder", "Ball"):
        if shape == "Cylinder":
            r = min(sy, sz) / 2
            n = 18
            a = np.linspace(0, 2 * math.pi, n, endpoint=False)
            ring = np.stack([np.zeros(n), np.cos(a) * r, np.sin(a) * r], axis=1)
            nr = np.stack([np.zeros(n), np.cos(a), np.sin(a)], axis=1)
            x0, x1 = -sx / 2, sx / 2
            for i in range(n):
                j = (i + 1) % n
                p00, p01 = ring[i] + [x0, 0, 0], ring[j] + [x0, 0, 0]
                p10, p11 = ring[i] + [x1, 0, 0], ring[j] + [x1, 0, 0]
                tris += [[p00, p10, p11], [p00, p11, p01]]
                norms += [[nr[i], nr[i], nr[j]], [nr[i], nr[j], nr[j]]]
                c0, c1 = np.array([x0, 0, 0]), np.array([x1, 0, 0])
                tris += [[c0, p01, p00], [c1, p10, p11]]
                norms += [[[-1, 0, 0]] * 3, [[1, 0, 0]] * 3]
        else:
            r = min(sx, sy, sz) / 2
            nu, nv = 18, 10
            for iv in range(nv):
                v0, v1 = math.pi * iv / nv, math.pi * (iv + 1) / nv
                for iu in range(nu):
                    u0, u1 = 2 * math.pi * iu / nu, 2 * math.pi * (iu + 1) / nu
                    pts = []
                    for (u, v) in ((u0, v0), (u1, v0), (u1, v1), (u0, v1)):
                        pts.append(np.array([math.sin(v) * math.cos(u), math.cos(v), math.sin(v) * math.sin(u)]))
                    if iv > 0:
                        tris.append([pts[0] * r, pts[1] * r, pts[2] * r])
                        norms.append([pts[0], pts[1], pts[2]])
                    if iv < nv - 1:
                        tris.append([pts[0] * r, pts[2] * r, pts[3] * r])
                        norms.append([pts[0], pts[2], pts[3]])
        tris = np.array(tris, float)
        norms = np.array(norms, float)
    else:
        polys = {"WedgePart": WEDGE, "CornerWedgePart": CORNER}.get(p["c"], BOX)
        scale = np.array([sx, sy, sz])
        centroid = np.unique(np.concatenate(polys), axis=0).mean(axis=0) * scale
        for poly in polys:
            q = poly * scale
            nrm = np.cross(q[1] - q[0], q[2] - q[0])
            ln = np.linalg.norm(nrm)
            if ln < 1e-12:
                continue
            nrm /= ln
            if np.dot(nrm, q.mean(axis=0) - centroid) < 0:
                nrm = -nrm
            for i in range(1, len(q) - 1):
                tris.append([q[0], q[i], q[i + 1]])
                norms.append([nrm, nrm, nrm])
        tris = np.array(tris, float)
        norms = np.array(norms, float)
    tris = tris @ rot.T + pos
    norms = norms @ rot.T
    return tris, norms


def face_frame(p, face):
    """Corners (top-left, top-right, bottom-right, bottom-left) of a face in
    world space, as a SurfaceGui canvas sees it, plus its width/height."""
    sx, sy, sz = p["z"]
    f = p["f"]
    pos = np.array(f[0:3], float)
    rot = np.array(f[3:12], float).reshape(3, 3)
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    if face == "Front":
        c = [[hx, hy, -hz], [-hx, hy, -hz], [-hx, -hy, -hz], [hx, -hy, -hz]]
        w, h = sx, sy
    elif face == "Back":
        c = [[-hx, hy, hz], [hx, hy, hz], [hx, -hy, hz], [-hx, -hy, hz]]
        w, h = sx, sy
    elif face == "Right":
        c = [[hx, hy, hz], [hx, hy, -hz], [hx, -hy, -hz], [hx, -hy, hz]]
        w, h = sz, sy
    elif face == "Left":
        c = [[-hx, hy, -hz], [-hx, hy, hz], [-hx, -hy, hz], [-hx, -hy, -hz]]
        w, h = sz, sy
    elif face == "Top":
        c = [[-hx, hy, -hz], [hx, hy, -hz], [hx, hy, hz], [-hx, hy, hz]]
        w, h = sx, sz
    else:
        c = [[-hx, -hy, hz], [hx, -hy, hz], [hx, -hy, -hz], [-hx, -hy, -hz]]
        w, h = sx, sz
    return np.array(c, float) @ rot.T + pos, w, h


# ---------------------------------------------------------------------------
# Text: emulate TextScaled + TextWrapped
# ---------------------------------------------------------------------------
def wrap_lines(text, fnt, width):
    out = []
    for para in text.split("\n"):
        words = para.split(" ")
        line = ""
        for w in words:
            trial = w if not line else line + " " + w
            if fnt.getlength(trial) <= width or not line:
                line = trial
            else:
                out.append(line)
                line = w
        out.append(line)
    return out


def fit_text(text, box_w, box_h, scaled, text_size):
    """Returns (size, lines) for a label box in pixels."""
    if not scaled:
        fnt = font(max(1, int(text_size)))
        return int(text_size), wrap_lines(text, fnt, box_w)
    best = 1
    lo, hi = 1, 100  # Roblox caps TextScaled at 100
    while lo <= hi:
        mid = (lo + hi) // 2
        fnt = font(mid)
        lines = wrap_lines(text, fnt, box_w)
        wmax = max(fnt.getlength(l) for l in lines)
        if wmax <= box_w and len(lines) * mid <= box_h:
            best = mid
            lo = mid + 1
        else:
            hi = mid - 1
    return best, wrap_lines(text, font(best), box_w)


def render_canvas(tx, w_studs, h_studs):
    ppu = tx["ppu"]
    W, H = max(1, int(round(w_studs * ppu))), max(1, int(round(h_studs * ppu)))
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for lab in tx["labels"]:
        sxs, sxo, sys_, syo = lab["size"]
        pxs, pxo, pys, pyo = lab["pos"]
        lw, lh = sxs * W + sxo, sys_ * H + syo
        lx = pxs * W + pxo - lab["anchor"][0] * lw
        ly = pys * H + pyo - lab["anchor"][1] * lh
        if lab.get("bg"):
            draw.rectangle([lx, ly, lx + lw, ly + lh], fill=tuple(lab["bg"]) + (255,))
        pl, pr, pt, pb = lab["pad"]
        bx, by = lx + pl * lw, ly + pt * lh
        bw, bh = lw * (1 - pl - pr), lh * (1 - pt - pb)
        size, lines = fit_text(lab["text"], bw, bh, lab["scaled"], lab["textSize"])
        fnt = font(size)
        total = len(lines) * size
        y = by + (bh - total) / 2
        for line in lines:
            lwid = fnt.getlength(line)
            x = bx + (bw - lwid) / 2
            asc, desc = fnt.getmetrics()
            draw.text((x, y + (size - asc - desc) / 2), line, font=fnt, fill=tuple(lab["color"]) + (255,))
            y += size
    return np.asarray(img).astype(float) / 255.0


# ---------------------------------------------------------------------------
# Rasteriser
# ---------------------------------------------------------------------------
class Camera:
    def __init__(self, eye, target, fov_deg, w, h):
        self.eye = np.array(eye, float)
        fwd = np.array(target, float) - self.eye
        fwd /= np.linalg.norm(fwd)
        up = np.array([0.0, 1.0, 0.0])
        right = np.cross(fwd, up)
        if np.linalg.norm(right) < 1e-6:
            right = np.array([1.0, 0.0, 0.0])
        right /= np.linalg.norm(right)
        up = np.cross(right, fwd)
        self.basis = np.stack([right, up, fwd])
        self.w, self.h = w, h
        self.f = (w / 2) / math.tan(math.radians(fov_deg) / 2)

    def to_view(self, pts):
        return (pts - self.eye) @ self.basis.T


class Raster:
    NEAR = 0.05

    def __init__(self, cam):
        self.cam = cam
        w, h = cam.w, cam.h
        self.color = np.zeros((h, w, 3))
        self.z = np.full((h, w), np.inf)
        self.pid = np.full((h, w), -1, dtype=np.int64)
        self.nrm = np.zeros((h, w, 3))
        self.alb = np.zeros((h, w, 3))
        self.zf = np.zeros((h, w), dtype=bool)
        ys = (np.arange(h) + 0.5)[:, None]
        yy = 1 - ys / h * 2
        sky_t = np.clip(yy * 0.8 + 0.3, 0, 1)
        self.color[:] = (SKY_BOTTOM * (1 - sky_t) + SKY_TOP * sky_t)[:, None, :]

    def _clip_near(self, v, n):
        """Clip a view-space triangle against z = NEAR; returns list of (v, n)."""
        inside = v[:, 2] > self.NEAR
        if inside.all():
            return [(v, n)]
        if not inside.any():
            return []
        pts, nrms = [], []
        for i in range(3):
            j = (i + 1) % 3
            if inside[i]:
                pts.append(v[i])
                nrms.append(n[i])
            if inside[i] != inside[j]:
                t = (self.NEAR - v[i, 2]) / (v[j, 2] - v[i, 2])
                pts.append(v[i] + (v[j] - v[i]) * t)
                nrms.append(n[i] + (n[j] - n[i]) * t)
        out = []
        for i in range(1, len(pts) - 1):
            out.append((np.array([pts[0], pts[i], pts[i + 1]]), np.array([nrms[0], nrms[i], nrms[i + 1]])))
        return out

    def draw(self, tris_world, norms_world, albedo, pid, emissive=False, alpha=1.0, uv=None, tex=None, zbias=0.0):
        cam = self.cam
        V = cam.to_view(tris_world.reshape(-1, 3)).reshape(-1, 3, 3)
        for ti in range(len(V)):
            for (v, n) in self._clip_near(V[ti], norms_world[ti]):
                self._tri(v, n, albedo, pid, emissive, alpha, None if uv is None else uv[ti], tex, zbias)

    def _tri(self, v, n, albedo, pid, emissive, alpha, uv, tex, zbias):
        cam = self.cam
        zs = v[:, 2]
        sx = cam.w / 2 + cam.f * v[:, 0] / zs
        sy = cam.h / 2 - cam.f * v[:, 1] / zs
        x0, x1 = int(max(0, math.floor(sx.min()))), int(min(cam.w - 1, math.ceil(sx.max())))
        y0, y1 = int(max(0, math.floor(sy.min()))), int(min(cam.h - 1, math.ceil(sy.max())))
        if x0 > x1 or y0 > y1:
            return
        area = (sx[1] - sx[0]) * (sy[2] - sy[0]) - (sx[2] - sx[0]) * (sy[1] - sy[0])
        if abs(area) < 1e-9:
            return
        px = np.arange(x0, x1 + 1) + 0.5
        py = (np.arange(y0, y1 + 1) + 0.5)[:, None]
        w0 = ((sx[1] - px) * (sy[2] - py) - (sx[2] - px) * (sy[1] - py)) / area
        w1 = ((sx[2] - px) * (sy[0] - py) - (sx[0] - px) * (sy[2] - py)) / area
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-9) & (w1 >= -1e-9) & (w2 >= -1e-9)
        if not inside.any():
            return
        iz = w0 / zs[0] + w1 / zs[1] + w2 / zs[2]
        depth = 1 / np.where(iz > 0, iz, 1e-12)
        b0, b1, b2 = w0 / zs[0] * depth, w1 / zs[1] * depth, w2 / zs[2] * depth
        zb = self.z[y0:y1 + 1, x0:x1 + 1]
        d = depth - zbias
        nrm = b0[..., None] * n[0] + b1[..., None] * n[1] + b2[..., None] * n[2]
        nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True) + 1e-12
        if tex is not None:
            u = b0 * uv[0, 0] + b1 * uv[1, 0] + b2 * uv[2, 0]
            vv = b0 * uv[0, 1] + b1 * uv[1, 1] + b2 * uv[2, 1]
            th, tw = tex.shape[:2]
            ui = np.clip((u * tw).astype(int), 0, tw - 1)
            vi = np.clip((vv * th).astype(int), 0, th - 1)
            texel = tex[vi, ui]
            a = texel[..., 3]
            m = inside & (a > 0.02) & (d <= zb + 0.02)
            if not m.any():
                return
            col = self._shade(texel[..., :3] * 255, nrm, False)
            cb = self.color[y0:y1 + 1, x0:x1 + 1]
            cb[m] = cb[m] * (1 - a[m, None]) + col[m] * a[m, None]
            return
        # z-fighting: nearly equal depth, parallel surfaces, different look
        pb = self.pid[y0:y1 + 1, x0:x1 + 1]
        tie = inside & (np.abs(d - zb) < 0.004) & (pb >= 0) & (pb != pid)
        if tie.any() and alpha >= 1:
            nb = self.nrm[y0:y1 + 1, x0:x1 + 1]
            ab = self.alb[y0:y1 + 1, x0:x1 + 1]
            par = (nb * nrm).sum(axis=-1) > 0.995
            diff = np.abs(ab - np.array(albedo)).sum(axis=-1) > 6
            self.zf[y0:y1 + 1, x0:x1 + 1] |= tie & par & diff
        m = inside & (d < zb - 0.004)
        if not m.any():
            return
        col = self._shade(np.broadcast_to(np.array(albedo, float), nrm.shape), nrm, emissive)
        cb = self.color[y0:y1 + 1, x0:x1 + 1]
        if alpha < 1:
            cb[m] = cb[m] * (1 - alpha) + col[m] * alpha
            return
        cb[m] = col[m]
        zb[m] = d[m]
        pb[m] = pid
        self.nrm[y0:y1 + 1, x0:x1 + 1][m] = nrm[m]
        self.alb[y0:y1 + 1, x0:x1 + 1][m] = albedo
        self.zf[y0:y1 + 1, x0:x1 + 1][m] = False

    def _shade(self, albedo, nrm, emissive):
        if emissive:
            return np.clip(albedo * NEON_BOOST + 30, 0, 255)
        lam = np.clip(nrm @ SUN, 0, 1)
        sky = 0.5 + 0.2 * nrm[..., 1]
        light = sky + 0.62 * lam
        return np.clip(albedo * light[..., None], 0, 255)

    def finish(self, outline=True):
        img = self.color.copy()
        if outline:
            pid = self.pid
            edge = np.zeros(pid.shape, bool)
            dy_a, dx_a = pid[:-1, :] != pid[1:, :], pid[:, :-1] != pid[:, 1:]
            edge[:-1, :] |= dy_a
            edge[:, :-1] |= dx_a
            img[edge] = img[edge] * 0.5
        if self.zf.any():
            h, w = self.zf.shape
            yy, xx = np.mgrid[0:h, 0:w]
            stripe = ((xx + yy) // (3 * SS)) % 2 == 0
            m = self.zf & stripe
            img[m] = ZFIGHT
        return img


# ---------------------------------------------------------------------------
# Scene drawing
# ---------------------------------------------------------------------------
def prepared(item):
    parts = []
    for i, p in enumerate(item["parts"]):
        if p["t"] >= 0.99 and not p.get("tx"):
            continue
        tris, norms = part_triangles(p)
        parts.append((i, p, tris, norms))
    return parts


def bounds(parts):
    pts = [t.reshape(-1, 3) for (_, p, t, _) in parts if p["t"] < 0.99]
    if not pts:
        return np.zeros(3), np.ones(3)
    allp = np.concatenate(pts)
    return allp.min(axis=0), allp.max(axis=0)


def render_view(parts, cam, ground=None):
    r = Raster(cam)
    if ground is not None:
        g0, g1, gy = ground
        quad = np.array([[g0[0], gy, g0[1]], [g1[0], gy, g0[1]], [g1[0], gy, g1[1]], [g0[0], gy, g1[1]]])
        tris = np.array([[quad[0], quad[2], quad[1]], [quad[0], quad[3], quad[2]]])
        norms = np.tile(np.array([0, 1, 0.0]), (2, 3, 1))
        r.draw(tris, norms, GROUND, -2)
    opaque = [x for x in parts if x[1]["t"] < 0.05]
    clear = [x for x in parts if 0.05 <= x[1]["t"] < 0.99]
    for (i, p, tris, norms) in opaque + clear:
        r.draw(tris, norms, p["col"], i, emissive=p["m"] == "Neon", alpha=1 - p["t"])
    for (i, p, _, _) in parts:
        for tx in p.get("tx", []):
            corners, w, h = face_frame(p, tx["face"])
            tex = render_canvas(tx, w, h)
            nrm = np.cross(corners[1] - corners[0], corners[3] - corners[0])
            nrm /= np.linalg.norm(nrm)
            tris = np.array([[corners[0], corners[1], corners[2]], [corners[0], corners[2], corners[3]]])
            uv = np.array([[[0, 0], [1, 0], [1, 1]], [[0, 0], [1, 1], [0, 1]]], float)
            norms = np.tile(nrm, (2, 3, 1))
            r.draw(tris, norms, None, i, uv=uv, tex=tex, zbias=0.0)
    return r.finish()


PROP_VIEWS = {
    "tree": [(25, 10), (150, 38)],
    "far": [(25, 10), (150, 38)],
    "plant": [(25, 18), (150, 45)],
    "rock": [(25, 18), (150, 45)],
    "sign": [(0, 4), (38, 12), (160, 10)],
    "delineator": [(0, 4), (38, 12), (160, 10)],
    "roadend": [(0, 8), (38, 16), (160, 12)],
}


def fitted_camera(lo, hi, az, el, size, fov=30):
    centre = (lo + hi) / 2
    a, e = math.radians(az), math.radians(el)
    # az 0 looks at the model's front (-Z face) from in front of it
    d = np.array([math.sin(a) * math.cos(e), math.sin(e), -math.cos(a) * math.cos(e)])
    fwd = -d
    right = np.cross(fwd, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    corners = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]) - centre
    half = max(np.abs(corners @ right).max(), np.abs(corners @ up).max()) * 1.08 + 0.1
    depth = np.abs(corners @ fwd).max()
    dist = half / math.tan(math.radians(fov) / 2) + depth
    return Camera(centre + d * dist, centre, fov, size, size)


MAX_VIEWS = 3


def render_item(item, cell, row_bounds=None):
    parts = prepared(item)
    cells = []
    if item["category"] == "scene":
        g = item.get("ground")
        ground = ((-600, -600), (600, 600), g) if g is not None else None
        for v in (item.get("views") or [])[:MAX_VIEWS]:
            cam = Camera(v["eye"], v["target"], v.get("fov", 60), cell * SS, cell * SS)
            cells.append(render_view(parts, cam, ground))
        return cells
    lo, hi = row_bounds if row_bounds is not None else bounds(parts)
    # frame from the ground up: buried post and trunk ends do not count
    lo = np.array([lo[0], 0.0, lo[2]])
    ground = ((lo[0] - 400, lo[2] - 400), (hi[0] + 400, hi[2] + 400), 0.0)
    for (az, el) in PROP_VIEWS[item["category"]][:MAX_VIEWS]:
        cam = fitted_camera(lo, hi, az, el, cell * SS)
        cells.append(render_view(parts, cam, ground))
    return cells


def downsample(img):
    h, w = img.shape[0] // SS, img.shape[1] // SS
    return img[: h * SS, : w * SS].reshape(h, SS, w, SS, 3).mean(axis=(1, 3))


def contact_sheet(items, title, path, cell, flow=False, max_w=2400, colors=0):
    rows = {}
    order = []
    for it in items:
        if it["row"] not in rows:
            rows[it["row"]] = []
            order.append(it["row"])
        rows[it["row"]].append(it)
    tiles = []  # one list of tile images per row
    for row in order:
        its = rows[row]
        shared = None
        if all(it["category"] in ("tree", "far") for it in its):
            # one scale for every tree in the row, so sizes compare
            b = [bounds(prepared(it)) for it in its]
            lo = np.min([x[0] for x in b], axis=0)
            hi = np.max([x[1] for x in b], axis=0)
            ext = np.maximum(np.abs(lo), np.abs(hi))
            shared = (np.array([-ext[0], min(lo[1], 0), -ext[2]]), np.array([ext[0], hi[1], ext[2]]))
        row_tiles = []
        for it in its:
            cells = [downsample(c) for c in render_item(it, cell, shared)]
            strip = np.concatenate(cells, axis=1)
            img = Image.fromarray(np.clip(strip, 0, 255).astype(np.uint8))
            cap = Image.new("RGB", (img.width, 18), (250, 250, 250))
            d = ImageDraw.Draw(cap)
            n = sum(1 for p in it["parts"] if p["t"] < 0.99)
            nt = len(it["parts"])
            label = f"{it['name']}  [{nt} parts" + (f", {nt - n} invisible" if nt != n else "") + "]"
            d.text((4, 2), label, font=font(12, CAPTION_FONT), fill=(20, 20, 20))
            tile = Image.new("RGB", (img.width, img.height + 18), (250, 250, 250))
            tile.paste(cap, (0, 0))
            tile.paste(img, (0, 18))
            row_tiles.append(tile)
        tiles.append(row_tiles)
    pad = 6
    if flow:
        # every tile in one stream; rows only keep their tiles together
        tiles = [[t for row_tiles in tiles for t in row_tiles]]
    lines = []
    for row_tiles in tiles:
        line, width = [], 0
        for t in row_tiles:
            if line and width + t.width + pad > max_w:
                lines.append(line)
                line, width = [], 0
            line.append(t)
            width += t.width + pad
        if line:
            lines.append(line)
    W = max(sum(t.width + pad for t in line) for line in lines) + pad
    H = sum(max(t.height for t in line) + pad for line in lines) + pad + 28
    sheet = Image.new("RGB", (W, H), (226, 226, 226))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 6), title, font=font(16, FONT_PATH), fill=(10, 10, 10))
    y = 28 + pad
    for line in lines:
        x = pad
        for t in line:
            sheet.paste(t, (x, y))
            x += t.width + pad
        y += max(t.height for t in line) + pad
    if colors:
        sheet = sheet.quantize(colors=colors, method=Image.Quantize.MEDIANCUT)
    sheet.save(path, optimize=True)
    return path


def main():
    import argparse

    ap = argparse.ArgumentParser(description="Contact sheets of props dumped by tools/render_props.luau")
    ap.add_argument("json")
    ap.add_argument("outdir")
    ap.add_argument("sheets", nargs="*", help="only these sheets (default: all)")
    ap.add_argument("--match", help="comma-separated name fragments: draw only matching items, on one sheet")
    ap.add_argument("--cell", type=int, help="cell size in pixels")
    ap.add_argument("--views", type=int, default=3, help="views per item (1-3)")
    ap.add_argument("--before", help="an older dump: draw each matched item from it next to the new one")
    ap.add_argument("--out", help="output file name for --match (default match.png)")
    ap.add_argument("--width", type=int, default=2400, help="sheet width before tiles wrap")
    ap.add_argument("--flow", action="store_true", help="pack tiles of different rows onto the same line")
    ap.add_argument("--colors", type=int, default=0, help="save with this many palette colours (smaller files)")
    args = ap.parse_intermixed_args()
    global MAX_VIEWS
    MAX_VIEWS = args.views
    data = json.load(open(args.json))
    os.makedirs(args.outdir, exist_ok=True)
    if args.match:
        keys = [k.strip() for k in args.match.split(",")]

        def pick(d):
            found = []
            for k in keys:
                for it in d["items"]:
                    if it["name"] == k or (k.endswith("*") and it["name"].startswith(k[:-1])):
                        if not args.sheets or it["sheet"] in args.sheets:
                            found.append(it)
            return found

        items = pick(data)
        if not items:
            items = [it for it in data["items"] if any(k in it["name"] for k in keys) and (not args.sheets or it["sheet"] in args.sheets)]
        if args.before:
            old = {(it["sheet"], it["name"]): it for it in json.load(open(args.before))["items"]}
            pairs = []
            for it in items:
                prev = old.get((it["sheet"], it["name"]))
                if prev:
                    pairs.append(dict(prev, name="before: " + it["name"], row=it["name"]))
                pairs.append(dict(it, name="after: " + it["name"], row=it["name"]))
            items = pairs
        name = args.out or "match.png"
        title = "match: " + args.match if not args.before else "before / after"
        path = contact_sheet(items, title, os.path.join(args.outdir, name), args.cell or 360, args.flow, args.width, args.colors)
        print("wrote", path)
        return
    sheets = {}
    order = []
    for it in data["items"]:
        if it["sheet"] not in sheets:
            sheets[it["sheet"]] = []
            order.append(it["sheet"])
        sheets[it["sheet"]].append(it)
    for name in order:
        if args.sheets and name not in args.sheets:
            continue
        cell = args.cell or {"road": 400, "signs": 200}.get(name, 170)
        path = contact_sheet(sheets[name], name, os.path.join(args.outdir, name + ".png"), cell)
        print("wrote", path)


if __name__ == "__main__":
    main()
