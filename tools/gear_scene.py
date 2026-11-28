"""Pictures of playermodels wearing the pack extensions' items, offline (dev tool, not in the .gma): each
playermodel as the game draws it (anim0.posed_mesh, its idle pose), each item placed the way the game
places it (cl_gear.lua: on its bone by the fit in the extension's Lua, with its size, height and depth, or
bonemerged for a rigged one), the eyes drawn with their iris looking at the camera. No game needed: Workshop
icons and screenshots of the extensions, checks of a whole outfit.

    python gear_scene.py <scene.json> <out.png>

scene.json:
    {"size": 1024, "camera": {"yaw": 0, "pitch": 6, "frame": "chest"}, "background": [r, g, b, r2, g2, b2],
     "subjects": [{"model": "models/player/group01/male_07.mdl", "yaw": -14, "pos": [0, -20],
                   "items": ["advinv_milou_csssf_seb_helmet_nvg", ...]}, ...]}
yaw: the way each one faces (0: the camera, the camera looks along -x from +x); pos: x, y in units.
camera.frame: "chest" (the heads to the waist), "body" (head to feet), "head"; camera.below: that many units
more under it. background: a vertical
gradient (top colour, bottom colour), the scene drawn over it. Needs MDL_EXTRA_DIRS as vest_check.py.
"""
import json
import math
import re
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vest_check as vc  # noqa: E402  (sets MDL_EXTRA_DIRS when empty, before mdl_render is read)
import anim0  # noqa: E402
import mdl_render as mr  # noqa: E402
import modelgear_pack as mg  # noqa: E402
import mount_check  # noqa: E402
import refbody  # noqa: E402
from modelgear_packs import PACKS  # noqa: E402

SCLERA = (232, 226, 220)


def all_items():
    """{class: (pack key, slot, stretch_top, depth_center, rigged, {playermodel: fit numbers})} of every extension."""
    out = {}
    for key, path in vc.ext_files().items():
        text = Path(path).read_text(encoding="utf-8")
        _k, items, fits = vc.read_ext(path)
        for cls, (slot, top, xc) in items.items():
            blk = re.search(rf'class = "{re.escape(cls)}",(?:(?!\n        \{{ class = ).)*', text, re.S).group(0)
            out[cls] = (key, slot, top, xc, "rigged = true" in blk, fits.get(cls, {}))
    return out


# ---------------------------------------------------------------- eyes

def eyeballs(model):
    """[(material index, bone, org, up, iris scale, iris texture)] of the model's eyes (mstudioeyeball_t)."""
    d = mr.vpk_read(model)
    i = lambda o: struct.unpack_from("<i", d, o)[0]  # noqa: E731
    f = lambda o, n=1: struct.unpack_from(f"<{n}f", d, o)  # noqa: E731
    tex_names = [mr.cstr(d, i(208) + k * 64 + i(i(208) + k * 64)) for k in range(i(204))]
    dirs = [mr.cstr(d, i(i(216) + k * 4)).replace("\\", "/").lower() for k in range(i(212))]
    skin0 = [struct.unpack_from("<h", d, i(228) + k * 2)[0] for k in range(i(220))]
    groups = mr.BODYGROUPS.get(model.lower(), {})
    out = []
    for b in range(i(232)):
        bo = i(236) + b * 16
        m = groups.get(b, 0)
        if m >= i(bo + 4):
            continue
        mo = bo + i(bo + 12) + m * 148
        for s in range(i(mo + 72)):
            ms = mo + i(mo + 76) + s * 116
            if i(ms + 24) != 1:  # (materialtype 1: an eyeball)
                continue
            eo = mo + i(mo + 104) + i(ms + 28) * 172
            tex = skin0[i(ms)] if i(ms) < len(skin0) else i(ms)
            iris = None
            for dd in dirs:
                data = mr.vpk_read(f"materials/{dd}{tex_names[tex]}.vmt".replace("//", "/"))
                if data:
                    mm = re.search(r'"?\$iris"?\s+"?([^"\r\n]+?)"?\s*$', data.decode("latin-1"), re.I | re.M)
                    iris = mm and mm.group(1).replace("\\", "/").lower().removesuffix(".vtf")
                    break
            out.append((tex, i(eo + 4), np.array(f(eo + 8, 3)), np.array(f(eo + 28, 3)), f(eo + 60)[0],
                        f(eo + 20)[0], iris))
    return out


