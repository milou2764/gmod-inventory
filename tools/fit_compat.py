"""Fits the models of the supported Workshop addons (compat_packs.py) on every default playermodel
(dev tool, not in the .gma). The addons' models are only read here to measure them: the inventory
never ships them.

Needs the addons' extracted folders in MDL_EXTRA_DIRS (separator ";" on Windows), e.g. the
Workshop downloads extracted with gmad.

Writes:
  lua/advinv/sh_compat_data.lua   the packs and their items (names, slot, stats, default attach =
                                  the fit on the reference body male_07, used for other playermodels)
  lua/advinv/cl_fits_compat.lua   the fit of every item on every playermodel (packed), merged into
                                  AdvInv.Fits like cl_fits_data.lua

Rules (playermodels in their reference pose):
  - helmets with a "ref" (all the compatible ones but the Adrian): the size and height chosen by eye on
    male_07, times the head's size / male_07's (width + length of the skull, or of the whole head for
    helmets enclosing it). Searching a size made them too big or lifted them off the head.
  - other helmets: the shell's axis on the middle of the skull, its inner top GAP above the top of the
    head, then the smallest size (0.85 - 1.2) where the skull (the top SKULL units of the head: not
    the ears, nose, hair at the neck or a cap's brim) doesn't go through the inner wall by more than
    HELMET_SLACK, height band by height band, in 24 directions around the axis (only where the shell
    is a closed ring: the face, a brim or a chin strap don't count). Placed on the head bone (eyes
    frame). A helmet sits on the skull: what sticks out of it (ears, hair) may go through, a bigger
    helmet looks far worse than that.
  - vests: size = the item's size on male_07 (extra "size", chosen by eye) x the body's chest girth
    (width + depth of the spine vertices 4 to 14 units under the neck) / male_07's: a test of the
    inside against the body is fooled by straps and buckles inside a vest (it gave the smallest
    size to the bulkiest bodies); then, at that size, the small front/back shift where the chest goes
    through the least; top of the vest at the base of the neck; on Spine4.
  - backpacks: the side against the body flat on the back (the back's usual surface, height by
    height: a hood or a bulge of the playermodel's own gear may go into the pack rather than push it
    off the back), top 2 units under the neck, centred (like the jetpack); smaller when taller than
    the back or much wider than the shoulders. On Spine2.

Pairs approved by hand in the fit editor (fit_locks.txt) are kept as they are.

    python fit_compat.py [playermodels.txt]
"""
import math
import re
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fit_items as fi  # noqa: E402
import fit_locks  # noqa: E402
import mdl_render as mr  # noqa: E402
from compat_packs import PACKS  # noqa: E402

TOOLS = Path(__file__).resolve().parent
OUT_DATA = TOOLS.parent / "lua" / "advinv" / "sh_compat_data.lua"
OUT_FITS = TOOLS.parent / "lua" / "advinv" / "cl_fits_compat.lua"
GAP = fi.GAP
SPINE4 = "ValveBiped.Bip01_Spine4"
BAND, SECTORS, RING = 0.5, 24, 0.6
SKULL = 3.0                     # helmets are fitted to the top 3 units of the head
HELMET_SIZES, HELMET_SLACK = (0.85, 1.2), 0.25
# helmets enclosing the whole head ("full"): fitted to the whole head, nothing may show through
# (short hair at the back of the head would): 98th percentile, no slack; up to 1.2 (a hair bun may
# go through rather than a helmet twice the size of the head)
FULL_SIZES, FULL_SLACK, FULL_PCT = (0.85, 1.2), 0.0, 98
CHEST = (4.0, 14.0)             # vests are fitted to the torso from 4 to 14 units under the neck
VEST_SIZES = (0.75, 1.45)       # bounds of the girth rule

