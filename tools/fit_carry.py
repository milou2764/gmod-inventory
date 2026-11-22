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
Tuned values (advinv_carry_tune, saved in garrysmod/data/advinv_carry_tuned.json) can be copied to
tools/carry_overrides.json: they replace the computed offsets of their set / weapon / mode.
"""
import json
import math
import sys
from pathlib import Path

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
ARMS = ("UpperArm", "Forearm", "Hand", "Finger", "Wrist", "Ulna", "Elbow", "Bicep")

WEAPONS = {  # class: (model, modes)
    "weapon_smg1": ("models/weapons/w_smg1.mdl", None),
    "weapon_ar2": ("models/weapons/w_irifle.mdl", None),
    "weapon_shotgun": ("models/weapons/w_shotgun.mdl", None),
    "weapon_crossbow": ("models/weapons/w_crossbow.mdl", None),
    "weapon_rpg": ("models/weapons/w_rocket_launcher.mdl", ("back_carry", "sling_up")),
}
MODES = ("sling_up", "sling_down", "cross_body", "back_carry", "front_hang")
BONES = {"sling_up": "ValveBiped.Bip01_Spine4", "sling_down": "ValveBiped.Bip01_Spine4",
         "cross_body": "ValveBiped.Bip01_Pelvis", "back_carry": "ValveBiped.Bip01_Spine2",
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
        pos, _, _, tris, _ = anim0.posed_mesh(model)
        used = sorted({t[k] for t in tris for k in range(3)})
        P = pos[used]
        Q = np.eye(3)
        if self._muzzle_back(model, P):
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
    def _muzzle_back(model, P):
        import studio  # noqa: E402
        m = studio.Model(mr.vpk_read(model))
        W = anim0.rest_bones(model)
        for a in m.attachments:
            if a["name"].lower() == "muzzle":
                L = np.vstack([a["local"], [0, 0, 0, 1]])
                return (W[a["bone"]] @ L)[0, 3] < (P[:, 0].min() + P[:, 0].max()) / 2
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
    wc, bc = grid(W + t), grid(body.solid)
    wn, bn = W @ n, body.solid @ n
    inner = {}
    for (i, j), v in zip(map(tuple, wc), wn):
        if v < inner.get((i, j), np.inf):
            inner[(i, j)] = v
    outer = {}
    for (i, j), v in zip(map(tuple, bc), bn):
        if (i, j) in inner and v > outer.get((i, j), -np.inf):
            outer[(i, j)] = v
    if outer:
        need = max(outer[c] - inner[c] for c in outer) + GAP
    else:  # nothing under the weapon: put it at the target
        need = np.asarray(target, float) @ n - (R @ np.asarray(ref_point, float)) @ n
    t = t + n * (need - t @ n)
    clear = min((t @ n + inner[c]) - outer[c] for c in outer) if outer else None
    return R, t, clear


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
    th = math.radians(40)
    # back: diagonal, muzzle up over the left shoulder
    out["back_carry"] = place(body, w, (math.sin(th), 0, math.cos(th)), (0, 1, 0), (0, 0, 1),
                              centre, (0, 0, (s2 + s4) / 2 + 2)) + (np.array([0, 1.0, 0]),)
    # from the right shoulder, muzzle up: behind the right shoulder blade, muzzle above the shoulder
    n_sh = unit((-0.3, 1, 0))
    x_sh = -0.55 * hw
    out["sling_up"] = place(body, w, (-0.12, 0.08, 1), n_sh, (-1, 0, 0), muzzle_tip,
                            (x_sh, 0, sh + 0.15 * L)) + (n_sh,)
    # from the right shoulder, muzzle down: the stock end under the shoulder
    out["sling_down"] = place(body, w, (-0.12, 0.08, -1), n_sh, (-1, 0, 0), stock_tip,
                              (x_sh, 0, sh - 1.5)) + (n_sh,)
    # sling across the torso from the right shoulder, gun on the left side: behind the left hip
    # (clear of the hanging arm and of the shoulder / back zones), muzzle down and a little forward
    n_side = unit((0.4, 0.92, 0))
    tang = unit(np.cross(n_side, (0, 0, 1)))  # left-forward along the body
    d_side = unit(-0.9 * np.array([0, 0, 1.0]) + 0.44 * tang)
    out["cross_body"] = place(body, w, d_side, n_side, -tang, centre,
                              (0.5 * body.half_width(pelvis + 4), 0, pelvis + 4)) + (n_side,)
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
    mn, mx = w.P.min(0), w.P.max(0)
    return np.array([[x, y, z] for x in (mn[0], mx[0]) for y in (mn[1], mx[1]) for z in (mn[2], mx[2])])


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
    C = corners(w) @ np.linalg.inv(w.Q).T  # canonical corners -> weapon model space
    return C @ Rm.T + t, Rm, t


def placed_points(body, w, e):
    """Weapon vertices placed by bone-relative values e on body (model space)."""
    Bw = body.world[e["bone"]]
    Rm = Bw[:3, :3] @ mr.rot_matrix(*e["ang"])
    return (w.Pc @ np.linalg.inv(w.Q).T) @ Rm.T + Bw[:3, :3] @ e["pos"] + Bw[:3, 3]


def penetration(body, w, e, solid=None):
    """How far the weapon placed by e goes into body (or into the points solid) along its resting
    side, <= 0 when clear."""
    if solid is None:
        solid = body.solid
    Bw = body.world[e["bone"]]
    Rm = Bw[:3, :3] @ mr.rot_matrix(*e["ang"])
    t = Bw[:3, :3] @ e["pos"] + Bw[:3, 3]
    W = (w.Pc @ np.linalg.inv(w.Q).T) @ Rm.T + t
    n = unit(Bw[:3, :3] @ e["out"])
    d = unit(Rm @ (w.Q.T @ np.array([1.0, 0, 0])))
    a1 = unit(np.cross(n, d))
    g = lambda pts: map(tuple, np.floor(np.c_[pts @ d, pts @ a1] / CELL).astype(int))
    inner = {}
    for c, v in zip(g(W), W @ n):
        inner[c] = min(inner.get(c, np.inf), v)
    worst = -np.inf
    for c, v in zip(g(solid), solid @ n):
        if c in inner:
            worst = max(worst, v - inner[c])
    return worst


BACK_SIDE = {"sling_up", "sling_down", "cross_body", "back_carry"}


def stacking(body, weapons, res):
    """When the launcher and the primary weapon are both carried on the back side and cross, one
    goes over the other: whichever needs the smaller push along its outward direction.
    { "rpg mode|primary class mode": push } with push > 0: the launcher moves out, < 0: the primary
    weapon moves out by -push."""
    out = {}
    zone = {"sling_up": "shoulder", "sling_down": "shoulder", "cross_body": "side", "back_carry": "back"}
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


def main():
    lst = Path(sys.argv[1]) if len(sys.argv) > 1 else TOOLS / "playermodels.txt"
    models = [l.strip() for l in lst.read_text(encoding="utf-8").splitlines() if l.strip()]
    weapons = {cls: Weapon(path) for cls, (path, _) in WEAPONS.items()}
    overrides = json.loads(OVERRIDES.read_text(encoding="utf-8")) if OVERRIDES.exists() else {}
    fitted, bodies, skipped = {}, {}, []
    for m in [REF] + [x for x in models if x != REF]:
        body, res = fit_model(m, weapons)
        if res is None:
            skipped.append(m)
            continue
        fitted[m], bodies[m] = res, body
    # alias sets: a model shares an existing set if it fits without clipping and close to its own fit
    sets, aliases = {}, {}
    for m, res in fitted.items():
        body = bodies[m]
        chosen = None
        for name, rep in sets.items():
            ok = True
            for cls, modes in res.items():
                w = weapons[cls]
                for mode, own in modes.items():
                    e = rep["res"][cls][mode]
                    a, _, _ = model_space(body, w, e)
                    b, _, _ = model_space(body, w, own)
                    if np.abs(a - b).max() > ALIAS_TOL or penetration(body, w, e) > 0.05:
                        ok = False
                        break
                if not ok:
                    break
            if ok:
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
    for name, s in sets.items():
        s["stack"] = stacking(bodies[s["rep"]], weapons, s["res"])
    # templates for weapons without offsets: the default body's rules (surface point, outward, angles)
    templates = {}
    ref = bodies[REF]
    for mode in MODES:
        e = fitted[REF]["weapon_ar2"].get(mode) or fitted[REF]["weapon_smg1"][mode]
        w = weapons["weapon_ar2"]
        R, t, n = e["R"], e["t"], e["n"]
        # surface point under the weapon centre, outward direction and canonical angles, bone-relative
        # (the main body's band across Y rests on the body, as in place())
        lo, hi = w.core_y
        c = R @ np.array([(w.mn[0] + w.mx[0]) / 2, (lo + hi) / 2, (w.mn[2] + w.mx[2]) / 2]) + t
        half = (hi - lo) / 2
        surf = c - n * (half + GAP)
        Bw = ref.world[BONES[mode]]
        Li = np.linalg.inv(Bw)
        templates[mode] = (BONES[mode], Li[:3, :3] @ surf + Li[:3, 3], Li[:3, :3] @ n, fi.matrix_angles(Li[:3, :3] @ R))
    write_lua(sets, aliases, templates, models)
    # report
    worst = []
    for m, name in aliases.items():
        body = bodies[m]
        for cls, modes in sets[name]["res"].items():
            for mode, e in modes.items():
                worst.append((penetration(body, weapons[cls], e), m, cls, mode))
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
    for mode, (bone, pos, out, ang) in templates.items():
        L.append(f'    {mode} = {{ bone = "{bone}", pos = {v(pos)}, out = {vo(out)}, ang = {a(ang)} }},')
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