def draw_eyes(model, mesh, look_at):
    """The eyes' triangles textured with their iris, projected the way the game does it, looking at look_at
    (a point in the model's space). mesh: (pos, nrm, uv, tris, mats), changed in place."""
    pos, _nrm, uv, tris, mats = mesh
    rest = anim0.rest_bones(model)
    for tex, bone, org, up, iris_scale, zoffset, iris in eyeballs(model):
        W = rest[bone]
        o = W[:3, :3] @ org + W[:3, 3]
        fwd = look_at - o
        fwd /= np.linalg.norm(fwd)
        upw = W[:3, :3] @ up
        right = np.cross(fwd, upw)
        right /= np.linalg.norm(right)
        upw = np.cross(right, fwd)
        scale = (1.0 / iris_scale) + zoffset if iris_scale else 1.0
        vs = sorted({t[k] for t in tris if t[3] == tex for k in range(3)})
        d = pos[vs] - o
        u = -scale * (d @ right) + 0.5
        v = -scale * (d @ upw) + 0.5
        img = mr.vtf_image(iris) if iris else None
        if img is None:
            continue
        n = img.size[0]
        canvas = Image.new("RGBA", (3 * n, 3 * n), SCLERA + (255,))
        canvas.alpha_composite(img.convert("RGBA"), (n, n))
        uv[vs] = np.c_[(u + 1) / 3, (v + 1) / 3]
        mats[tex] = (canvas, False, False)


# ---------------------------------------------------------------- the body

PLAYER_COLOR = (0.24, 0.34, 0.41)  # (GMod's default cl_playercolor: the clothes' tint)


def tint_clothes(model, mats, color=PLAYER_COLOR):
    """The player colour on the materials that take it ($blendtintbybasealpha: the base texture's alpha is the
    mask), as the game draws them: rgb x lerp(1, colour, alpha). mats changed in place."""
    d = mr.vpk_read(model)
    i = lambda o: struct.unpack_from("<i", d, o)[0]  # noqa: E731
    names = [mr.cstr(d, i(208) + k * 64 + i(i(208) + k * 64)) for k in range(i(204))]
    dirs = [mr.cstr(d, i(i(216) + k * 4)).replace("\\", "/").lower() for k in range(i(212))]
    for k, name in enumerate(names):
        if k >= len(mats) or mats[k][0] is None:
            continue
        text = None
        for dd in dirs:
            data = mr.vpk_read(f"materials/{dd}{name}.vmt".replace("//", "/"))
            if data:
                text = data.decode("latin-1")
                break
        if not text or not re.search(r'"?\$blendtintbybasealpha"?\s+"?1', text, re.I):
            continue
        a = np.asarray(mats[k][0].convert("RGBA")).astype(float)
        m = a[..., 3:4] / 255.0
        a[..., :3] *= 1.0 + (np.array(color) - 1.0) * m
        a[..., 3] = 255
        mats[k] = (Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA"),) + tuple(mats[k][1:])


def _turn(a, b):
    """Rotation taking unit vector a onto b."""
    v, c = np.cross(a, b), float(np.dot(a, b))
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1 / (1 + c))


