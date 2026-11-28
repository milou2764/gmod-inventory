"""Gear taken from a playermodel addon's own bodygroups, as inventory items: an AIS extension that ships
Lua only. The gear is drawn with the playermodel's own model (its other bodygroups set to their empty
choice, the parts that have none hidden by material), so nothing of the playermodel's author is
redistributed; the playermodel addon must be installed, as for its textures.

For each item of a pack (modelgear_packs.py) it measures, in the pose the game draws the model in
(its first sequence, anim0.py):
  - the bodygroups that show it worn and stored (on the ground, in the inventory: webbing without its
    straps), the others empty; the materials hidden (checked: none of the gear's);
  - the stored gear's centre (the item's origin on the ground) and a convex hull around it (its physics);
  - its fit on every playermodel of a list, transferred from the playermodel it comes from: headgear
    in the eyes frame, by the skull's size, top on the top of the skull; vests and backpacks in their
    spine bone's frame, by the chest's girth (playermodels with that gear in their mesh get none);
  - on the pack's own playermodels, the bodygroups that show it (AdvInv.ModelGear items: no prop).
Writes the extension's Lua (lua/autorun/advinv_ext_<pack>.lua).

    python modelgear_pack.py <pack> <playermodels.txt> <out.lua> [--preview out.jpg]

Needs MDL_EXTRA_DIRS (see fit_compat.py).
"""
import math
import struct
import os
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import anim0  # noqa: E402
import builtin_gear  # noqa: E402
import fit_compat as fc  # noqa: E402
import fit_items as fi  # noqa: E402
import fit_locks  # noqa: E402

_nz = fit_locks._nz  # (a negative zero without its sign; "-0.004" keeps it)
import fitcore  # noqa: E402  (the rays and cuts in C when built: tools/fitcore)
import mdl_render as mr  # noqa: E402
import refbody  # noqa: E402
from modelgear_packs import PACKS  # noqa: E402

SPINE2, SPINE4, NECK = "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_Neck1"
PELVIS = "ValveBiped.Bip01_Pelvis"
UPPERARMS = ("ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_R_UpperArm")
_posed_cache = {}
BONE = {"Helmet": fi.HEAD, "Vest": SPINE4, "Rucksack": SPINE2, "Gasmask": fi.HEAD, "NVGs": fi.HEAD, "Radio": fi.HEAD}
HEAD_SLOTS = ("Helmet", "Gasmask", "NVGs", "Radio")  # (fitted by the skull: a gas mask, night vision, a headset)


def bodyparts(model):
    """[(name, [(submodel name, has a mesh)])] of the model, in order."""
    d = mr.vpk_read(model)
    i = lambda o: struct.unpack_from("<i", d, o)[0]
    out = []
    for b in range(i(232)):
        bo = i(236) + b * 16
        subs = []
        for s in range(i(bo + 4)):
            so = bo + i(bo + 12) + s * 148
            subs.append((mr.cstr(d, so).lower(), i(so + 72) > 0))
        out.append((mr.cstr(d, bo + i(bo)).strip(), subs))
    return out


def _pick(names, want):
    """Index of the first name starting with want, else ending with it, else containing it (models of
    one pack may prefix their names: "VN3_Headgear_Pith02", "male_01_helmet1.smd")."""
    want = want.lower()
    low = [n.lower() for n in names]
    for test in (lambda n: n.startswith(want), lambda n: n.endswith(want) or n.endswith(want + ".smd"),
                 lambda n: want in n):
        for k, n in enumerate(low):
            if test(n):
                return k
    return None


def find(parts, part, sub):
    """Index of the bodypart named `part` and of its submodel `sub` (start of their names, else the
    end, else a part of it)."""
    b = _pick([name for name, _ in parts], part)
    if b is None:
        raise SystemExit(f"no bodypart {part}")
    s = _pick([sn for sn, _ in parts[b][1]], sub)
    if s is None:
        raise SystemExit(f"{part}: no submodel {sub}")
    return b, s


def empty_choices(parts):
    return {b: next(s for s, (_, m) in enumerate(subs) if not m) for b, (_, subs) in enumerate(parts)
            if any(not m for _, m in subs)}


def posed(model, sel):
    mr.BODYGROUPS[model.lower()] = dict(sel)
    return anim0.posed_mesh(model)


def _unused_gear_mesh(model, sel, hidden):
    """Vertices (posed) and triangles of what the selection shows, the hidden materials left out."""
    P, N, uv, tris, mats = posed(model, sel)
    keep = [t for t in tris if t[3] not in hidden]
    used = sorted({t[k] for t in keep for k in range(3)})
    return P, keep, used


def hull_points(pts, n=56):
    """Support points of the cloud in n directions (a convex polytope inside its hull, a few dozen points)."""
    k = np.arange(n) + 0.5
    phi = np.arccos(1 - 2 * k / n)
    th = math.pi * (1 + 5 ** 0.5) * k
    dirs = np.c_[np.cos(th) * np.sin(phi), np.sin(th) * np.sin(phi), np.cos(phi)]
    idx = sorted({int(np.argmax(pts @ d)) for d in dirs})
    return pts[idx]


def split_pieces(V, min_gap=2.0, keep=0.3):
    """Pieces apart from each other (webbing's pouches without their straps: nothing holds them together):
    the widest empty slab across the cloud along x, y or z, if wider than min_gap. -> [(normal, dist,
    offset)] for both sides (a clip plane in the model's space, and the move that closes the gap down to
    `keep`), or None."""
    best = None
    for a in range(3):
        xs = np.sort(V[:, a])
        gaps = np.diff(xs)
        k = int(np.argmax(gaps))
        if gaps[k] > min_gap and (best is None or gaps[k] > best[1]):
            best = (a, gaps[k], xs[k], xs[k + 1])
    if best is None:
        return None
    a, gap, lo, hi = best
    mid = (lo + hi) / 2
    n = np.zeros(3)
    n[a] = 1.0
    close = (gap - keep) / 2
    return [(n, mid, -n * close), (-n, -mid, n * close)]


def posed_bones(model):
    """World matrices (posed, as drawn) and the reference ones, by bone name."""
    names = [b["name"] for b in refbody.bones(model)]
    pose = anim0.rest_bones(model)
    ref = [b["world"] for b in refbody.bones(model)]
    return {n: (pose[k], ref[k]) for k, n in enumerate(names)}