# frames: columns = front, left, up
EYES = np.eye(3)                                                     # x forward, y left, z up
BODY = np.column_stack([(0, -1.0, 0), (1.0, 0, 0), (0, 0, 1.0)])   # model space: front -Y, left +X
PROP = {
    "x_front": np.column_stack([(1.0, 0, 0), (0, 1.0, 0), (0, 0, 1.0)]),
    "y_front": np.column_stack([(0, 1.0, 0), (-1.0, 0, 0), (0, 0, 1.0)]),
    "-y_front": np.column_stack([(0, -1.0, 0), (1.0, 0, 0), (0, 0, 1.0)]),
    "x_out": np.column_stack([(-1.0, 0, 0), (0, -1.0, 0), (0, 0, 1.0)]),
}


def auto_frame(P):
    """Round helmet: dome axis = direction of least spread (top where it narrows), left-right =
    the chin straps (points far from the dome)."""
    c = P.mean(0)
    d = np.linalg.norm(P - c, axis=1)
    core = P[d <= np.percentile(d, 85)]
    w, v = np.linalg.eigh(np.cov((core - core.mean(0)).T))
    u = v[:, 0]
    h = (core - core.mean(0)) @ u
    radius = np.linalg.norm((core - core.mean(0)) - np.outer(h, u), axis=1)
    if radius[h > np.percentile(h, 80)].mean() > radius[h < np.percentile(h, 20)].mean():
        u = -u
    far = P[d > np.percentile(d, 92)] - c
    far = far - np.outer(far @ u, u)
    w2, v2 = np.linalg.eigh(np.cov(far.T))
    left = v2[:, -1] - (v2[:, -1] @ u) * u
    left /= np.linalg.norm(left)
    front = np.cross(left, u)
    # the straps hang at the sides: what the spread of the far points finds is the front-back
    # axis (the brim reaches further than the straps), so turn a quarter
    return np.column_stack([left, -front, u])


def rotation(model, orient, target):
    _, _, P = fi.rest_mesh(model)
    F = auto_frame(P) if orient == "auto" else PROP[orient]
    return target @ F.T


def surface_points(model, step=0.35):
    """Points spread over the triangles (a low-poly shell has few vertices per height band)."""
    pos, tris, P = fi.rest_mesh(model)
    T = np.array([[pos[a], pos[b], pos[c]] for a, b, c, _ in tris])
    area = np.linalg.norm(np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]), axis=1) / 2
    n = np.clip(np.ceil(area / (step * step)), 1, 60).astype(int)
    rng = np.random.default_rng(7)
    idx = np.repeat(np.arange(len(T)), n)
    u, v = rng.random(len(idx)), rng.random(len(idx))
    flip = u + v > 1
    u[flip], v[flip] = 1 - u[flip], 1 - v[flip]
    S = T[idx, 0] + u[:, None] * (T[idx, 1] - T[idx, 0]) + v[:, None] * (T[idx, 2] - T[idx, 0])
    return np.r_[P, S]


