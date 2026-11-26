"""Fits every worn item and the weapon mounts to every default playermodel (dev tool, not in the .gma).

Writes lua/advinv/cl_fits_data.lua: for each playermodel, the ENT.Attach of each worn item
(position, angles, size on its bone) and the weapon mounts adapted to that body. In game, a model
that is not in the table uses the item's own ENT.Attach and Config.WeaponMounts.

Rules (the ones the defaults were made with), in the frame of the wearer's 'eyes' attachment
(x forward, y left, z up; it follows each model's face, whatever its head bone looks like):
  - Barney helmet: inner top of the shell on the top of the head, inner back on the back of the
    head, centred; the Civil Protection mask shares the helmet's transform (they are a pair);
  - bucket: upside down, inner bottom on the top of the head, centred, size 0.7 or more if the head
    would poke out of its walls;
  - hats (top hat, graduation cap): placed like their bonemerge on the reference body (Valve's
    placement), carried over to each face, then enlarged until the head fits in the crown (95% of
    it: hair may go through), 1.2 at most;
  - back items (jetpack, suitcase): the side against the body flat on the back, top 2 units under
    the neck, centred;
  - weapons: back anchor between Spine2 and Spine4, right thigh anchor 8 units under the hip.
Props are taken in their rest pose (anim0.py), as the game draws them. Pairs approved by hand in
the fit editor (fit_locks.txt) are kept as they are.

    python fit_items.py [playermodels.txt]
"""
import math
import re
import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import anim0  # noqa: E402
import mdl_render as mr  # noqa: E402
import refbody  # noqa: E402

# A negative zero ("-0.00", "-0.0") written without its sign; only a number that is all zeros
# ("-0.004" keeps its sign: a plain .replace("-0.00", "0.00") turned it into 0.004).
_NEG_ZERO = re.compile(r"(?<![\w.])-(0\.0+)(?![0-9])")  # (not "1-0.00")


def _nz(text):
    return _NEG_ZERO.sub(lambda m: m.group(1), text)


TOOLS = Path(__file__).resolve().parent
OUT = TOOLS.parent / "lua" / "advinv" / "cl_fits_data.lua"
REF = "models/player/group01/male_07.mdl"
HEAD, SPINE, THIGH = "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_R_Thigh"
TORSO = ["ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine4"]
GAP = 0.15
HAT_MAX_SCALE = 1.2  # a hair bun or a cap goes through rather than a hat half again too big


# ---------------------------------------------------------------- geometry helpers

def matrix_angles(m):
    """3x3 rotation -> Source QAngle (pitch, yaw, roll), degrees (MatrixAngles)."""
    f, l, u = m[:, 0], m[:, 1], m[:, 2]
    xy = math.hypot(f[0], f[1])
    if xy > 0.001:
        return (math.degrees(math.atan2(-f[2], xy)), math.degrees(math.atan2(f[1], f[0])),
                math.degrees(math.atan2(l[2], u[2])))
    return math.degrees(math.atan2(-f[2], xy)), math.degrees(math.atan2(-l[0], l[1])), 0.0


class Body:
    """A playermodel in its reference pose: bones, vertices grouped by dominant bone, eyes frame."""

    def __init__(self, model):
        self.model = model
        self.bones = refbody.bones(model)
        self.names = [b["name"] for b in self.bones]
        self.world = {b["name"]: b["world"] for b in self.bones}
        self.P, self.dom = refbody.skinned_vertices(model)
        self.eyes = self._attachment("eyes")
        # a model without an "eyes" attachment (some ports have none: the Dying Light Security forces):
        # the reference body's eyes frame, kept in the same place relative to the head bone
        self.eyes_guessed = False
        if self.eyes is None and HEAD in self.world and model.lower() != REF:
            self.eyes = self.world[HEAD] @ ref_eyes_local()
            self.eyes_guessed = True

    def _attachment(self, name):
        d = mr.vpk_read(self.model)
        i = lambda o: struct.unpack_from("<i", d, o)[0]
        for a in range(i(240)):
            o = i(244) + a * 92
            if mr.cstr(d, o + i(o)) == name:
                L = np.vstack([np.array(struct.unpack_from("<12f", d, o + 12)).reshape(3, 4), [0, 0, 0, 1]])
                return self.bones[i(o + 8)]["world"] @ L
        return None

    def has(self, *bones):
        return all(b in self.world for b in bones)

    def verts(self, bones):
        ids = [self.names.index(n) for n in bones if n in self.names]
        return self.P[np.isin(self.dom, ids)]

    def head_in_eyes(self):
        h = self.verts([HEAD])
        return (np.linalg.inv(self.eyes) @ np.c_[h, np.ones(len(h))].T).T[:, :3]

    def eyes_local(self):
        """eyes frame expressed in the head bone's frame."""
        return np.linalg.inv(self.world[HEAD]) @ self.eyes