def transfer_helmet(src, src_bones, V, target, lift=0.0):
    """Attach on target's head: the gear in the source's eyes frame, scaled by the skull, top on top;
    lift: raised by that much (units on the source's head, scaled like it: a cap worn over the eyes on
    its own model, its brim brought up on the forehead)."""
    hp, hr = src_bones[fi.HEAD]
    eyes_posed = hp @ np.linalg.inv(hr) @ src.eyes
    Ei = np.linalg.inv(eyes_posed)
    hs, ht = fc.skull(src), fc.skull(target)
    k = fc.head_size(ht) / fc.head_size(hs)
    a_s = np.array([(hs[:, 0].min() + hs[:, 0].max()) / 2, (hs[:, 1].min() + hs[:, 1].max()) / 2, hs[:, 2].max()])
    a_t = np.array([(ht[:, 0].min() + ht[:, 0].max()) / 2, (ht[:, 1].min() + ht[:, 1].max()) / 2, ht[:, 2].max()])
    R_e = Ei[:3, :3]
    t_e = k * (Ei[:3, 3] - a_s) + a_t
    t_e[2] += k * lift
    return fi.eyes_to_bone(target, R_e, t_e, round(float(k), 3))


def girth_at(body, t, half=2.0):
    """Width + depth of the torso at the relative height t between the pelvis (0) and the neck (1)."""
    torso = body.verts(fi.TORSO)
    pel, neck = body.world["ValveBiped.Bip01_Pelvis"][2, 3], body.world[NECK][2, 3]
    z = pel + t * (neck - pel)
    c = torso[np.abs(torso[:, 2] - z) <= half]
    if len(c) < 20:
        return None
    return float(np.ptp(np.percentile(c[:, 0], [3, 97])) + np.ptp(np.percentile(c[:, 1], [3, 97])))


def gear_height(body, zc):
    """Relative height (pelvis 0, neck 1) of the gear as worn: zc, the median height of its vertices
    (where most of it is: a chest rig's pouches, not its shoulder straps)."""
    pel, neck = body.world["ValveBiped.Bip01_Pelvis"][2, 3], body.world[NECK][2, 3]
    return float(np.clip((zc - pel) / (neck - pel), 0.25, 0.8))


LEVEL = os.environ.get("MODELGEAR_LEVEL", "1") != "0"  # (0: the former placement, for comparisons)
LEVEL_LOG = []  # (gear class, playermodel, units moved up) of the last run
LAST_UP = None
ANCHOR = os.environ.get("MODELGEAR_ANCHOR", "top")  # "middle": its middle at the same relative height
STRETCH_MAX = 1.25  # a vest made taller than wide by at most that much (0 or 1: never)
TALL = 0.6  # gear whose top is that high on the torso (pelvis 0, neck 1) or higher: stretched with it


def transfer_torso(src, src_bones, bone, target, src_girth, t=None, drop=0.0, zc=None, ztop=None, tall=True):
    """Attach on target's spine bone: the gear in the source's bone frame, scaled by the torso's girth
    where it sits (t: its relative height, both bodies measured there; a chest rig on a slim soldier's
    belly isn't sized by a citizen's chest), else by the chest's. A vest drawn as one piece (ztop: the
    height of its top as worn on its own soldier; zc, of its middle) keeps its straps the same distance
    below the neck, and is stretched downwards to the torso's length when that is longer than its size
    gives (on a slim body, sized by the girth alone, it ended high on the chest: the female citizens).
    -> pos, angles, size, stretch (vertical, around ztop: 1 = none)."""
    bp, _br = src_bones[bone]
    Bi = np.linalg.inv(bp)
    k = fc.chest_girth(target) / src_girth
    if t is not None:
        gs, gt = girth_at(src, t), girth_at(target, t)
        if gs and gt:  # (within 15 % of the chest's ratio: a built-in vest's collar isn't the body)
            k = min(max(gt / gs, 0.85 * k), 1.15 * k)
    k = round(float(k), 3)
    pos = Bi[:3, 3] * k
    stretch = 1.0
    if tall and ztop is not None and STRETCH_MAX > 1 and PELVIS in src_bones and NECK in src_bones:
        # a vest is as wide as the chest gives and as tall as the torso is long: on a slim body (the
        # female citizens, Alyx) sized by the girth alone it was too short and its plate ended high on the
        # chest; stretched downwards from its top (the straps stay on the shoulders), never shortened
        tb = _posed_cache.get(target.model)
        if tb is None:
            tb = _posed_cache[target.model] = posed_bones(target.model)
        ls = abs(src_bones[NECK][0][2, 3] - src_bones[PELVIS][0][2, 3])
        lt = abs(tb[NECK][0][2, 3] - tb[PELVIS][0][2, 3]) if PELVIS in tb and NECK in tb else 0
        if ls > 1 and lt > 1:
            stretch = round(float(min(max(lt / ls / k, 1.0), STRETCH_MAX)), 3)
    if zc is not None and ztop is not None and PELVIS in src_bones \
            and all(u in src_bones for u in UPPERARMS) and target.has(PELVIS, *UPPERARMS):
        # (between the pelvis and the shoulder joints, where a vest's straps and a pack's hang: the neck
        # bone stands higher above the shoulders on some bodies, the female citizens')
        ps = src_bones[PELVIS][0][2, 3]
        ns = sum(src_bones[u][0][2, 3] for u in UPPERARMS) / 2
        rel = (zc - ps) / (ns - ps)  # (where it sits on its own soldier, as drawn)
        # the target as the game draws it too (its idle pose: the female citizens' chest bone stands
        # differently there than in their reference pose)
        tb = _posed_cache.get(target.model)
        if tb is None:
            tb = _posed_cache[target.model] = posed_bones(target.model)
        Tt = tb[bone][0]
        q = (Bi @ np.array([bp[0, 3], bp[1, 3], zc, 1.0]))[:3] * k  # its middle in the target bone's frame
        z_now = (Tt[:3, :3] @ q + Tt[:3, 3])[2]
        pt, nt = tb[PELVIS][0][2, 3], sum(tb[u][0][2, 3] for u in UPPERARMS) / 2
        up = (pt + rel * (nt - pt)) - z_now
        if ANCHOR == "top" and ztop is not None and NECK in src_bones and NECK in tb:
            # a vest hangs from the shoulders: its top (the straps) the same distance below the neck,
            # scaled like it; a smaller or larger one changes towards the waist (centred, a slim body's
            # vest rose up the chest)
            qt = (Bi @ np.array([bp[0, 3], bp[1, 3], ztop, 1.0]))[:3] * k
            top_now = (Tt[:3, :3] @ qt + Tt[:3, 3])[2]
            up = (tb[NECK][0][2, 3] - k * (src_bones[NECK][0][2, 3] - ztop)) - top_now
        global LAST_UP
        LAST_UP = round(float(up), 2)
        if LEVEL:
            pos = pos + Tt[:3, :3].T @ np.array([0.0, 0.0, up])
    if drop:  # lowered by that much (units on the source's body, scaled like it), straight down
        pos = pos + target.world[bone][:3, :3].T @ np.array([0.0, 0.0, -drop * k])
    return pos, fi.matrix_angles(Bi[:3, :3]), k, stretch


