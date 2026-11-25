"""Carry-mode offsets of the long guns for every default playermodel (dev tool, not in the .gma).

Writes lua/advinv/cl_carry_data.lua:
  - AdvInv.CarryOffsets[set][weapon class][mode] = { bone, position, angles, outward }:
    where the weapon model goes on the bone (like ENT.Attach), and the direction away from the body
    (worn gear pushes the weapon along it);
  - AdvInv.CarryAliases[playermodel] = set: models with the same proportions share a set;
    "default" (male_07) is used for any other playermodel;
  - AdvInv.CarryTemplates[mode]: placement rules for weapons that have no offsets (another
    addon's), applied at run time with the weapon's own shape (cl_carry.lua);
  - AdvInv.CarryStack[set]: when the launcher and the primary weapon cross on the back side,
    which one goes over the other and by how much;
  - AdvInv.CarryDefaultModels: the base game's playermodels (for advinv_carry_cycle).

Each mode gives the gun's direction, the side of the body it rests on and where it sits; the gun
is then lowered onto the body along that side until its main body touches it (contact solved on a
grid over its footprint, arms left out since they move): no clipping in the reference pose, except
small parts sticking out sideways (Weapon.Pc).
A model joins an existing set only if that set's offsets fit it without clipping and within
ALIAS_TOL units of its own fit.

    python fit_carry.py [models.txt]     (default: playermodels.txt, the base game's list)
    python fit_carry.py --current        (the playermodels cl_carry_data.lua already has)
    --jobs N: processes fitting the playermodels (default: up to 8), at below normal priority.
Tuned values (advinv_carry_tune, saved in garrysmod/data/advinv_carry_tuned.json) can be copied to
tools/carry_overrides.json: they replace the computed offsets of their set / weapon / mode.
"""
import json
import math
import os
import sys
from multiprocessing import Pool
from pathlib import Path
from types import SimpleNamespace

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import anim0  # noqa: E402
import fit_items as fi  # noqa: E402
import mdl_render as mr  # noqa: E402

TOOLS = Path(__file__).resolve().parent
OUT = TOOLS.parent / "lua" / "advinv" / "cl_carry_data.lua"
OVERRIDES = TOOLS / "carry_overrides.json"
REF = "models/player/group01/male_07.mdl"
GAP = 0.3          # room between the weapon and the body
CELL = 0.75        # contact grid (units)
ALIAS_TOL = 1.0    # max difference (weapon corners, units) to share another model's set
JOBS = min(8, os.cpu_count() or 1)  # processes fitting the playermodels (--jobs N)
TURN_RATIO = 1.25  # a weapon model longer along Y than X by this: its barrel lies along Y
# model -> barrel along X, top up (cl_weapons.lua: the same). Such models (the Sandstorm SWEPs, posed by
# their idle animation) lie upside down too: all 27 of that pack were, their sights towards -Z
TURN = np.array([[0, 1.0, 0], [1, 0, 0], [0, 0, -1]])
ARMS = ("UpperArm", "Forearm", "Hand", "Finger", "Wrist", "Ulna", "Elbow", "Bicep")

WEAPONS = {  # class: (model, modes)
    "weapon_smg1": ("models/weapons/w_smg1.mdl", None),
    "weapon_ar2": ("models/weapons/w_irifle.mdl", None),
    "weapon_shotgun": ("models/weapons/w_shotgun.mdl", None),
    "weapon_crossbow": ("models/weapons/w_crossbow.mdl", None),
    "weapon_rpg": ("models/weapons/w_rocket_launcher.mdl", ("sling_up",)),
}
# other addons' long guns, set offline in the fit editor like these (tools/carry_weapons.txt, made by
# carry_weapons.py scan): the game uses their offsets by weapon class instead of the mode's template
import carry_weapons  # noqa: E402
for _cls, _slot, _model, _name in carry_weapons.load():
    WEAPONS.setdefault(_cls, (_model, ("sling_up",) if _slot == "RocketLauncher" else None))