_ref_eyes = []


def ref_eyes_local():
    """The reference body's (male_07) eyes frame in its head bone's frame."""
    if not _ref_eyes:
        _ref_eyes.append(Body(REF).eyes_local())
    return _ref_eyes[0]


_mesh = {}


def rest_mesh(model):
    if model not in _mesh:
        pos, nrm, uv, tris, mats = anim0.posed_mesh(model, textures=False)  # (geometry only)
        used = sorted({t[k] for t in tris for k in range(3)})
        _mesh[model] = (pos, tris, pos[used])
    return _mesh[model]


def ray_hits(model, origin, direction):
    pos, tris, _ = rest_mesh(model)
    T = np.array([[pos[a], pos[b], pos[c]] for a, b, c, _ in tris])
    e1, e2 = T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]
    p = np.cross(direction, e2)
    det = (e1 * p).sum(1)
    ok = np.abs(det) > 1e-9
    inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
    s = origin - T[:, 0]
    u = (s * p).sum(1) * inv
    q = np.cross(s, e1)
    v = (q @ direction) * inv
    t = (q * e2).sum(1) * inv
    hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0)
    return np.sort(t[hit])


def eyes_to_bone(body, R_e, t_e, scale):
    """Item placed in the eyes frame (v_e = R_e @ (scale v) + t_e) -> FollowBone values on the head."""
    E = body.eyes_local()
    R_b = E[:3, :3] @ R_e
    pos = E[:3, :3] @ t_e + E[:3, 3]
    return pos, matrix_angles(R_b), scale


def model_to_bone(body, bone, R_m, t_m, scale=1.0):
    """Item placed in model space (reference pose) -> FollowBone values on bone."""
    L = np.linalg.inv(body.world[bone])
    return L[:3, :3] @ t_m + L[:3, 3], matrix_angles(L[:3, :3] @ R_m), scale


# ---------------------------------------------------------------- rules

HELMET = "models/barneyhelmet.mdl"
_helmet_c = np.array([-1.6, -0.15, 0.0])  # inside the shell (rest pose: front +X, left +Y, up +Z)
_helmet_top = _helmet_c + np.array([0, 0, 1.0]) * ray_hits(HELMET, _helmet_c, np.array([0, 0, 1.0]))[0]
_helmet_back = _helmet_c - np.array([1.0, 0, 0]) * ray_hits(HELMET, _helmet_c, np.array([-1.0, 0, 0]))[0]


def fit_helmet(body):
    """The CP mask's faceplate (upright in its rest pose: front +X, up +Z)."""
    h = body.head_in_eyes()
    t = np.array([h[:, 0].min() - GAP - _helmet_back[0],
                  (h[:, 1].min() + h[:, 1].max()) / 2 - _helmet_c[1],
                  h[:, 2].max() + GAP - _helmet_top[2]])
    return eyes_to_bone(body, np.eye(3), t, 1.0)