class Ring:
    """A shell around a vertical axis (helmet, vest), in the target frame, prop origin kept: inner
    radius by height band and direction, where the shell is a closed ring."""

    def __init__(self, model, R):
        self.model, self.R = model, R
        # the axis: middle of the shell by surface (area), not by vertices (dense details such as an
        # antenna or a rangefinder would pull it), its thin ends left out
        P = surface_points(model)
        Q = P @ R.T
        lo, hi = np.percentile(Q, 2, axis=0), np.percentile(Q, 98, axis=0)
        self.C = (lo + hi) / 2
        q = Q - self.C
        self.z0 = q[:, 2].min()
        self.nb = int((q[:, 2].max() - self.z0) / BAND) + 1
        b = np.clip(((q[:, 2] - self.z0) / BAND).astype(int), 0, self.nb - 1)
        s = ((np.arctan2(q[:, 1], q[:, 0]) + math.pi) / (2 * math.pi) * SECTORS).astype(int) % SECTORS
        r = np.hypot(q[:, 0], q[:, 1])
        self.r_in = np.full((self.nb, SECTORS), np.inf)
        for bi in range(self.nb):
            for si in range(SECTORS):
                rr = r[(b == bi) & (s == si)]
                if len(rr) >= 3:
                    self.r_in[bi, si] = np.percentile(rr, 10)
        ring = np.isfinite(self.r_in).sum(1) >= RING * SECTORS
        if ring.any():
            self.r_in[: int(np.argmax(ring))] = np.inf  # under the lowest closed ring: open
        self.top = q[:, 2].max()  # outer top (vests); inner top of helmets below
        hits = fi.ray_hits(model, R.T @ self.C, R.T @ np.array([0, 0, 1.0]))
        self.inner_top = hits[0] if len(hits) else self.top

    def poke(self, pts, Ce, s, pct=95):
        """How far (target units) points go through the inner wall: the pct percentile, so that a
        few stray vertices don't decide the size alone (<= 0: inside)."""
        rel = (pts - Ce) / s
        b = np.floor((rel[:, 2] - self.z0) / BAND).astype(int)
        ok = (b >= 0) & (b < self.nb)
        rel, b = rel[ok], b[ok]
        sec = ((np.arctan2(rel[:, 1], rel[:, 0]) + math.pi) / (2 * math.pi) * SECTORS).astype(int) % SECTORS
        lim = self.r_in[b, sec]
        fin = np.isfinite(lim)
        if not fin.any():
            return -np.inf
        d = (np.hypot(rel[fin, 0], rel[fin, 1]) - lim[fin]) * s
        return np.percentile(d, pct)


def search(ring, pts, place, s_min, s_max, offsets, slack, pct=95):
    """Smallest size where the points fit (going through by slack at most), trying small offsets
    of the axis; else the size where they go through the least."""
    best = None
    for s in np.arange(s_min, s_max + 1e-9, 0.01):
        for off in offsets:
            Ce = place(s) + off
            p = ring.poke(pts, Ce, s, pct)
            if p <= slack:
                return round(float(s), 2), Ce
            if best is None or p < best[0]:
                best = (p, round(float(s), 2), Ce)
    return best[1], best[2]


# a helmet rests on the skull: it may sit a little above the top of the head (1.5 units at most)
HELMET_OFFSETS = [np.array([dx, 0, dz]) for dz in (0, 0.5, 1.0, 1.5)
                  for dx in (0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5)]
VEST_OFFSETS = [np.array([0, dy, 0]) for dy in (0, 0.5, -0.5, 1.0, -1.0)]


def skull(body):
    """The top SKULL units of the head (eyes frame): what a helmet rests on."""
    h = body.head_in_eyes()
    return h[h[:, 2] >= h[:, 2].max() - SKULL]


def head_size(h):
    """Width + length (2nd-98th percentiles) of head vertices: what a helmet's size follows."""
    return float(np.ptp(np.percentile(h[:, 0], [2, 98])) + np.ptp(np.percentile(h[:, 1], [2, 98])))


def fit_helmet(body, ring, full=False, min_ratio=None, outer_w=None, sizes=None, lift=0.0, ref=None, ref_body=None):
    h = body.head_in_eyes() if full else skull(body)
    hc = np.array([(h[:, 0].min() + h[:, 0].max()) / 2, (h[:, 1].min() + h[:, 1].max()) / 2, 0])
    top = h[:, 2].max()

    def place(s):
        return np.array([hc[0], hc[1], top + GAP - s * ring.inner_top])

    if ref:  # chosen by eye on male_07: carried over by the head's size, no search
        r = ref_body.head_in_eyes() if full else skull(ref_body)
        k = head_size(h) / head_size(r)
        s = round(float(np.clip(ref[0] * k, 0.6, 1.6)), 2)
        back = ref[2] if len(ref) > 2 else 0.0  # moved towards the back of the head (units)
        Ce = place(s) + np.array([-back * k, 0, ref[1] * k])
        return fi.eyes_to_bone(body, ring.R, Ce - s * ring.C, s)
    if full:
        s, Ce = search(ring, h, place, *(sizes or FULL_SIZES), HELMET_OFFSETS, FULL_SLACK, FULL_PCT)
    else:
        lo, hi = sizes or HELMET_SIZES
        if min_ratio:  # at least min_ratio x the skull's width wide
            lo = min(hi, max(lo, round(min_ratio * (h[:, 1].max() - h[:, 1].min()) / outer_w, 2)))
        s, Ce = search(ring, h, place, lo, hi, HELMET_OFFSETS, HELMET_SLACK)
    if lift:  # a shell deeper than the head: raised so that its rim sits at the brow
        Ce = Ce + np.array([0, 0, lift])
    return fi.eyes_to_bone(body, ring.R, Ce - s * ring.C, s)