MODES = ("sling_up", "sling_down", "front_hang")  # (back_carry, cross_body: removed, 23/11; sling_down is the back carry)
# weapons without offsets (templates): the point of the gun that keeps its place (default: its middle)
TEMPLATE_ANCHOR = {"sling_down": "butt"}
BONES = {"sling_up": "ValveBiped.Bip01_Spine4", "sling_down": "ValveBiped.Bip01_Spine4",
         "front_hang": "ValveBiped.Bip01_Spine4"}


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


# ---------------------------------------------------------------- weapons in a canonical frame

class Weapon:
    """Weapon mesh turned so that X = towards the muzzle, Y = its thinnest side (rests on the
    body), Z = the other side (its top for most guns). Q: model space -> canonical.
    Pc: the points of its main body, the band across Y that holds 90 % of its surface (like the
    game's I.WeaponGeometry core): only they rest on the body. Parts sticking out sideways (the
    AR2's disc) may sink into it; counting them would hold the whole gun off the body."""

    def __init__(self, model):
        pos, _, _, tris, _ = anim0.posed_mesh(model, textures=False)
        used = sorted({t[k] for t in tris for k in range(3)})
        P = pos[used]
        Q = np.eye(3)
        ext = P.max(0) - P.min(0)
        if ext[1] > TURN_RATIO * ext[0]:  # barrel along Y at rest (the Sandstorm SWEPs: their idle animation
            Q = TURN.copy()                # turns the hand bone): turned first (as the game's I.WeaponGeometry)
        if self._muzzle_back(model, P, Q):
            Q = np.diag([-1.0, -1.0, 1.0]) @ Q
        Pq = P @ Q.T
        core = lambda ax: np.percentile(Pq[:, ax], 95) - np.percentile(Pq[:, ax], 5)
        if core(1) > core(2):  # thinner along Z (a crossbow's limbs): roll it 90 degrees
            Q = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0.0]]) @ Q
        self.Q = Q
        self.P = P @ Q.T
        self.mn, self.mx = self.P.min(0), self.P.max(0)
        self.length = self.mx[0] - self.mn[0]
        # main body: area-weighted 5-95 % band of triangle centres across Y
        T = np.array([[t[0], t[1], t[2]] for t in tris])
        A, B, C = (pos[T[:, k]] @ Q.T for k in range(3))
        area = np.linalg.norm(np.cross(B - A, C - A), axis=1) / 2
        cy = (A[:, 1] + B[:, 1] + C[:, 1]) / 3
        o = np.argsort(cy)
        cum = np.cumsum(area[o]) / area.sum()
        lo, hi = cy[o][np.searchsorted(cum, 0.05)], cy[o][min(np.searchsorted(cum, 0.95), len(o) - 1)]
        self.core_y = (lo, hi)
        self.Pc = self.P[(self.P[:, 1] >= lo - 0.25) & (self.P[:, 1] <= hi + 0.25)]

    @staticmethod
    def _muzzle_back(model, P, Q):
        import studio  # noqa: E402
        m = studio.Model(mr.vpk_read(model))
        W = anim0.rest_bones(model)
        for a in m.attachments:
            if a["name"].lower() == "muzzle":
                L = np.vstack([a["local"], [0, 0, 0, 1]])
                x = Q @ (W[a["bone"]] @ L)[:3, 3]
                Px = P @ Q[0]
                return x[0] < (Px.min() + Px.max()) / 2
        return False


# ---------------------------------------------------------------- bodies

class Carrier(fi.Body):
    def __init__(self, model):
        super().__init__(model)
        keep = np.array([not any(a in self.names[d] for a in ARMS) for d in self.dom])
        self.solid = self.P[keep]  # everything but the arms

    def z_of(self, bone):
        return self.world[bone][:3, 3][2]

    def shoulder_z(self):
        ids = [self.names.index(n) for n in ("ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_R_Clavicle")
               if n in self.names]
        v = self.P[np.isin(self.dom, ids)]
        v = v[(v[:, 0] < -3) & (v[:, 0] > -8)]
        return v[:, 2].max() if len(v) else self.z_of("ValveBiped.Bip01_Spine4") + 6

    def half_width(self, z):
        t = self.verts(fi.TORSO)
        band = t[np.abs(t[:, 2] - z) < 2]
        return np.abs(band[:, 0]).max() if len(band) else 7.0