def body_mesh(model, arms_down=True):
    """The playermodel as the game draws it (anim0.posed_mesh), its arms lowered along the body (the first
    frame of its idle holds them out: a player standing with nothing in hand has them down), its clothes
    tinted: -> (pos, nrm, uv, tris, mats), {bone name: world matrix}."""
    pos, nrm, uv, tris, mats = mr.load_model(model)
    bones = refbody.bones(model)
    names = [b["name"] for b in bones]
    world = [w.copy() for w in anim0.rest_bones(model)]
    if arms_down:
        mid = world[names.index("ValveBiped.Bip01_Spine4")][:3, 3] if "ValveBiped.Bip01_Spine4" in names else np.zeros(3)
        for side in ("L", "R"):
            ua, fa = f"ValveBiped.Bip01_{side}_UpperArm", f"ValveBiped.Bip01_{side}_Forearm"
            if ua not in names or fa not in names:
                continue
            k0 = names.index(ua)
            sh, el = world[k0][:3, 3], world[names.index(fa)][:3, 3]
            out = 1.0 if sh[1] > mid[1] else -1.0
            want = np.array([0.08, out * math.sin(math.radians(9)), -math.cos(math.radians(9))])
            R = _turn((el - sh) / np.linalg.norm(el - sh), want / np.linalg.norm(want))
            kids, grew = {k0}, True
            while grew:
                grew = False
                for k, b in enumerate(bones):
                    if b["parent"] in kids and k not in kids:
                        kids.add(k)
                        grew = True
            T = np.eye(4)
            T[:3, :3], T[:3, 3] = R, sh - R @ sh
            for k in kids:
                world[k] = T @ world[k]
    K = np.array([world[k] @ np.linalg.inv(bones[k]["world"]) for k in range(len(bones))])
    B, Wt = mount_check.vertex_weights(model)
    h = np.c_[pos, np.ones(len(pos))]
    P, N = np.zeros_like(pos), np.zeros_like(nrm)
    for j in range(3):
        Kj = K[B[:, j]]
        P += Wt[:, j, None] * np.einsum("nij,nj->ni", Kj, h)[:, :3]
        N += Wt[:, j, None] * np.einsum("nij,nj->ni", Kj[:, :3, :3], nrm)
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-9
    mats = list(mats)
    tint_clothes(model, mats)
    return [P, N, uv.copy(), tris, mats], {n: world[k] for k, n in enumerate(names)}


# ---------------------------------------------------------------- items

def bonemerged(gear_key, cls, bones):
    """A rigged item's mesh bonemerged on a body (bones: {name: posed world matrix}): every bone of the item
    takes the body's bone of the same name (cl_gear.lua: EF_BONEMERGE); only the item's own triangles."""
    pack = PACKS[gear_key]
    draw = pack["models"][0]
    gear = vc.gear_of(gear_key, cls)  # (its triangles and their vertices, renumbered)
    parts = mg.bodyparts(draw)
    empty = mg.empty_choices(parts)
    base = {b: empty.get(b, 0) for b in range(len(parts))}
    base_tris = {tuple(t) for t in mg.posed(draw, base)[3]}
    it = next(x for x in pack["items"] if x["class"] == cls)
    sel = dict(base)
    for part, sub in it["show"]:
        b, s = mg.find(parts, part, sub)
        sel[b] = s
    mr.BODYGROUPS[draw.lower()] = sel
    pos, nrm, uv, tris, mats = mr.load_model(draw)
    keep = [t for t in tris if tuple(t) not in base_tris]
    ib = refbody.bones(draw)
    rest = anim0.rest_bones(draw)
    worlds = []
    for k, b in enumerate(ib):
        if b["name"] in bones:
            W = bones[b["name"]]
        elif b["parent"] >= 0:
            W = worlds[b["parent"]] @ np.linalg.inv(rest[b["parent"]]) @ rest[k]
        else:
            W = rest[k]
        worlds.append(W)
    K = np.array([worlds[k] @ np.linalg.inv(ib[k]["world"]) for k in range(len(ib))])
    B, Wt = mount_check.vertex_weights(draw)
    h = np.c_[pos, np.ones(len(pos))]
    P, N = np.zeros_like(pos), np.zeros_like(nrm)
    for j in range(3):
        Kj = K[B[:, j]]
        P += Wt[:, j, None] * np.einsum("nij,nj->ni", Kj, h)[:, :3]
        N += Wt[:, j, None] * np.einsum("nij,nj->ni", Kj[:, :3, :3], nrm)
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-9
    used = sorted({t[k] for t in keep for k in range(3)})
    new = {v: n for n, v in enumerate(used)}
    del gear
    return P[used], N[used], uv[used], [(new[a], new[b], new[c], t) for a, b, c, t in keep], mats


def placed(gear, top, xc, n, Tt):
    """An item's mesh placed by its fit numbers n (pos, angles, size[, height[, depth]]) on a bone (world Tt)."""
    P, N = gear[0].copy(), gear[1].copy()
    st = n[7] if len(n) > 7 else 1.0
    dp = n[8] if len(n) > 8 else 1.0
    if top is not None and st != 1:
        P[:, 2] = top + (P[:, 2] - top) * st
        N = N / np.array([1.0, 1.0, st])
    if xc is not None and dp != 1:
        P[:, 0] = xc + (P[:, 0] - xc) * dp
        N = N / np.array([dp, 1.0, 1.0])
    R = Tt[:3, :3] @ mg.angle_matrix(n[3:6])
    W = (R @ (P * n[6]).T).T + Tt[:3, :3] @ np.array(n[:3]) + Tt[:3, 3]
    N = (R @ N.T).T
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-9
    return W, N, gear[2], gear[3], gear[4]