def fit_helmet_outer(body, R, model, width_ratio, top_gap, full=False, sizes=None):
    """Shells whose inside can't be measured (visors, face parts inside): outer width = width_ratio
    x the skull's width (ears left out), outer top top_gap above the head (that gap follows the
    size), centred on the skull."""
    S = surface_points(model) @ R.T
    lo, hi = np.percentile(S, 2, axis=0), np.percentile(S, 98, axis=0)
    h = body.head_in_eyes() if full else skull(body)
    hw = h[:, 1].max() - h[:, 1].min()
    # within the sizes of the other helmets: a head wearing its own helmet or cap (built into the
    # playermodel) would otherwise give 2.5 or 0.03
    s = round(float(np.clip(width_ratio * hw / (hi[1] - lo[1]), *(sizes or (FULL_SIZES if full else HELMET_SIZES)))), 2)
    hc = (h.min(0) + h.max(0)) / 2
    t = np.array([hc[0] - s * (lo[0] + hi[0]) / 2, hc[1] - s * (lo[1] + hi[1]) / 2,
                  h[:, 2].max() + top_gap * s - s * hi[2]])
    return fi.eyes_to_bone(body, R, t, s)


def chest_girth(body):
    """Width + depth (3rd-97th percentiles) of the spine vertices CHEST units under the neck."""
    torso = body.verts(fi.TORSO)
    neck = body.world["ValveBiped.Bip01_Neck1"][2, 3]
    c = torso[(torso[:, 2] <= neck - CHEST[0]) & (torso[:, 2] >= neck - CHEST[1])]
    return float(np.ptp(np.percentile(c[:, 0], [3, 97])) + np.ptp(np.percentile(c[:, 1], [3, 97])))


def fit_vest(body, ring, size=1.0, ref_girth=None):
    torso = body.verts(fi.TORSO)
    neck = body.world["ValveBiped.Bip01_Neck1"][:3, 3]
    chest = torso[np.abs(torso[:, 2] - body.world[SPINE4][2, 3]) < 4]
    torso = torso[(torso[:, 2] <= neck[2] - CHEST[0]) & (torso[:, 2] >= neck[2] - CHEST[1])]
    cx = (chest[:, 0].min() + chest[:, 0].max()) / 2
    cy = (chest[:, 1].min() + chest[:, 1].max()) / 2

    def place(s):
        return np.array([cx, cy, neck[2] - s * ring.top])

    s = round(float(np.clip(size * chest_girth(body) / ref_girth, *VEST_SIZES)), 2)
    s, Ce = search(ring, torso, place, s, s, VEST_OFFSETS, -np.inf)  # the shift that goes through least
    return fi.model_to_bone(body, SPINE4, ring.R, Ce - s * ring.C, s)