def place(body, w, d, n, top_hint, ref_point, target):
    """Weapon w with its muzzle along d, resting on the body side n (outward), top towards
    top_hint; its canonical point ref_point goes over the model-space point target (in the plane
    across n), then it is lowered along n onto the body. -> (R, t, clearance) in model space."""
    d, n = unit(d), unit(n)
    n = unit(n - d * (n @ d))
    for s in (1.0, -1.0):
        R = np.column_stack([d, s * n, np.cross(d, s * n)])
        if R[:, 2] @ np.asarray(top_hint, float) >= 0:
            break
    W = w.Pc @ R.T
    # in-plane position: ref_point over target
    t = np.asarray(target, float) - R @ np.asarray(ref_point, float)
    t = t - n * ((t - target) @ n)  # n-coordinate decided by the contact below
    a1 = unit(np.cross(n, d))
    def grid(points):
        return np.floor(np.c_[points @ d, points @ a1] / CELL).astype(int)
    inner, outer = cell_extremes(grid(W + t), W @ n, grid(body.solid), body.solid @ n)
    if len(outer):
        need = (outer - inner).max() + GAP
    else:  # nothing under the weapon: put it at the target
        need = np.asarray(target, float) @ n - (R @ np.asarray(ref_point, float)) @ n
    t = t + n * (need - t @ n)
    clear = ((t @ n + inner) - outer).min() if len(outer) else None
    return R, t, clear


def cell_extremes(wc, wn, bc, bn):
    """On the contact grid: for each cell holding both weapon and body points, the weapon's lowest
    point (inner) and the body's highest (outer) along the resting side. wc, bc: (N, 2) cells of the
    points, wn, bn: their heights. -> (inner, outer), same cells in the same order."""
    lo, hi = wc.min(0), wc.max(0)
    nj = hi[1] - lo[1] + 1
    size = (hi[0] - lo[0] + 1) * nj
    inner = np.full(size, np.inf)
    np.minimum.at(inner, (wc[:, 0] - lo[0]) * nj + (wc[:, 1] - lo[1]), wn)
    m = np.all((bc >= lo) & (bc <= hi), axis=1)  # body points within the weapon's footprint box
    outer = np.full(size, -np.inf)
    np.maximum.at(outer, (bc[m, 0] - lo[0]) * nj + (bc[m, 1] - lo[1]), bn[m])
    both = np.isfinite(inner) & np.isfinite(outer)
    return inner[both], outer[both]


def modes_for(body, w):
    """Model-space placement (R, t, clearance, outward) of weapon w for each mode on body."""
    out = {}
    L = w.length
    sh = body.shoulder_z()
    s2, s4 = body.z_of("ValveBiped.Bip01_Spine2"), body.z_of("ValveBiped.Bip01_Spine4")
    pelvis = body.z_of("ValveBiped.Bip01_Pelvis")
    hw = body.half_width(s4)
    centre = (w.mn + w.mx) / 2
    muzzle_tip = np.array([w.mx[0], centre[1], centre[2]])
    stock_tip = np.array([w.mn[0], centre[1], centre[2]])
    # from the right shoulder, muzzle up: behind the right shoulder blade, muzzle above the shoulder
    n_sh = unit((-0.3, 1, 0))
    x_sh = -0.55 * hw
    out["sling_up"] = place(body, w, (-0.12, 0.08, 1), n_sh, (-1, 0, 0), muzzle_tip,
                            (x_sh, 0, sh + 0.15 * L)) + (n_sh,)
    # The back carry (sling_down): the cross-body carry, muzzle down, of the USMC weapons carries
    # (0300-M16-1004, p. 19): the sling across the chest, the gun flat on the back, about 13 degrees
    # off the vertical.
    back = np.array([0, 1.0, 0])
    tilt = math.radians(13)
    # muzzle down: the butt behind the left shoulder blade, the muzzle down towards the right calf,
    # its top (the sights) towards the right
    out["sling_down"] = place(body, w, (-math.sin(tilt), 0, -math.cos(tilt)), back, (-1, 0, 0), stock_tip,
                              (0.75 * hw, 0, sh - 2)) + (back,)
    # in front of the chest and belly, hands free: diagonal, stock at the right chest, muzzle down left
    out["front_hang"] = place(body, w, (0.71, 0, -0.71), (0, -1, 0), (0, 0, 1), centre,
                              (0, 0, s2 - 2)) + (np.array([0, -1.0, 0]),)
    return out