# Barney's helmet lies on its side in its rest pose (its crown towards -X, its front +Z, as the game
# draws it): R_HELMET stands it up (front +X, left +Y, up +Z). Resting on the head (inner top GAP above
# it, back of the shell against the back of the head), then adjusted like the fit editor does it
# (chosen by eye there): 12 % bigger, tilted front up by 10 degrees about the item's centre, 0.5
# forward and 0.3 down (eyes frame). Upright at size 1 the forehead went through the visor on most heads.
R_HELMET = np.array([[0, 0, 1.0], [0, 1.0, 0], [-1.0, 0, 0]])
HELMET_ADJUST = (1.12, 10.0, np.array([0.5, 0, -0.3]))  # size, tilt (front up), shift (forward, left, up)
_hu = rest_mesh(HELMET)[2] @ R_HELMET.T
_hu_c = np.array([(_hu[:, 0].min() + _hu[:, 0].max()) / 2, (_hu[:, 1].min() + _hu[:, 1].max()) / 2,
                  _hu[:, 2].min() + 0.35 * np.ptp(_hu[:, 2])])  # inside the shell
# the shell itself (an inner layer under the crown would hold the head too high)
_hu_top = _hu_c + np.array([0, 0, 1.0]) * max(ray_hits(HELMET, R_HELMET.T @ _hu_c, R_HELMET.T @ np.array([0, 0, 1.0])))
_hu_back = _hu_c - np.array([1.0, 0, 0]) * ray_hits(HELMET, R_HELMET.T @ _hu_c, R_HELMET.T @ np.array([-1.0, 0, 0]))[0]
_h_mid = (rest_mesh(HELMET)[2].min(0) + rest_mesh(HELMET)[2].max(0)) / 2  # the item's centre (its model space)


def fit_barney_helmet(body):
    h = body.head_in_eyes()
    t = np.array([h[:, 0].min() - GAP - _hu_back[0],
                  (h[:, 1].min() + h[:, 1].max()) / 2 - _hu_c[1],
                  h[:, 2].max() + GAP - _hu_top[2]])
    size, tilt, shift = HELMET_ADJUST
    p0 = R_HELMET @ _h_mid + t  # the centre stays put (then shifted)
    a = np.radians(tilt)
    R = np.array([[np.cos(a), 0, -np.sin(a)], [0, 1.0, 0], [np.sin(a), 0, np.cos(a)]]) @ R_HELMET
    return eyes_to_bone(body, R, p0 + shift - R @ (size * _h_mid), size)


BUCKET, BUCKET_SCALE, BUCKET_MAX_SCALE = "models/props_junk/metalbucket01a.mdl", 0.7, 1.2
R_BUCKET = np.array([[0, 1, 0], [1, 0, 0], [0, 0, -1.0]])  # upside down, handle sideways
_bucket_bottom = np.array([0, 0, -ray_hits(BUCKET, np.zeros(3), np.array([0, 0, -1.0]))[0]])


def poke(P, cxy, z0, z1, v_item, s):
    """How far (units, after scaling by s) points v_item stick out of the wall of a round container
    P whose axis is its Z through cxy, between heights z0 and z1 (its own space). Negative: inside."""
    out = -np.inf
    for z in np.arange(z0, z1, 0.5):
        band = P[np.abs(P[:, 2] - z) < 0.6]
        r = np.hypot(band[:, 0] - cxy[0], band[:, 1] - cxy[1])
        r = r[r > 1.5]  # a button, a pin or the bottom disk on the axis is not the wall
        sel = v_item[np.abs(v_item[:, 2] - z) < 0.25]
        if not len(r) or not len(sel):
            continue
        out = max(out, (np.hypot(sel[:, 0] - cxy[0], sel[:, 1] - cxy[1]).max() - np.percentile(r, 10)) * s)
    return out