def fit_pack(body, model, R, straps=False):
    _, _, P = fi.rest_mesh(model)
    Pm = P @ R.T
    neck = body.world["ValveBiped.Bip01_Neck1"][:3, 3]
    pelvis = body.world["ValveBiped.Bip01_Pelvis"][:3, 3]
    torso = body.verts(fi.TORSO)
    z_top = neck[2] - 2.0
    height = Pm[:, 2].max() - Pm[:, 2].min()
    width = Pm[:, 0].max() - Pm[:, 0].min()
    shoulders = torso[:, 0].max() - torso[:, 0].min()
    s = round(min(1.0, (z_top - (pelvis[2] - 6)) / height, 1.4 * shoulders / width), 2)
    Ps = Pm * s
    z_bot = z_top - (Ps[:, 2].max() - Ps[:, 2].min())
    band = torso[(torso[:, 2] > z_bot) & (torso[:, 2] < z_top) & (np.abs(torso[:, 0]) < 7)]
    # the back's usual surface: the median, over 1-unit heights, of the furthest point back
    rows = [band[(band[:, 2] >= z) & (band[:, 2] < z + 1), 1].max() for z in np.arange(z_bot, z_top, 1.0)
            if ((band[:, 2] >= z) & (band[:, 2] < z + 1)).sum() >= 3]
    back = float(np.median(rows)) if rows else (band[:, 1].max() if len(band) else torso[:, 1].max())
    # contact: the side against the body, small protrusions (a buckle, a strap) may sink in
    S = surface_points(model) @ R.T * s
    contact = np.percentile(S, 3, axis=0)[1]
    if straps:
        # a pack modelled with its shoulder straps on (Escape From Tarkov's): they reach forward
        # around the shoulders and would hold it off the back. The back panel instead: over the
        # middle of its height, per 1-unit height, the furthest point forward within the middle
        # quarter of its width, their median
        cx = (S[:, 0].min() + S[:, 0].max()) / 2
        mid = S[np.abs(S[:, 0] - cx) < 0.125 * (S[:, 0].max() - S[:, 0].min())]
        lo, hi = np.percentile(S[:, 2], 20), np.percentile(S[:, 2], 80)
        rows = [mid[(mid[:, 2] >= z) & (mid[:, 2] < z + 1), 1].min() for z in np.arange(lo, hi, 1.0)
                if ((mid[:, 2] >= z) & (mid[:, 2] < z + 1)).sum() >= 3]
        if rows:
            contact = float(np.median(rows))
    t = np.array([-(Ps[:, 0].min() + Ps[:, 0].max()) / 2, back + GAP - contact, z_top - Ps[:, 2].max()])
    return fi.model_to_bone(body, fi.SPINE, R, t, s)


# ---------------------------------------------------------------- items

def class_name(pack, model):
    base = re.sub(r"[^a-z0-9]+", "_", Path(model).stem.lower()).strip("_")
    return f"advinv_c_{pack['key']}_{base}"[:60]