def to_bone(body, bone, w, R, t, n):
    """Model-space placement of the canonical weapon -> FollowBone values for the weapon MODEL."""
    Rm = R @ w.Q  # weapon model space -> body model space
    Bw = body.world[bone]
    Li = np.linalg.inv(Bw)
    pos = Li[:3, :3] @ t + Li[:3, 3]
    return pos, fi.matrix_angles(Li[:3, :3] @ Rm), Li[:3, :3] @ n


def corners(w):
    if getattr(w, "_corners", None) is None:  # (once per weapon: the set checks ask for them thousands of times)
        mn, mx = w.P.min(0), w.P.max(0)
        w._corners = np.array([[x, y, z] for x in (mn[0], mx[0]) for y in (mn[1], mx[1]) for z in (mn[2], mx[2])])
    return w._corners


def model_points(w):
    """The weapon's canonical points and corners in its model space (once per weapon)."""
    if getattr(w, "_model_points", None) is None:
        Qi = np.linalg.inv(w.Q).T
        w._model_points = (w.Pc @ Qi, corners(w) @ Qi)
    return w._model_points


# ---------------------------------------------------------------- run

def fit_model(model, weapons):
    body = Carrier(model)
    if not body.has(*BONES.values(), "ValveBiped.Bip01_R_Clavicle"):
        return None, None
    res = {}
    for cls, (wpath, allowed) in WEAPONS.items():
        w = weapons[cls]
        placed = modes_for(body, w)
        res[cls] = {}
        for mode in (allowed or MODES):
            R, t, clear, n = placed[mode]
            pos, ang, out = to_bone(body, BONES[mode], w, R, t, n)
            res[cls][mode] = {"bone": BONES[mode], "pos": pos, "ang": ang, "out": out, "clear": clear,
                              "R": R, "t": t, "n": n}
    return body, res


def model_space(body, w, e):
    """Corners of the weapon placed by bone-relative values e on body (model space)."""
    Bw = body.world[e["bone"]]
    Rm = Bw[:3, :3] @ mr.rot_matrix(*e["ang"])
    t = Bw[:3, :3] @ e["pos"] + Bw[:3, 3]
    C = model_points(w)[1]  # canonical corners -> weapon model space
    return C @ Rm.T + t, Rm, t


def placed_points(body, w, e):
    """Weapon vertices placed by bone-relative values e on body (model space)."""
    Bw = body.world[e["bone"]]
    Rm = Bw[:3, :3] @ mr.rot_matrix(*e["ang"])
    return model_points(w)[0] @ Rm.T + Bw[:3, :3] @ e["pos"] + Bw[:3, 3]


def penetration(body, w, e, solid=None):
    """How far the weapon placed by e goes into body (or into the points solid) along its resting
    side, <= 0 when clear."""
    if solid is None:
        solid = body.solid
    Bw = body.world[e["bone"]]
    Rm = Bw[:3, :3] @ mr.rot_matrix(*e["ang"])
    t = Bw[:3, :3] @ e["pos"] + Bw[:3, 3]
    W = model_points(w)[0] @ Rm.T + t
    n = unit(Bw[:3, :3] @ e["out"])
    d = unit(Rm @ (w.Q.T @ np.array([1.0, 0, 0])))
    a1 = unit(np.cross(n, d))
    g = lambda pts: np.floor(np.c_[pts @ d, pts @ a1] / CELL).astype(int)
    inner, outer = cell_extremes(g(W), W @ n, g(solid), solid @ n)
    return (outer - inner).max() if len(outer) else -np.inf