# ---------------------------------------------------------------- a vest fitted to the body
# After its placement by the neck bone and its size by the chest's girth (transfer_torso), a vest drawn as
# one piece is fitted to the body as the game draws it (anim0.posed_mesh: no game needed):
#   - its straps rest on the shoulders (placed by the neck bone they floated 2 units over the female
#     citizens' shoulders: their neck bone stands differently above them);
#   - its front and back panels lie against the chest, the belly and the back: its depth is stretched (the
#     fit's 9th number, around the item's depth_center) and it is moved forward or back (sized by the girth
#     it was too shallow for G-Man and Kleiner, their jackets through its front plate, and stood off the
#     female citizens' backs).
# Each is brought as close to the body as it goes without the body showing through it: on a grid across
# it, its outer surface stands FIT_MARGIN outside the body's (rays cast onto the body), but for FIT_SPARE
# percent of the cells (a ponytail, a hood, a collar). tools/vest_check.py reports what is left.
FIT = os.environ.get("MODELGEAR_FIT", "1") != "0"  # (0: as placed by the neck bone and sized by the girth)
FIT_MARGIN = 0.15  # (world units) its outer surface outside the body's
FIT_SPARE = 3  # (percent of the cells) where the body may show through
FIT_CELL = 0.6  # (units on the source's body, scaled like it) the grid across its straps and panels
STRAP_BAND = 3.0  # the top of a vest that lies on the shoulders (units on its own soldier)
STRAP_FLAT = 0.5  # a strap rests on what faces up at least that much (its normal's vertical part)
REST_MAX = 4.0  # moved up or down by at most that much (units on the source's body, scaled like it)
DEPTH_RANGE = (0.85, 1.35)
DEPTH_MOVE = 3.0  # moved forward or back by at most that much (units on the source's body, scaled like it)
STRAP_SPREAD, STRAP_OUTLIER = 2.5, 1.5  # (units on the source's body, scaled like them) when resting on
# the highest things under the straps would leave most of them floating more than STRAP_SPREAD over the
# shoulders, those standing STRAP_OUTLIER above the rest are a hood or a big collar: the straps go under it,
# the vest isn't lifted over it (Alyx's hood raised it 2.8 units). A shoulder rising to the neck is not one.
AIR_OK = 0.4  # (world units) a gap seen from the side up to that much is left as it is; beyond, tilted
TILTS = (2.0, -2.0, 4.0, -4.0, 6.0, -6.0)  # (degrees, about the straps) tried for a vest that leaves a gap
TILTS_SMALL = (4.0, -4.0, 8.0, -8.0, 12.0, -12.0)  # (and for gear hanging from a belt: a holster against the hip)
FIT_LOG = []  # (gear class, playermodel, up, forward, depth, tilt, air left, "fit" | "lock") of the last run
_mesh_cache = {}


def angle_matrix(a):
    """Source QAngle (pitch, yaw, roll), degrees -> 3x3 rotation (AngleMatrix; fit_items.matrix_angles back)."""
    p, y, r = (math.radians(x) for x in a)
    sp, cp, sy, cy, sr, cr = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(r), math.cos(r)
    return np.array([[cp * cy, sr * sp * cy - cr * sy, cr * sp * cy + sr * sy],
                     [cp * sy, sr * sp * sy + cr * cy, cr * sp * sy - sr * cy],
                     [-sp, sr * cp, cr * cp]])


def drawn_mesh(model):
    """The playermodel as the game draws it (anim0.posed_mesh): vertices, triangles (n, 3); the last one kept."""
    if _mesh_cache.get("model") != model:
        P, _N, _uv, tris, _mats = anim0.posed_mesh(model, textures=False)
        _mesh_cache.update(model=model, P=P, T=np.array([t[:3] for t in tris], dtype=np.int64).reshape(-1, 3))
    return _mesh_cache["P"], _mesh_cache["T"]


def surface_below(BP, BT, pts, below, above, slope=False):
    """Height of the highest triangle of a mesh (vertices BP, triangles BT) straight below each point,
    from `below` under it to `above` over it; -inf where none. slope: also how flat it is there (the
    vertical part of its normal, 1: level, 0: upright) -> (heights, flatness)."""
    out = np.full(len(pts), -np.inf)
    flat = np.zeros(len(pts))
    if not len(pts) or not len(BT):
        return (out, flat) if slope else out
    if fitcore.available():
        out, flat = fitcore.surface_below(BP, BT, pts, below, above)
        return (out, flat) if slope else out
    A, B, C = BP[BT[:, 0]], BP[BT[:, 1]], BP[BT[:, 2]]
    lo, hi = pts.min(0), pts.max(0)
    tmin, tmax = np.minimum(np.minimum(A, B), C), np.maximum(np.maximum(A, B), C)
    keep = ((tmax[:, 0] >= lo[0]) & (tmin[:, 0] <= hi[0]) & (tmax[:, 1] >= lo[1]) & (tmin[:, 1] <= hi[1])
            & (tmax[:, 2] >= lo[2] - below) & (tmin[:, 2] <= hi[2] + above))
    A, B, C = A[keep], B[keep], C[keep]
    e1, e2 = (B - A)[:, :2], (C - A)[:, :2]
    den = e1[:, 0] * e2[:, 1] - e1[:, 1] * e2[:, 0]
    ok = np.abs(den) > 1e-9
    A, B, C, e1, e2, den = A[ok], B[ok], C[ok], e1[ok], e2[ok], den[ok]
    if not len(A):
        return (out, flat) if slope else out
    nrm = np.cross(B - A, C - A)
    level = np.abs(nrm[:, 2]) / (np.linalg.norm(nrm, axis=1) + 1e-12)
    for s in range(0, len(pts), 256):
        p = pts[s:s + 256]
        d = p[:, None, :2] - A[None, :, :2]
        u = (d[..., 0] * e2[:, 1] - d[..., 1] * e2[:, 0]) / den
        v = (e1[:, 0] * d[..., 1] - e1[:, 1] * d[..., 0]) / den
        z = A[:, 2] + u * (B[:, 2] - A[:, 2]) + v * (C[:, 2] - A[:, 2])
        valid = (u >= 0) & (v >= 0) & (u + v <= 1) & (z <= p[:, 2:3] + above) & (z >= p[:, 2:3] - below)
        zz = np.where(valid, z, -np.inf)
        top = zz.argmax(1)
        out[s:s + 256] = zz[np.arange(len(p)), top]
        flat[s:s + 256] = level[top]
    return (out, flat) if slope else out