def merge(meshes):
    pos, nrm, uv, tris, mats = [], [], [], [], []
    for p, n, u, t, m in meshes:
        off, moff = sum(len(x) for x in pos), len(mats)
        pos.append(p)
        nrm.append(n)
        uv.append(u)
        tris += [(a + off, b + off, c + off, k + moff) for a, b, c, k in t]
        mats += list(m)
    return np.concatenate(pos), np.concatenate(nrm), np.concatenate(uv), tris, mats


def subject(s, items, cam_dir):
    """One playermodel and its items, turned and moved into the scene: (mesh, points to frame by)."""
    model = s["model"]
    yaw = math.radians(s.get("yaw", 0.0))
    Rz = np.array([[math.cos(yaw), -math.sin(yaw), 0.0], [math.sin(yaw), math.cos(yaw), 0.0], [0.0, 0.0, 1.0]])
    off = np.array(list(s.get("pos", [0, 0])) + [0.0])
    body, bones = body_mesh(model, s.get("arms_down", True))
    tb = mg.posed_bones(model)
    head = tb[mg.fi.HEAD][0][:3, 3]
    # the camera, far along cam_dir from the scene, seen from this model's space: the eyes look at it
    draw_eyes(model, body, Rz.T @ ((Rz @ head + off) + cam_dir * 300.0 - off))
    meshes = [tuple(body)]
    for cls in s.get("items", []):
        key, slot, top, xc, rigged, fits = items[cls]
        if rigged:
            meshes.append(bonemerged(key, cls, bones))
            continue
        n = fits.get(model.lower())
        if not n:
            print(f"{cls}: no fit on {model}, left out")
            continue
        meshes.append(placed(vc.gear_of(key, cls), top, xc, n, tb[mg.BONE[slot]][0]))
    P, N, uv, tris, mats = merge(meshes)
    P = P @ Rz.T + off
    N = N @ Rz.T
    neck = Rz @ tb[mg.NECK][0][:3, 3] + off
    pel = Rz @ tb[mg.PELVIS][0][:3, 3] + off
    return (P, N, uv, tris, mats), (neck, pel, Rz @ head + off)


def render(scene, out):
    size = int(scene.get("size", 1024))
    cam = scene.get("camera", {})
    yaw, pitch = float(cam.get("yaw", 0.0)), float(cam.get("pitch", 6.0))
    cam_dir = np.array([math.cos(math.radians(pitch)) * math.cos(math.radians(yaw)),
                        math.cos(math.radians(pitch)) * math.sin(math.radians(yaw)), math.sin(math.radians(pitch))])
    items = all_items()
    meshes, frame = [], []
    for s in scene["subjects"]:
        mesh, (neck, pel, head) = subject(s, items, cam_dir)
        meshes.append(mesh)
        kind = cam.get("frame", "chest")
        lo = pel if kind == "chest" else (head - np.array([0, 0, 5.0]) if kind == "head" else pel - (neck - pel) * 1.6)
        lo = lo - np.array([0, 0, float(cam.get("below", 0.0))])  # (room under it: a title over the legs)
        top = mesh[0][np.argmax(mesh[0][:, 2])]  # (the highest of the head and what is on it: night vision)
        frame += [head + np.array([0, 0, 7.0]), top + np.array([0, 0, 2.0]), lo, neck + np.array([0, 9.0, 0]),
                  neck - np.array([0, 9.0, 0])]
    P, N, uv, tris, mats = merge(meshes)
    img = mr.rasterize(P, N, uv, tris, mats, yaw, pitch, np.array(frame), size=size)
    bg = np.array(scene.get("background", [70, 76, 86, 28, 30, 36]), dtype=float)
    t = np.linspace(0, 1, size)[:, None, None]
    grad = (bg[:3] * (1 - t) + bg[3:] * t) * np.ones((1, size, 1))
    base = Image.fromarray(grad.astype(np.uint8), "RGB").convert("RGBA")
    base.alpha_composite(img)
    base.convert("RGB").save(out)
    print(out)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    render(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")), sys.argv[2])