BACK_SIDE = {"sling_up", "sling_down"}


def stacking(body, weapons, res):
    """When the launcher and the primary weapon are both carried on the back side and cross, one
    goes over the other: whichever needs the smaller push along its outward direction.
    { "rpg mode|primary class mode": push } with push > 0: the launcher moves out, < 0: the primary
    weapon moves out by -push."""
    out = {}
    zone = {"sling_up": "shoulder", "sling_down": "back"}
    for lmode, le in res["weapon_rpg"].items():
        for cls, modes in res.items():
            if cls == "weapon_rpg":
                continue
            for pmode, pe in modes.items():
                if pmode not in BACK_SIDE or lmode not in BACK_SIDE or zone[pmode] == zone[lmode]:
                    continue
                over_p = penetration(body, weapons["weapon_rpg"], le, placed_points(body, weapons[cls], pe)) + GAP
                over_l = penetration(body, weapons[cls], pe, placed_points(body, weapons["weapon_rpg"], le)) + GAP
                if max(over_p, over_l) <= 0.1 or min(over_p, over_l) <= 0.1:
                    continue  # they do not cross
                push = over_p if over_p <= over_l else -over_l
                out[f"weapon_rpg {lmode}|{cls} {pmode}"] = round(float(push), 2)
    return out


_weapons = None


def _worker_init():
    global _weapons
    _weapons = {cls: Weapon(path) for cls, (path, _) in WEAPONS.items()}


def _fit_one(m):
    """One playermodel, in a worker: (model, its placements, the body's parts used afterwards)."""
    body, res = fit_model(m, _weapons)
    if res is None:
        return m, None, None
    return m, res, SimpleNamespace(solid=body.solid, world=body.world)


def _deepest(args):
    """The deepest contact of these placements on body (a share of a set check)."""
    body, entries = args
    return max(penetration(body, _weapons[cls], e) for cls, e in entries)


def _stack_one(args):
    body, res = args
    return stacking(body, _weapons, res)


def _report_one(args):
    """How far each weapon goes into the body m in its set's placements (the report)."""
    m, body, entries = args
    return [(penetration(body, _weapons[cls], e), m, cls, mode) for cls, mode, e in entries]


class _Serial:
    """Pool stand-in for --jobs 1."""
    def __init__(self, weapons):
        global _weapons
        _weapons = weapons

    def imap(self, f, items, chunksize=1):
        return map(f, items)

    def close(self):
        pass

    def join(self):
        pass