def placed_vest(V, ztop, xc, model, bone, fit):
    """A vest's vertices (its model's space, as worn on its own soldier) placed on model by fit (pos, angles,
    size[, stretch[, depth]]), as the game draws them (cl_gear.lua AdvInv.StretchGear)."""
    tb = _posed_cache.get(model)
    if tb is None:
        tb = _posed_cache[model] = posed_bones(model)
    pos, ang, k = fit[0], fit[1], fit[2]
    st = fit[3] if len(fit) > 3 else 1.0
    dp = fit[4] if len(fit) > 4 else 1.0
    P = V.copy()
    if ztop is not None and st != 1:
        P[:, 2] = ztop + (P[:, 2] - ztop) * st
    if xc is not None and dp != 1:
        P[:, 0] = xc + (P[:, 0] - xc) * dp
    Tt = tb[bone][0]
    return (Tt[:3, :3] @ angle_matrix(ang) @ (P * k).T).T + Tt[:3, :3] @ np.asarray(pos, dtype=float) + Tt[:3, 3]


def cover(W, BP, BT, region, k=1.0, shoulders_z=None, part=None):
    """A placed vest (vertices W) against the body as drawn (BP, BT; it faces +x), on a grid across one
    region: "straps" (its top, seen from above), "front" or "back" (its panels, the middle of its width,
    from just above its bottom to below its straps, seen from that side). -> (cover, gap) per cell: how
    far its outer and its inner surface stand outside the body's outermost surface there (cover < 0: the
    body shows through it; gap > 0: air between them). Straps: whatever of it lies over the shoulders (the
    body's surface under it higher than shoulders_z, the shoulder joints, and nothing of it hanging down past
    that surface: not the top of a plate in front of the chest). Without shoulders_z: its top STRAP_BAND."""
    empty = (np.array([]), np.array([]))
    zt, zb = W[:, 2].max(), W[:, 2].min()
    h = zt - zb
    if region == "straps":  # (outward: up)
        U = W[W[:, 2] > (shoulders_z - 2.0 * k if shoulders_z is not None else zt - STRAP_BAND * k)]
        B = BP
    else:
        band = W[(W[:, 2] < zt - 0.25 * h) & (W[:, 2] > zb + 0.05 * h)]
        if part is not None:  # (its lower half: the belly; its upper half: the chest)
            zm = (zb + 0.05 * h + zt - 0.25 * h) / 2
            band = band[band[:, 2] < zm] if part == "low" else band[band[:, 2] >= zm]
        if len(band) < 20:
            return empty
        cy = float(np.median(band[:, 1]))
        half = (band[:, 1].max() - band[:, 1].min()) / 2
        band = band[np.abs(band[:, 1] - cy) < 0.6 * half]
        near = BP[(BP[:, 2] < band[:, 2].max()) & (BP[:, 2] > band[:, 2].min()) & (np.abs(BP[:, 1] - cy) < 0.6 * half)]
        if len(band) < 20 or len(near) < 10:
            return empty
        cx = float((near[:, 0].min() + near[:, 0].max()) / 2)
        sgn = 1.0 if region == "front" else -1.0
        side = band[(band[:, 0] - cx) * sgn > 0]
        U = np.c_[side[:, 1], side[:, 2], sgn * side[:, 0]]  # (y, z, outward)
        B = np.c_[BP[:, 1], BP[:, 2], sgn * BP[:, 0]]
    if len(U) < 8:
        return empty
    cell = FIT_CELL * k
    keys, inv = np.unique(np.floor(U[:, :2] / cell).astype(np.int64), axis=0, return_inverse=True)
    inv = inv.ravel()
    outer = np.full(len(keys), -np.inf)
    inner = np.full(len(keys), np.inf)
    np.maximum.at(outer, inv, U[:, 2])
    np.minimum.at(inner, inv, U[:, 2])
    zs, flat = surface_below(B, BT, np.c_[(keys + 0.5) * cell, outer], 10.0 * k, 2.0 * k, slope=True)
    ok = np.isfinite(zs)
    if region == "straps" and shoulders_z is not None:
        # (on the top of the shoulders: not the side of the neck or of a collar, which a strap goes around:
        # the female citizens' collar raised a soft vest 2 units)
        ok &= (zs > shoulders_z) & (inner > zs - 2.0 * k) & (flat > STRAP_FLAT)
    return outer[ok] - zs[ok], inner[ok] - zs[ok]


def zcut(P, T, z):
    """Points where the triangles T of a mesh (vertices P) cross the plane at height z (its outline there)."""
    if fitcore.available() and len(T):
        return fitcore.zcut(P, T, z)
    A, B, C = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    out = []
    for p, q in ((A, B), (B, C), (C, A)):
        dp, dq = p[:, 2] - z, q[:, 2] - z
        m = (dp < 0) != (dq < 0)
        t = (dp[m] / (dp[m] - dq[m]))[:, None]
        out.append(p[m] + t * (q[m] - p[m]))
    return np.concatenate(out) if out else np.zeros((0, 3))