def stats(kind, P, extra):
    size = P.max(0) - P.min(0)
    vol = float(size[0] * size[1] * size[2])
    if kind == "back":
        load = int(min(200, max(40, round(vol / 30 / 5) * 5)))
        return {"slot": "Rucksack", "mass": 10 + load // 8, "load": load, "armor": 0, "blocks": "back"}
    if kind == "vest":
        load = extra.get("load", 0)
        return {"slot": "Vest", "mass": 20 + load // 4 + extra.get("armor", 0) // 5, "load": load,
                "armor": extra.get("armor", 0), "blocks": "front" if extra.get("front") else None}
    return {"slot": "Helmet", "mass": 8 + extra.get("armor", 0) // 10, "load": 0, "armor": extra.get("armor", 50), "blocks": None}


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    lst = Path(sys.argv[1]) if len(sys.argv) > 1 else TOOLS / "playermodels.txt"
    models = [l.strip() for l in lst.read_text(encoding="utf-8").splitlines() if l.strip()]
    bodies = {}
    for m in models:
        try:
            b = fi.Body(m)
        except Exception as e:  # noqa: BLE001
            print(f"{m}: skipped ({e})")
            continue
        bodies[m] = b
    ref = bodies.get(fi.REF) or fi.Body(fi.REF)
    ref_girth = chest_girth(ref)
    locks = fit_locks.load()
    import builtin_gear  # noqa: E402
    blocked = builtin_gear.builtin()

    base_hev = None
    saved = mr.EXTRA_DIRS[:]
    mr.EXTRA_DIRS.clear()
    d = mr.vpk_read("models/items/hevsuit.mdl")
    base_hev = len(d) if d else None
    mr.EXTRA_DIRS.extend(saved)

    data, fits = [], {}
    for pack in PACKS:
        items = []
        for (iid, model, kind, orient, en, fr, extra) in pack["items"]:
            if mr.vpk_read(model) is None:
                raise SystemExit(f"{model} not found: set MDL_EXTRA_DIRS to the extracted addons")
            target = EYES if kind == "helmet" else BODY
            R = rotation(model, orient, target)
            if extra.get("tilt"):  # around the shoulder axis (model X)
                a = math.radians(extra["tilt"])
                R = np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]]) @ R
            _, _, P = fi.rest_mesh(model)
            st = stats(kind, P, extra)
            cls = class_name(pack, model)
            ring = Ring(model, R) if kind in ("helmet", "vest") else None
            full = bool(extra.get("full"))
            S = surface_points(model) @ R.T
            outer_w = float(np.percentile(S[:, 1], 98) - np.percentile(S[:, 1], 2))
            per = {}
            for m, body in bodies.items():
                if m.lower() in blocked[{"helmet": "Helmet", "vest": "Vest"}.get(kind, "Rucksack")]:
                    continue  # that gear of its own is in its mesh: none of ours over it
                lk = fit_locks.get(locks, cls, m)
                if lk is not None:  # approved by hand: final
                    per[m] = lk
                    continue
                try:
                    if kind == "helmet":
                        if body.eyes is None or not body.has(fi.HEAD) or len(body.verts([fi.HEAD])) <= 20:
                            continue
                        per[m] = (fit_helmet_outer(body, R, model, *extra["outer"], full, extra.get("sizes")) if "outer" in extra
                                  else fit_helmet(body, ring, full, extra.get("min_ratio"), outer_w, extra.get("sizes"), extra.get("lift", 0.0),
                                                 extra.get("ref"), ref))
                    elif kind == "vest":
                        if not body.has(SPINE4, "ValveBiped.Bip01_Neck1") or len(body.verts(fi.TORSO)) < 50:
                            continue
                        per[m] = fit_vest(body, ring, extra.get("size", 1.0), ref_girth)
                    else:
                        if not body.has(fi.SPINE, "ValveBiped.Bip01_Neck1", "ValveBiped.Bip01_Pelvis"):
                            continue
                        per[m] = fit_pack(body, model, R, extra.get("straps", False))
                except Exception as e:  # noqa: BLE001
                    print(f"  {cls} on {m}: {e}")
            default = per.get(fi.REF)
            if default is None:
                default = ((fit_helmet_outer(ref, R, model, *extra["outer"], full, extra.get("sizes")) if "outer" in extra
                            else fit_helmet(ref, ring, full, extra.get("min_ratio"), outer_w, extra.get("sizes"), extra.get("lift", 0.0),
                                      extra.get("ref"), ref))
                           if kind == "helmet" else fit_vest(ref, ring, extra.get("size", 1.0), ref_girth) if kind == "vest"
                           else fit_pack(ref, model, R, extra.get("straps", False)))
            bone = fi.HEAD if kind == "helmet" else SPINE4 if kind == "vest" else fi.SPINE
            fits[cls] = per
            scales = sorted(v[2] for v in per.values())
            print(f"{iid} {cls:58} {len(per):3d} fits  size {scales[0]:.2f}-{scales[-1]:.2f}")
            items.append({"id": iid, "class": cls, "model": model, "name": (en, fr), "bone": bone, "attach": default, **st})
        data.append((pack, items))

    write_data(data, base_hev)
    write_fits(list(bodies), fits)