def main():
    global JOBS
    args = sys.argv[1:]
    if "--jobs" in args:
        k = args.index("--jobs")
        JOBS = int(args[k + 1])
        del args[k:k + 2]
    sys.argv[1:] = args
    if os.name == "nt":  # below normal priority, the workers too: the computer stays usable meanwhile
        import ctypes
        k32 = ctypes.windll.kernel32
        k32.GetCurrentProcess.restype = ctypes.c_void_p
        k32.SetPriorityClass.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        k32.SetPriorityClass(k32.GetCurrentProcess(), 0x4000)
    if sys.argv[1:2] == ["--current"]:  # the playermodels the game's carry data already has
        import carry_data
        models = sorted(carry_data.read()[1])
    else:
        lst = Path(sys.argv[1]) if len(sys.argv) > 1 else TOOLS / "playermodels.txt"
        models = [l.strip() for l in lst.read_text(encoding="utf-8").splitlines() if l.strip()]
    overrides = json.loads(OVERRIDES.read_text(encoding="utf-8")) if OVERRIDES.exists() else {}
    fitted, bodies, skipped = {}, {}, []
    todo = [REF] + [x for x in models if x.lower() != REF]
    jobs = max(1, min(JOBS, len(todo)))
    # several processes (started first: they load the weapons while this one does too); the
    # playermodels come back in order, so the sets below come out the same
    pool = Pool(jobs, initializer=_worker_init) if jobs > 1 else None
    weapons = {cls: Weapon(path) for cls, (path, _) in WEAPONS.items()}
    pool = pool or _Serial(weapons)
    for k, (m, res, body) in enumerate(pool.imap(_fit_one, todo), 1):
        print(f"  playermodel {k}/{len(todo)}  {m}", flush=True)
        if res is None:
            skipped.append(m)
            continue
        fitted[m], bodies[m] = res, body
    # alias sets: a model shares an existing set if it fits without clipping and close to its own fit
    sets, aliases = {}, {}
    for m, res in fitted.items():
        body = bodies[m]
        chosen = None
        pairs = [(weapons[cls], cls, mode, model_space(body, weapons[cls], own)[0])
                 for cls, modes in res.items() for mode, own in modes.items()]
        for name, rep in sets.items():
            # the corners of every weapon and mode first (cheap), the contacts only if they all match
            # (shared among the workers)
            if all(not (np.abs(model_space(body, w, rep["res"][cls][mode])[0] - own).max() > ALIAS_TOL)
                   for w, cls, mode, own in pairs):
                entries = [(cls, rep["res"][cls][mode]) for _, cls, mode, _ in pairs]
                parts = [(body, entries[k::jobs]) for k in range(jobs) if entries[k::jobs]]
                if not (max(pool.imap(_deepest, parts)) > 0.05):
                    chosen = name
                    break
        if chosen is None:
            chosen = "default" if m == REF else Path(m).stem if Path(m).parent.name == "player" else \
                f"{Path(m).parent.name}_{Path(m).stem}"
            sets[chosen] = {"res": res, "rep": m}
        aliases[m] = chosen
    # overrides from the in-game tuner
    for name, wmap in overrides.items():
        for cls, mmap in wmap.items():
            for mode, v in mmap.items():
                if name in sets and cls in sets[name]["res"]:
                    sets[name]["res"][cls][mode].update(
                        bone=v["bone"], pos=np.array(v["pos"]), ang=v["ang"],
                        out=np.array(v.get("out", sets[name]["res"][cls][mode]["out"])))
    # positions approved in the fit editor (tools/fit_locks.txt, "carry:<weapon>:<mode>"): final
    import carry_data
    import fit_locks
    set_of = {m.lower(): n for m, n in aliases.items()}  # (locks are keyed by lowercase playermodel)
    for cls_key, per in fit_locks.load().items():
        wm = carry_data.split_class(cls_key)
        if not wm:
            continue
        for pm, (p, a, _s) in per.items():
            name = set_of.get(pm)
            e = name and sets.get(name, {}).get("res", {}).get(wm[0], {}).get(wm[1])
            if e:
                e.update(pos=np.array(p), ang=tuple(a))
    # launcher and primary weapon crossing on the back, per set (in the workers)
    for s, stack in zip(sets.values(), pool.imap(_stack_one, [(bodies[s["rep"]], s["res"]) for s in sets.values()])):
        s["stack"] = stack
    # templates for weapons without offsets: the default body's rules (surface point, outward, angles)
    templates = {}
    ref = bodies[REF]
    for mode in MODES:
        e = fitted[REF]["weapon_ar2"].get(mode) or fitted[REF]["weapon_smg1"][mode]
        w = weapons["weapon_ar2"]
        R, t, n = e["R"], e["t"], e["n"]
        # surface point under the weapon's anchor (its middle, or its butt for the modes whose butt
        # has its place: a longer gun then goes further from it, not both ways), outward direction and
        # canonical angles, bone-relative (the main body's band across Y rests on the body, as in place())
        lo, hi = w.core_y
        anchor = TEMPLATE_ANCHOR.get(mode, "middle")
        ax = w.mn[0] if anchor == "butt" else (w.mn[0] + w.mx[0]) / 2
        c = R @ np.array([ax, (lo + hi) / 2, (w.mn[2] + w.mx[2]) / 2]) + t
        half = (hi - lo) / 2
        surf = c - n * (half + GAP)
        Bw = ref.world[BONES[mode]]
        Li = np.linalg.inv(Bw)
        templates[mode] = (BONES[mode], Li[:3, :3] @ surf + Li[:3, 3], Li[:3, :3] @ n,
                           fi.matrix_angles(Li[:3, :3] @ R), anchor)
    write_lua(sets, aliases, templates, models)
    # report
    worst = []
    jobs_report = [(m, bodies[m], [(cls, mode, e) for cls, modes in sets[name]["res"].items() for mode, e in modes.items()])
                   for m, name in aliases.items()]
    for part in pool.imap(_report_one, jobs_report, chunksize=4):
        worst += part
    pool.close()
    pool.join()
    worst.sort(reverse=True)
    print(f"{len(fitted)} playermodels, {len(sets)} offset sets, skipped: {skipped or 'none'}")
    print("deepest contacts (<= 0 = no clipping):")
    for p, m, cls, mode in worst[:6]:
        print(f"   {p:+.2f}  {Path(m).stem:22} {cls:16} {mode}")
    print("sets:", {n: sum(1 for a in aliases.values() if a == n) for n in sets})