def side_air(W, WT, BP, BT, k=1.0):
    """The air seen from the side between a placed vest (vertices W, triangles WT) and the body as drawn
    (BP, BT; it faces +x), from just above its bottom to below its straps, every half unit of height:
    (front, back) arrays: how far the vest's front stands off the body's foremost point at that height
    (across the vest's width) and its back off the body's rearmost point; > 0: a gap you see from the side
    (the belly, the small of the back), < 0: none (they overlap)."""
    zt, zb = W[:, 2].max(), W[:, 2].min()
    h = zt - zb
    front, back = [], []
    for z in np.arange(zb + 0.05 * h, zt - 0.25 * h, 0.5 * k):
        v, b = zcut(W, WT, z), zcut(BP, BT, z)
        if len(v) < 4:
            continue
        b = b[(b[:, 1] > v[:, 1].min()) & (b[:, 1] < v[:, 1].max())]
        if len(b) < 4:
            continue
        cx = (b[:, 0].min() + b[:, 0].max()) / 2
        vf, vb = v[v[:, 0] > cx], v[v[:, 0] < cx]
        if len(vf):
            front.append(vf[:, 0].min() - b[:, 0].max())
        if len(vb):
            back.append(b[:, 0].min() - vb[:, 0].max())
    return np.array(front), np.array(back)


def strap_support(c, k):
    """The straps' cells that hold them up (cover): all, but for a hood (STRAP_SPREAD, STRAP_OUTLIER)."""
    if len(c) and np.median(c) - np.percentile(c, FIT_SPARE) > STRAP_SPREAD * k:
        return c[c > np.median(c) - STRAP_OUTLIER * k]
    return c


BUST_MAX = 1.0  # (units on the source's body, scaled like it) a bust may go that far into a vest's front


def front_need(W, BP, BT, k):
    """How far a vest's front must move outwards: against the belly (the lower half of the front panel),
    the chest above it allowed into the vest by up to BUST_MAX (the user: "it is no big deal if female
    breast go inside the vest"; resting on the bust, the plate stood 1.5 to 2.5 units off the belly).
    A flat chest needs the same at both heights: nothing changes there."""
    lo, hi = _need(cover(W, BP, BT, "front", k, part="low")[0]), _need(cover(W, BP, BT, "front", k, part="high")[0])
    if lo is None or hi is None:
        return _need(cover(W, BP, BT, "front", k)[0])
    return max(lo, hi - BUST_MAX * k)


def _need(c):
    """How far a region must move outwards for its cover to be FIT_MARGIN but for FIT_SPARE % of it."""
    return float(FIT_MARGIN - np.percentile(c, FIT_SPARE)) if len(c) >= 8 else None


def fit_to_body(V, ztop, xc, model, bone, fit):
    """fit (pos, angles, size[, stretch]) of a vest on model, fitted to its body: -> ((pos, angles, size,
    stretch, depth), (up, forward, depth)). Depth and forward first (both panels against the body), then
    up (the straps on the shoulders), twice (the body's shape changes with the height)."""
    tb = _posed_cache.get(model)
    if tb is None:
        tb = _posed_cache[model] = posed_bones(model)
    k = fit[2]
    st = fit[3] if len(fit) > 3 else 1.0
    dp = fit[4] if len(fit) > 4 else 1.0
    pos = np.asarray(fit[0], dtype=float)
    BP, BT = drawn_mesh(model)
    Rt = tb[bone][0][:3, :3]
    sh = sum(tb[u][0][2, 3] for u in UPPERARMS) / 2 if all(u in tb for u in UPPERARMS) else None
    up_t = fwd_t = 0.0

    def at(p, d):
        return placed_vest(V, ztop, xc, model, bone, (p, fit[1], k, st, d))

    for _ in range(2):
        if xc is not None:
            W0, W1 = at(pos, dp), at(pos, dp + 0.1)
            nf0, nb0 = front_need(W0, BP, BT, k), _need(cover(W0, BP, BT, "back", k)[0])
            nf1, nb1 = front_need(W1, BP, BT, k), _need(cover(W1, BP, BT, "back", k)[0])
            if None not in (nf0, nb0, nf1, nb1):
                dnf, dnb = (nf1 - nf0) / 0.1, (nb1 - nb0) / 0.1  # (deeper: both need less)
                d = dp
                if dnf + dnb < -1e-3:  # both panels against the body: their needs add up to 0
                    d = float(np.clip(dp - (nf0 + nb0) / (dnf + dnb), *DEPTH_RANGE))
                # forward by m: the front's need goes down by m, the back's up by m (the same miss both sides)
                m = ((nf0 + dnf * (d - dp)) - (nb0 + dnb * (d - dp))) / 2
                m = float(np.clip(fwd_t + m, -DEPTH_MOVE * k, DEPTH_MOVE * k)) - fwd_t
                pos, dp, fwd_t = pos + Rt.T @ np.array([m, 0.0, 0.0]), d, fwd_t + m
            elif nf0 is not None or nb0 is not None:
                # only a front (a holster on the hip, it floated 2 units off the belly) or only a back: moved
                # against the body, not made deeper (that needs both)
                m = nf0 if nf0 is not None else -nb0
                m = float(np.clip(fwd_t + m, -DEPTH_MOVE * k, DEPTH_MOVE * k)) - fwd_t
                pos, fwd_t = pos + Rt.T @ np.array([m, 0.0, 0.0]), fwd_t + m
        if sh is not None:
            n = _need(strap_support(cover(at(pos, dp), BP, BT, "straps", k, sh)[0], k))
            if n is not None:
                u = float(np.clip(up_t + n, -REST_MAX * k, REST_MAX * k)) - up_t
                pos, up_t = pos + Rt.T @ np.array([0.0, 0.0, u]), up_t + u
    return (pos, fit[1], k, st, round(float(dp), 3)), (round(up_t, 2), round(fwd_t, 2), round(float(dp), 3))


def tilted(fit, deg, ztop, xc):
    """fit turned by deg about the vest's lateral axis through its straps (its model's y at stretch_top,
    depth_center): its bottom forward (> 0) or back."""
    a = math.radians(deg)
    Ry = np.array([[math.cos(a), 0.0, math.sin(a)], [0.0, 1.0, 0.0], [-math.sin(a), 0.0, math.cos(a)]])
    R = angle_matrix(fit[1])
    c = np.array([xc or 0.0, 0.0, ztop])
    pos = np.asarray(fit[0], dtype=float) + R @ (c - Ry @ c) * fit[2]
    return (pos, fi.matrix_angles(R @ Ry)) + tuple(fit[2:])