def vec(p, n=2):
    return ", ".join(f"{x:.{n}f}" for x in p).replace("-0.00", "0.00").replace("-0.0,", "0.0,")


def write_data(data, base_hev):
    out = ["-- Generated by tools/fit_compat.py from tools/compat_packs.py (do not edit by hand).",
           "-- Workshop addons the inventory is compatible with: their models become inventory items when",
           "-- the addon is installed (sh_compat.lua). The models are the addons' own: nothing is shipped here.",
           "-- attach: the fit on the reference playermodel (others: cl_fits_compat.lua).",
           "AdvInv.CompatPacks = {"]
    for pack, items in data:
        out.append("    {")
        out.append(f"        key = {lua_str(pack['key'])}, wid = \"{pack['wid']}\", title = {lua_str(pack['title'])},")
        out.append(f"        category = {{ {lua_str(pack['category'][0])}, {lua_str(pack['category'][1])} }},")
        if pack.get("probe_material"):
            out.append(f"        probeMaterial = {lua_str(pack['probe_material'])}, baseModelSize = {base_hev or 0},")
        out.append("        items = {")
        for it in items:
            p, a, s = it["attach"]
            blocks = f", blocks = \"{it['blocks']}\"" if it["blocks"] else ""
            out.append(f"            {{ id = {it['id']}, class = {lua_str(it['class'])}, model = {lua_str(it['model'])},")
            out.append(f"              name = {{ {lua_str(it['name'][0])}, {lua_str(it['name'][1])} }}, slot = \"{it['slot']}\","
                       f" mass = {it['mass']}, load = {it['load']}, armor = {it['armor']}{blocks},")
            out.append(f"              attach = {{ bone = \"{it['bone']}\", pos = Vector({vec(p)}), ang = Angle({vec(a, 1)}), scale = {s:g} }} }},")
        out.append("        },")
        out.append("    },")
    out.append("}")
    OUT_DATA.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
    print(f"-> {OUT_DATA}")


def write_fits(models, fits):
    out = ["-- Generated by tools/fit_compat.py (do not edit by hand): the compatibility items (sh_compat_data.lua)",
           "-- fitted to each default playermodel: \"x y z pitch yaw roll size\" per playermodel of M, \"|\" between them,",
           "-- empty when the playermodel can't wear it. Merged into AdvInv.Fits (cl_fits_data.lua).",
           "local M = {"]
    out += [f"    {lua_str(m)}," for m in models]
    out.append("}")
    out.append("local F = {")
    for cls, per in fits.items():
        parts = []
        for m in models:
            f = per.get(m)
            if f is None:
                parts.append("")
                continue
            p, a, s = f
            parts.append(" ".join([f"{x:.2f}" for x in p] + [f"{x:.1f}" for x in a] + [f"{s:g}"]).replace("-0.00", "0.00"))
        out.append(f"    {cls} = \"{'|'.join(parts)}\",")
    out.append("}")
    out += [
        "AdvInv.Fits = AdvInv.Fits or {}",
        "for class, packed in pairs(F) do",
        "    local k = 0",
        "    for e in string.gmatch(packed .. \"|\", \"([^|]*)|\") do",
        "        k = k + 1",
        "        if e ~= \"\" and M[k] then",
        "            local n = {}",
        "            for x in string.gmatch(e, \"%S+\") do n[#n + 1] = tonumber(x) end",
        "            AdvInv.Fits[M[k]] = AdvInv.Fits[M[k]] or {}",
        "            AdvInv.Fits[M[k]][class] = { Vector(n[1], n[2], n[3]), Angle(n[4], n[5], n[6]), n[7] }",
        "        end",
        "    end",
        "end",
    ]
    OUT_FITS.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
    print(f"-> {OUT_FITS} ({OUT_FITS.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