def write_lua(sets, aliases, templates, models):
    v = lambda x: f"V({x[0]:.2f}, {x[1]:.2f}, {x[2]:.2f})"
    vo = lambda x: f"V({x[0]:.3f}, {x[1]:.3f}, {x[2]:.3f})"
    a = lambda x: f"A({x[0]:.1f}, {x[1]:.1f}, {x[2]:.1f})"
    L = ["-- Generated by tools/fit_carry.py (do not edit by hand; tune in game with advinv_carry_tune).",
         "-- CarryOffsets[set][weapon class][mode] = { bone, position, angles, outward direction }",
         "local V, A = Vector, Angle",
         "AdvInv.CarryOffsets = {"]
    for name, s in sets.items():
        L.append(f'    ["{name}"] = {{ -- {s["rep"]}')
        for cls, modes in s["res"].items():
            L.append(f"        {cls} = {{")
            for mode, e in modes.items():
                L.append(f'            {mode} = {{ "{e["bone"]}", {v(e["pos"])}, {a(e["ang"])}, {vo(e["out"])} }},')
            L.append("        },")
        L.append("    },")
    L.append("}")
    L.append("-- launcher over the primary weapon when both are on the back side: push along its outward")
    L.append("-- direction, [set][\"launcher mode|primary class mode\"] = units")
    L.append("AdvInv.CarryStack = {")
    for name, s in sets.items():
        if s["stack"]:
            L.append(f'    ["{name}"] = {{')
            for k, push in sorted(s["stack"].items()):
                L.append(f'        ["{k}"] = {push:.2f},')
            L.append("    },")
    L.append("}")
    L.append("-- playermodel -> offset set (models with the same proportions share one)")
    L.append("AdvInv.CarryAliases = {")
    for m, name in aliases.items():
        L.append(f'    ["{m}"] = "{name}",')
    L.append("}")
    L.append("-- weapons without offsets: surface point, outward direction and angles of each mode on the")
    L.append("-- default body, placed at run time with the weapon's own shape")
    L.append("AdvInv.CarryTemplates = {")
    for mode, (bone, pos, out, ang, anchor) in templates.items():
        L.append(f'    {mode} = {{ bone = "{bone}", pos = {v(pos)}, out = {vo(out)}, ang = {a(ang)}, anchor = "{anchor}" }},')
    L.append("}")
    L.append("-- the base game's playermodels (player_manager), for advinv_carry_cycle")
    L.append("AdvInv.CarryDefaultModels = {")
    for m in models:
        L.append(f'    "{m}",')
    L.append("}")
    text = "\n".join(L).replace("-0.00", "0.00").replace("-0.0,", "0.0,").replace("-0.0)", "0.0)") + "\n"
    OUT.write_text(text, encoding="utf-8", newline="\n")
    print("written", OUT)


if __name__ == "__main__":
    main()