def fit_vest(V, T, ztop, xc, model, bone, fit, tall=True):
    """fit_to_body, then, when a gap seen from the side is left (side_air: the belly under a bust, the
    small of the back), the same tilted a little (TILTS) if that leaves less: -> (fit, (up, forward,
    depth, tilt, air left))."""
    BP, BT = drawn_mesh(model)

    def score(f):  # the widest gap seen from the side, and 0.4 more per % of the panels the body shows through
        W = placed_vest(V, ztop, xc, model, bone, f)
        fa, ba = side_air(W, T, BP, BT, f[2])
        air = max(float(fa.max()) if len(fa) else 0.0, float(ba.max()) if len(ba) else 0.0)
        show = [cover(W, BP, BT, "front", f[2], part="low")[0], cover(W, BP, BT, "back", f[2])[0]]  # (a bust may go in)
        return air + 0.4 * sum(max(0.0, float((c < 0).mean() * 100) - FIT_SPARE) for c in show if len(c))

    best, moved = fit_to_body(V, ztop, xc, model, bone, fit)
    air, tilt = score(best), 0.0
    if T is not None and air > AIR_OK:
        for deg in (TILTS if tall else TILTS_SMALL):
            f, m = fit_to_body(V, ztop, xc, model, bone, tilted(fit, deg, ztop, xc))
            a = score(f)
            if a < air - 0.05:
                best, moved, air, tilt = f, m, a, deg
            if air <= AIR_OK:
                break
    return best, moved + (tilt, round(air, 2))


def lua_vec(v, n=2):
    return "Vector(" + _nz(", ".join(f"{x:.{n}f}" for x in v)) + ")"


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def backpack_depth(G, body, face):
    """How far a worn backpack (vertices G) sticks out behind the soldier's back (body vertices, facing
    yaw face in degrees): weapons carried on the back go over it by that much. Measured straight behind
    him, the back surface taken near his middle (not the arms); a roll worn across the body counts where
    it crosses the back."""
    d = -np.array([math.cos(math.radians(face)), math.sin(math.radians(face)), 0.0])
    zlo, zhi = G[:, 2].min(), G[:, 2].max()
    B = body[(body[:, 2] > zlo) & (body[:, 2] < zhi)]
    lat = np.cross([0.0, 0.0, 1.0], d)
    c = B.mean(0)
    near = B[np.abs((B - c) @ lat) < 6]
    back = G[np.abs((G - c) @ lat) < 6]  # the pack behind his middle
    if not len(back):
        return 0.0, 0.0
    surface = (near @ d).max()
    depth = max(0.0, float((back @ d).max() - surface))
    # its half width behind the back (straps over the shoulders left out): a rifle slung over the
    # shoulder hangs beside it
    behind = G[(G @ d) > surface + 1.0]
    half = float(np.abs((behind - c) @ lat).max()) if len(behind) else 0.0
    return depth, half


def gear_mesh(pack, cls):
    """An item's worn look alone (the fit editor's mesh): the pack's playermodel in its reference pose,
    only the triangles of that item's bodygroups, its vertices renumbered. -> (pos, nrm, uv, tris, mats)"""
    draw = pack["models"][0]
    parts = bodyparts(draw)
    empty = empty_choices(parts)
    base = {b: empty.get(b, 0) for b in range(len(parts))}
    base_tris = {tuple(t) for t in posed(draw, base)[3]}
    it = next(i for i in pack["items"] if i["class"] == cls)
    sel = dict(base)
    for part, sub in it["show"]:
        b, s = find(parts, part, sub)
        sel[b] = s
    P, N, uv, tris, mats = posed(draw, sel)
    keep = [t for t in tris if tuple(t) not in base_tris]
    used = sorted({t[k] for t in keep for k in range(3)})
    new = {v: k for k, v in enumerate(used)}
    return P[used], N[used], uv[used], [(new[t[0]], new[t[1]], new[t[2]], t[3]) for t in keep], mats