def fit_bucket(body):
    """Upside down on the head; 0.7 by default, bigger only where the head pokes out of its walls."""
    h = body.head_in_eyes()
    _, _, P = rest_mesh(BUCKET)
    s = BUCKET_SCALE
    while True:
        t = np.array([(h[:, 0].min() + h[:, 0].max()) / 2, (h[:, 1].min() + h[:, 1].max()) / 2,
                      h[:, 2].max() + GAP - (R_BUCKET @ (s * _bucket_bottom))[2]])
        v_item = (np.linalg.inv(R_BUCKET) @ (h - t).T).T / s
        if s >= BUCKET_MAX_SCALE or poke(P, (0, 0), _bucket_bottom[2] + 0.5, P[:, 2].max(), v_item, s) <= -0.1:
            break
        s = round(s + 0.02, 2)
    return eyes_to_bone(body, R_BUCKET, t, s)


class Hat:
    """A hat rigged on the head (top hat, graduation cap), placed like its bonemerge on REF.
    crown: (z0, z1) heights of the part that holds the head (its own rest-pose space); base_z: height
    of its lower edge (the pivot it is enlarged around). strict: the whole head must be inside the
    crown (top hat: no hair through it); otherwise a head may reach out of it as much as the reference
    head does under Valve's placement (graduation cap: a shallow skull cap under the board)."""

    def __init__(self, model, ref, crown, base_z, strict=True):
        self.model = model
        rest = anim0.rest_bones(model)
        names = [b["name"] for b in refbody.bones(model)]
        L0 = np.linalg.inv(rest[names.index(HEAD)])  # bonemerge == FollowBone(head) with this transform
        _, _, P = rest_mesh(model)
        self.P = P
        self.crown = crown
        C = P[(P[:, 2] >= crown[0]) & (P[:, 2] <= crown[1])]
        self.p = np.array([(C[:, 0].min() + C[:, 0].max()) / 2, (C[:, 1].min() + C[:, 1].max()) / 2, base_z])
        E = ref.eyes_local()
        self.R_e = np.linalg.inv(E[:3, :3]) @ L0[:3, :3]
        p_e = (np.linalg.inv(E) @ np.r_[L0[:3, :3] @ self.p + L0[:3, 3], 1])[:3]
        h = ref.head_in_eyes()
        self.offset = p_e - self._anchor(h)  # pivot relative to the head on the reference body
        self.allow = -0.1
        if not strict:
            rel = (np.linalg.inv(self.R_e) @ (h - p_e).T).T
            self.allow = max(self.allow, self._poke(self.p + rel, 1.0) + 0.05)

    @staticmethod
    def _anchor(h):
        return np.array([(h[:, 0].min() + h[:, 0].max()) / 2, (h[:, 1].min() + h[:, 1].max()) / 2, h[:, 2].max()])

    def _crown_radius(self, z):
        band = self.P[np.abs(self.P[:, 2] - z) < 0.6]
        r = np.hypot(band[:, 0] - self.p[0], band[:, 1] - self.p[1])
        r = r[r > 1.5]  # a button or a pin on the axis is not the wall of the crown
        return np.percentile(r, 10) if len(r) else None

    def _poke(self, v_item, s):
        out = -np.inf
        for z in np.arange(self.crown[0], self.crown[1], 0.5):
            sel = v_item[np.abs(v_item[:, 2] - z) < 0.25]
            rc = self._crown_radius(z)
            if not len(sel) or rc is None:
                continue
            # 95th percentile: a few strands of hair or a bun don't decide the size alone
            out = max(out, (np.percentile(np.hypot(sel[:, 0] - self.p[0], sel[:, 1] - self.p[1]), 95) - rc) * s)
        return out

    def fit(self, body):
        h = body.head_in_eyes()
        p_e = self._anchor(h) + self.offset
        rel = (np.linalg.inv(self.R_e) @ (h - p_e).T).T  # head in the hat's frame, around the pivot
        s = 1.0
        while s < HAT_MAX_SCALE and self._poke(self.p + rel / s, s) > self.allow:
            s = round(s + 0.01, 2)
        t = p_e - s * (self.R_e @ self.p)
        return eyes_to_bone(body, self.R_e, t, s)