def main():
    args = sys.argv[1:]
    preview = None
    if "--preview" in args:
        k = args.index("--preview")
        preview = args[k + 1]
        del args[k:k + 2]
    pack = PACKS[args[0]]
    if pack.get("bind_positions"):  # (the game draws them with their bind positions: anim0.py)
        anim0.BIND_POSITIONS.update(m.lower() for m in pack["models"])
    targets = [l.strip() for l in Path(args[1]).read_text(encoding="utf-8").splitlines() if l.strip()]
    out = Path(args[2])
    draw = pack["models"][0]
    parts = bodyparts(draw)
    empty = empty_choices(parts)
    base = {b: empty.get(b, 0) for b in range(len(parts))}
    P0, _N0, _uv0, tris0, _m0 = posed(draw, base)
    base_tris = {tuple(t) for t in tris0}
    body = P0[sorted({t[k] for t in tris0 for k in range(3)})]  # the soldier himself (no gear)
    face = 0.0  # posed as the game animates it, the soldier faces +x (his reference pose faces -y)
    hidden = sorted({t[3] for t in tris0})  # what the empty selection still draws: the parts with no empty choice
    blocked = builtin_gear.builtin()
    items = []
    for it in pack["items"]:
        bgs, stored = {}, {}
        for part, sub in it["show"]:
            b, s = find(parts, part, sub)
            bgs[b] = s
        for part, sub in it.get("stored", it["show"]):
            b, s = find(parts, part, sub)
            stored[b] = s
        sel = {**base, **stored}  # the look on the ground: its centre and hull
        P, _N, _uv, tris, _mats = posed(draw, sel)
        keep = [t for t in tris if tuple(t) not in base_tris]  # the gear's own triangles
        # gear on a material the body also uses (hidden with it): the game draws those triangles apart,
        # read from the installed model (sh_modelgear_items.lua, I.SharedPartsMesh)
        shared_stored = bool({t[3] for t in keep} & set(hidden))
        used = sorted({t[k] for t in keep for k in range(3)})
        pieces = split_pieces(P[used]) if it.get("stored") and not shared_stored else None
        if it.get("stored_cut") is not None:  # stored: only below that fraction of its height (straps cut away)
            z0, z1 = P[used][:, 2].min(), P[used][:, 2].max()
            zc = z0 + it["stored_cut"] * (z1 - z0)
            keep = [t for t in keep if min(P[t[k]][2] for k in range(3)) <= zc]
            used = sorted({v for t in keep for v in t[:3] if P[v][2] <= zc})
            pieces = [(np.array([0.0, 0.0, -1.0]), -zc, np.zeros(3))]  # one piece: the side below the plane
        if pieces:  # drawn in two halves, cut in the gap between them and pushed together
            P = P.copy()
            for normal, dist, off in pieces:
                side = [v for v in used if P[v] @ normal > dist]
                P[side] += off
        V = P[used]
        center = (V.min(0) + V.max(0)) / 2
        hull = hull_points(V - center)
        # the gear as worn (its straps too): its box in the model's space, to frame a character wearing it
        Pw, _Nw, _uvw, trisw, _mw = posed(draw, {**base, **bgs})
        wt = [t for t in trisw if tuple(t) not in base_tris]
        shared_worn = bool({t[3] for t in wt} & set(hidden))
        wv = sorted({t[k] for t in wt for k in range(3)})
        wi = {v: n for n, v in enumerate(wv)}
        worn_T = np.array([[wi[t[0]], wi[t[1]], wi[t[2]]] for t in wt], dtype=np.int64).reshape(-1, 3)
        worn_box = (Pw[wv].min(0), Pw[wv].max(0))
        worn_z = float(np.median(Pw[wv][:, 2]))
        back_depth, back_half = backpack_depth(Pw[wv], body, face) if it["slot"] == "Rucksack" else (None, None)
        # a vest drawn as one piece stretches downwards from its top on bodies longer than wide (not one bonemerged,
        # nor one with parts on the body's material, drawn apart)
        stretch_top = float(worn_box[1][2]) if it["slot"] == "Vest" and not it.get("rigged") and not shared_worn else None
        items.append({**it, "stretch_top": stretch_top, "sel": sel, "bgs": bgs, "stored_bgs": stored, "V": V, "P": P, "tris": keep, "center": center,
                      "hull": hull, "pieces": pieces, "worn_box": worn_box, "back_depth": back_depth,
                      "shared": [k for k, s in (("stored", shared_stored), ("worn", shared_worn)) if s],
                      "worn_z": worn_z, "worn_V": Pw[wv] if stretch_top is not None else None, "worn_T": worn_T,
                      "depth_center": float((worn_box[0][0] + worn_box[1][0]) / 2) if stretch_top is not None else None,
                      "back_half_width": back_half})
        print(f"{it['class']:40} {len(keep):5} triangles, {len(hull):2} hull points, size {np.round(V.max(0) - V.min(0), 1)}"
              f"{'  in 2 pieces' if pieces else ''}{f'  {back_depth:.1f} behind the back, {back_half:.1f} half wide' if back_depth else ''}"
              f"{'  parts on the body material (' + ', '.join(items[-1]['shared']) + ')' if items[-1]['shared'] else ''}")
    if preview:
        write_preview(draw, items, preview)

    # fits: transferred from the pack's playermodel to every target
    mr.BODYGROUPS[draw.lower()] = dict(base)  # the soldier himself, no gear (posed() leaves its last selection)
    src = fi.Body(draw)
    src_bones = posed_bones(draw)
    # torso gear of a pack drawn in its bind pose (anim0.BIND_POSITIONS): placed as it looks on its own
    # soldier in game, animated (the animation stretches his spine, and a vest spread over the spine
    # bones with it); head gear follows the head bone rigidly: placed from the pose the copy is drawn in
    torso_bones = src_bones
    if pack.get("bind_positions"):
        anim0.BIND_POSITIONS.difference_update(m.lower() for m in pack["models"])
        torso_bones = posed_bones(draw)
        anim0.BIND_POSITIONS.update(m.lower() for m in pack["models"])
    src_girth = fc.chest_girth(src)
    torso = abs(torso_bones[NECK][0][2, 3] - torso_bones[PELVIS][0][2, 3]) if NECK in torso_bones and PELVIS in torso_bones else 0
    for it in items:
        it["height"] = gear_height(src, it["worn_z"])
        # stretched to the torso's length only if it runs down the torso: its top up on the chest (a vest,
        # webbing), not a holster or a pouch hanging from a belt (a holster 9.7 high was stretched)
        pz = torso_bones[PELVIS][0][2, 3] if PELVIS in torso_bones else 0.0
        it["tall"] = not torso or float(it["worn_box"][1][2] - pz) >= TALL * torso
    fits = {it["class"]: {} for it in items}
    for m in targets:
        try:
            body = fi.Body(m)
        except Exception as e:  # noqa: BLE001
            print(f"{m}: skipped ({e})")
            continue
        for it in items:
            if m.lower() in blocked.get(it["slot"], ()):
                continue
            try:
                if it["slot"] in HEAD_SLOTS:
                    if body.eyes is None or not body.has(fi.HEAD) or len(body.verts([fi.HEAD])) <= 20:
                        continue
                    fits[it["class"]][m] = transfer_helmet(src, src_bones, it["V"], body, it.get("lift", 0.0))
                else:
                    bone = BONE[it["slot"]]
                    if not body.has(bone, NECK) or len(body.verts(fi.TORSO)) < 50:
                        continue
                    fit = transfer_torso(src, torso_bones, bone, body, src_girth, it["height"],
                                         it.get("drop", 0.0), it["worn_z"], it.get("stretch_top"), it.get("tall", True))
                    LEVEL_LOG.append((it["class"], m, LAST_UP))
                    if FIT and it.get("worn_V") is not None:  # against the body, straps on the shoulders
                        fit, moved = fit_vest(it["worn_V"], it.get("worn_T"), it["stretch_top"], it["depth_center"], m,
                                              bone, fit, it.get("tall", True))
                        FIT_LOG.append((it["class"], m) + moved + ("fit",))
                    fits[it["class"]][m] = fit
            except Exception as e:  # noqa: BLE001
                print(f"  {it['class']} on {m}: {e}")
    # fits approved in the fit editor are final (tools/fit_locks.txt)
    locks = fit_locks.load()
    # a vest fitted to the body: Claude's approvals give way to its new fit, the user's stay as approved
    by = fit_locks.approvers()
    for it in items:
        per = fits[it["class"]]
        stretchy = it.get("stretch_top") is not None
        for m in list(per):
            lk = fit_locks.get(locks, it["class"], m)
            if lk is None:
                continue
            key = (it["class"], m.lower())
            if stretchy and by.get(key) == "claude":
                # Claude's own approvals (stamped or adjusted under the earlier rules) give way to the fit
                # against the body, the user's standard (one adjusted by hand left a holster 8 units off the
                # belly the new fit couldn't bring back); the user's stay final
                continue
            per[m] = lk
    for it in items:
        it["attach"] = fits[it["class"]].get(fi.REF)
    # the pack's own playermodels: the bodygroups that show each item there
    own = {}
    for m in pack["models"]:
        pm_parts = bodyparts(m)
        own[m] = {it["class"]: {find(pm_parts, part, sub)[0]: find(pm_parts, part, sub)[1] for part, sub in it["show"]}
                  for it in items}
    write_lua(pack, draw, base, hidden, items, own, targets, fits, out)