JETPACK, SUITCASE = "models/thrusters/jetpack.mdl", "models/props_c17/suitcase001a.mdl"
# model space of the reference pose: front -Y, back +Y, left +X, up +Z
R_JETPACK = np.array([[0, -1, 0], [1, 0, 0], [0, 0, 1.0]])   # rest pose: straps on -X
R_SUITCASE = np.array([[-1, 0, 0], [0, -1, 0], [0, 0, 1.0]])  # static prop: flat faces on +-Y


def fit_back(body, model, R):
    _, _, P = rest_mesh(model)
    Pm = P @ R.T  # prop in body axes, before translation
    neck = body.world["ValveBiped.Bip01_Neck1"][:3, 3]
    z_top = neck[2] - 2.0
    z_bot = z_top - (Pm[:, 2].max() - Pm[:, 2].min())
    torso = body.verts(TORSO)
    band = torso[(torso[:, 2] > z_bot) & (torso[:, 2] < z_top) & (np.abs(torso[:, 0]) < 7)]
    back = band[:, 1].max() if len(band) else torso[:, 1].max()
    t = np.array([-(Pm[:, 0].min() + Pm[:, 0].max()) / 2, back + GAP - Pm[:, 1].min(), z_top - Pm[:, 2].max()])
    return model_to_bone(body, SPINE, R, t)


TH = math.radians(40)


def _frame(x, z):
    x, z = np.array(x, float), np.array(z, float)
    return np.column_stack([x, np.cross(z, x), z])


R_PRIMARY = _frame([math.sin(TH), 0, math.cos(TH)], [-math.cos(TH), 0, math.sin(TH)])
R_LAUNCHER = _frame([-math.sin(TH), 0, math.cos(TH)], [math.cos(TH), 0, math.sin(TH)])
R_HOLSTER = _frame([0, 0, -1], [0, -1, 0])


def fit_weapons(body):
    out = {}
    s2, s4 = body.world[SPINE][:3, 3], body.world["ValveBiped.Bip01_Spine4"][:3, 3]
    zc = (s2[2] + s4[2]) / 2 + 2
    t = body.verts(TORSO)
    band = t[(np.abs(t[:, 0]) < 5) & (np.abs(t[:, 2] - zc) < 6)]
    if len(band):
        A = np.array([0.0, band[:, 1].max() + GAP, zc])
        L = np.linalg.inv(body.world[SPINE])
        o = L[:3, :3] @ np.array([0, 1.0, 0])
        a = L[:3, :3] @ A + L[:3, 3]
        out["PrimaryWep"] = (a, o, matrix_angles(L[:3, :3] @ R_PRIMARY))
        out["RocketLauncher"] = (a, o, matrix_angles(L[:3, :3] @ R_LAUNCHER))
    if body.has(THIGH):
        th = body.world[THIGH][:3, 3]
        zh = th[2] - 8
        v = body.verts([THIGH])
        band = v[np.abs(v[:, 2] - zh) < 2.5]
        if len(band):
            A = np.array([band[:, 0].min() - GAP, band[:, 1].mean(), zh])
            L = np.linalg.inv(body.world[THIGH])
            out["SecondaryWep"] = (L[:3, :3] @ A + L[:3, 3], L[:3, :3] @ np.array([-1.0, 0, 0]),
                                   matrix_angles(L[:3, :3] @ R_HOLSTER))
    return out


# ---------------------------------------------------------------- run

def fit_body(model, hats):
    body = Body(model)
    items = {}
    if body.eyes is not None and body.has(HEAD) and len(body.verts([HEAD])) > 20:
        items["advinv_barney_helmet"] = fit_barney_helmet(body)
        items["advinv_cp_mask"] = fit_helmet(body)
        items["advinv_bucket"] = fit_bucket(body)
        for cls, hat in hats.items():
            items[cls] = hat.fit(body)
    if body.has(SPINE, "ValveBiped.Bip01_Neck1"):
        items["advinv_jetpack"] = fit_back(body, JETPACK, R_JETPACK)
        items["advinv_suitcase"] = fit_back(body, SUITCASE, R_SUITCASE)
    weapons = fit_weapons(body) if body.has(SPINE, "ValveBiped.Bip01_Spine4") else {}
    return items, weapons