def write_preview(draw, items, path):
    import mount_check as mc  # noqa: E402
    from PIL import Image, ImageDraw
    face = mc.facing_yaw(draw)
    S = 220
    sheet = Image.new("RGB", (S * 2 * 3, (S + 20) * ((len(items) + 2) // 3)), (24, 24, 26))
    d = ImageDraw.Draw(sheet)
    for k, it in enumerate(items):
        _P, N, uv, tris, mats = posed(draw, it["sel"])
        P = it["P"]  # (moved pieces included)
        scene = (P, N, uv, it["tris"], mats)
        x, y = (k % 3) * 2 * S, (k // 3) * (S + 20)
        for v, yaw in enumerate((35, 200)):
            img = mr.rasterize(*scene, face + yaw, 15, it["V"], size=S)
            bg = Image.new("RGBA", img.size, (78, 82, 90, 255))
            bg.alpha_composite(img)
            sheet.paste(bg.convert("RGB"), (x + v * S, y))
        d.text((x + 4, y + S + 3), f"{it['class']}  {it['name'][0]}", fill=(240, 220, 120))
    sheet.save(path, quality=90)


def write_lua(pack, draw, base, hidden, items, own, targets, fits, out):
    L = [f"-- {pack['title']}: its gear as Advanced Inventory System items. Generated by",
         "-- advanced-inventory/tools/modelgear_pack.py (do not edit by hand). The gear is drawn with the",
         "-- playermodel addon's own model (Workshop " + pack["wid"] + "): nothing of it is shipped here.",
         "AdvInv = AdvInv or {}",
         "AdvInv.ModelGearPacks = AdvInv.ModelGearPacks or {}",
         "local pack = {",
         f"    key = {lua_str(pack['key'])}, title = {lua_str(pack['title'])}, wid = \"{pack['wid']}\",",
         f"    author = {lua_str(pack['author'])},",
         f"    category = {{ {lua_str(pack['category'][0])}, {lua_str(pack['category'][1])} }},",
         f"    model = {lua_str(draw.lower())},",
         "    blank = { " + ", ".join(f"[{b}] = {v}" for b, v in sorted(base.items())) + " },",
         "    hide = { " + ", ".join(str(h) for h in hidden) + " },",
         "    items = {"]
    for it in items:
        a = it["attach"]
        L.append(f"        {{ class = {lua_str(it['class'])}, slot = \"{it['slot']}\", name = {{ {lua_str(it['name'][0])}, {lua_str(it['name'][1])} }},")
        L.append(f"          mass = {it['mass']}, armor = {it.get('armor', 0)}, load = {it.get('load', 0)},")
        L.append("          bodygroups = { " + ", ".join(f"[{b}] = {v}" for b, v in sorted(it["bgs"].items())) + " },")
        if it["stored_bgs"] != it["bgs"]:
            L.append("          stored = { " + ", ".join(f"[{b}] = {v}" for b, v in sorted(it["stored_bgs"].items())) + " },")
        if it["pieces"]:  # { normal, distance, move }: a clip plane in the model's space, and its side's move
            L.append("          pieces = { " + ", ".join(f"{{ {lua_vec(n, 0)}, {d:.3f}, {lua_vec(o, 3)} }}" for n, d, o in it["pieces"]) + " },")
        L.append(f"          origin = {lua_vec(it['center'], 3)},")
        L.append("          hull = { " + ", ".join(lua_vec(h, 2) for h in it["hull"]) + " },")
        L.append(f"          worn_box = {{ {lua_vec(it['worn_box'][0], 1)}, {lua_vec(it['worn_box'][1], 1)} }},")
        if it.get("stretch_top") is not None:
            L.append(f"          stretch_top = {it['stretch_top']:.2f}, -- (a fit's 8th number stretches it downwards from there)")
        if it.get("depth_center") is not None:
            L.append(f"          depth_center = {it['depth_center']:.2f}, -- (a fit's 9th number: its depth, around there)")
        if it.get("rigged"):  # bonemerged on the wearer (parts on the legs follow them): no rigid fit
            L.append("          rigged = true,")
        if it["shared"]:  # looks with parts on a material of the hidden body: drawn apart by the game
            L.append("          shared = { " + ", ".join(f"{k} = true" for k in it["shared"]) + " },")
        if it["back_depth"]:  # (a backpack: weapons carried on the back go over it by that much)
            L.append(f"          back_depth = {it['back_depth']:.1f}, back_half_width = {it['back_half_width']:.1f},")
        if a is not None:
            L.append(f"          attach = {{ bone = \"{BONE[it['slot']]}\", pos = {lua_vec(a[0])}, ang = Angle({a[1][0]:.1f}, {a[1][1]:.1f}, {a[1][2]:.1f}), scale = {a[2]:g} }},")
        L.append("          on = {")
        for m, per in own.items():
            L.append(f"              [{lua_str(m.lower())}] = {{ " + ", ".join(f"[{b}] = {v}" for b, v in sorted(per[it['class']].items())) + " },")
        L.append("          } },")
    L.append("    },")
    L.append("    fits = {")
    L.append("        models = {")
    L += [f"            {lua_str(m.lower())}," for m in targets]
    L.append("        },")
    L.append("        items = {")
    for it in items:
        parts = []
        for m in targets:
            f = fits[it["class"]].get(m)
            if f is None:
                parts.append("")
                continue
            p, ang, s = f[:3]
            st = f[3] if len(f) > 3 else 1.0
            dp = f[4] if len(f) > 4 else 1.0
            extra = [f"{st:g}", f"{dp:g}"] if abs(dp - 1) > 0.004 else [f"{st:g}"] if abs(st - 1) > 0.004 else []
            parts.append(_nz(" ".join([f"{x:.2f}" for x in p] + [f"{x:.1f}" for x in ang] + [f"{s:g}"] + extra)))
        L.append(f"            [{lua_str(it['class'])}] = \"{'|'.join(parts)}\",")
    L.append("        },")
    L.append("    },")
    L.append("}")
    L.append("if AdvInv.AddModelGearPack then AdvInv.AddModelGearPack(pack) else table.insert(AdvInv.ModelGearPacks, pack) end")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(L) + "\n", encoding="utf-8", newline="\n")
    print(f"-> {out} ({out.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