def lua(models_fits):
    v = lambda x: f"V({x[0]:.2f}, {x[1]:.2f}, {x[2]:.2f})"
    vo = lambda x: f"V({x[0]:.3f}, {x[1]:.3f}, {x[2]:.3f})"
    a = lambda x: f"A({x[0]:.1f}, {x[1]:.1f}, {x[2]:.1f})"
    lines = ["-- Generated by tools/fit_items.py (do not edit by hand): the worn items' ENT.Attach and the",
             "-- weapon mounts adapted to each default playermodel. A model that is not listed uses the",
             "-- item's own ENT.Attach and Config.WeaponMounts.",
             "--   item = { position, angles, size } on the item's bone",
             "--   weapon slot = { surface point, outward direction, angles } on the mount's bone",
             "local V, A = Vector, Angle",
             "AdvInv.Fits = {"]
    for model, (items, weapons) in models_fits.items():
        lines.append(f'    ["{model}"] = {{')
        for cls, (p, ang, s) in items.items():
            lines.append(f"        {cls} = {{ {v(p)}, {a(ang)}, {s:g} }},")
        for cat, (p, o, ang) in weapons.items():
            lines.append(f"        {cat} = {{ {v(p)}, {vo(o)}, {a(ang)} }},")
        lines.append("    },")
    lines.append("}")
    return _nz("\n".join(lines)) + "\n"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    lst = Path(args[0]) if args else TOOLS / "playermodels.txt"
    models = [l.strip() for l in lst.read_text(encoding="utf-8").splitlines() if l.strip()]
    ref = Body(REF)
    hats = {"advinv_top_hat": Hat("models/player/items/humans/top_hat.mdl", ref, crown=(6.5, 11.0), base_z=3.8),
            # the tassel hangs below the cap: only the skull cap (under the board) holds the head
            "advinv_graduation_cap": Hat("models/player/items/humans/graduation_cap.mdl", ref, crown=(5.5, 9.4), base_z=5.5,
                                       strict=False)}
    fits = {}
    import fit_locks  # noqa: E402
    import builtin_gear  # noqa: E402
    locks = fit_locks.load()
    blocked, slots = builtin_gear.builtin(), builtin_gear.item_slots()
    unread = []
    for m in models:
        try:
            items, weapons = fit_body(m, hats)
            # gear of its own in its mesh (headgear, backpack): none of ours over it
            items = {c: f for c, f in items.items() if not builtin_gear.is_blocked(c, m, blocked, slots)}
            for cls in items:
                lk = fit_locks.get(locks, cls, m)
                if lk is not None:  # approved by hand: final
                    items[cls] = lk
        except Exception as e:  # noqa: BLE001
            print(f"{m}: skipped ({e})")
            unread.append(m)
            continue
        if items or weapons:
            fits[m] = (items, weapons)
            hs = " ".join(f"{c[5:]}x{items[c][2]:g}" for c in hats if c in items)
            print(f"{m:46} {len(items)} items, {len(weapons)} weapon mounts  {hs}")
        else:
            print(f"{m}: nothing to fit (no usable ValveBiped head / spine)")
    # playermodels of the shipped file that can't be read now (MDL_EXTRA_DIRS not set: run from
    # fit_editor\local.bat's settings) would be dropped from it with their approved fits
    shipped = OUT.read_text(encoding="utf-8").lower() if OUT.exists() else ""
    lost = [m for m in unread if f'"{m.lower()}"' in shipped]
    if lost and "--allow-drop" not in sys.argv:
        print(f"{len(lost)} playermodels of {OUT.name} can't be read now (e.g. {lost[0]}): nothing written."
              " Set MDL_EXTRA_DIRS (fit_editor\\local.bat), or --allow-drop to drop them.")
        return
    OUT.write_text(lua(fits), encoding="utf-8", newline="\n")
    print(f"{len(fits)} playermodels -> {OUT}")


if __name__ == "__main__":
    main()
