"""Offline check of how the worn items sit on playermodels (dev tool, not in the .gma).

For every worn item in lua/entities (helmets, masks, backpacks, vests...), reads ENT.Model and
ENT.Attach and places the model on the playermodel's bones in its reference pose, the way the game
does it (lua/advinv/cl_gear.lua):
  - with ENT.Attach: FollowBone on attach.bone, then local offset attach.pos / attach.ang, size
    attach.scale;
  - without it (bonemerge): every bone of the item takes the transform of the playermodel's bone
    of the same name; other bones follow their parent.
Then it renders the item on the whole body (arms included) from the front, the left and the back.

Items are drawn in their rest pose (first frame of their idle sequence, anim0.py), like the game:
several props (Barney helmet, jetpack...) are stored turned and only reach their real orientation
through that animation. Not simulated: ENT.BodyFit (vests / backpacks of item packs), the body's
own animations (only the bone the item follows matters for its fit).

Usage (from this folder):
    python mount_check.py <out_dir> [playermodel ...]
Default playermodels: Dr. Isaac Kleiner and male_07 (the reference body).
"""
import math
import re
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import anim0  # noqa: E402
import mdl_render as mr  # noqa: E402
import refbody  # noqa: E402

ENTITIES = Path(__file__).resolve().parents[1] / "lua" / "entities"
WORN_BASES = {"advinv_base_helmet", "advinv_base_gear", "advinv_base_rucksack", "advinv_base_vest", "advinv_base_pocketvest"}
DEFAULT_MODELS = ["models/player/kleiner.mdl", "models/player/group01/male_07.mdl"]
ARM_BONES = re.compile(r"UpperArm|Forearm|Hand|Finger|Wrist|Ulna|Elbow|Bicep")
# (name, angle from the face, pitch): front-left 3/4, left profile, back-right 3/4
VIEWS = [("front-left", 45, 12), ("left", 90, 5), ("back-right", 225, 15)]
SIZE = 360


def model_fits():
    """Per-playermodel fits from lua/advinv/cl_fits_data.lua: {model: {class: (pos, ang, scale)}}."""
    p = ENTITIES.parent / "advinv" / "cl_fits_data.lua"
    fits = {}
    if not p.exists():
        return fits
    cur = None
    for line in p.read_text(encoding="utf-8").splitlines():
        m = re.match(r'\s*\["([^"]+)"\] = \{', line)
        if m:
            cur = fits.setdefault(m.group(1), {})
            continue
        m = re.match(r"\s*(\w+) = \{ V\(([^)]*)\), A\(([^)]*)\), ([\d.]+) \},", line)
        if m and cur is not None:
            num = lambda s: [float(x) for x in s.split(",")]
            cur[m.group(1)] = (np.array(num(m.group(2))), num(m.group(3)), float(m.group(4)))
    return fits


def attach_for(cls, att, playermodel, fits):
    """Like AdvInv.AttachFor: the playermodel's fit, else the item's own ENT.Attach."""
    f = fits.get(playermodel, {}).get(cls)
    if not (f and att):
        return att
    return {"bone": att["bone"], "pos": f[0], "ang": f[1], "scale": f[2]}


def worn_items():
    """(class, model, attach or None, has BodyFit) for every worn item of the addon."""
    out = []
    for p in sorted(ENTITIES.glob("*.lua")):
        t = p.read_text(encoding="utf-8")
        base = re.search(r'^ENT\.Base\s*=\s*"([^"]+)"', t, re.M)
        model = re.search(r'^ENT\.Model\s*=\s*"([^"]+)"', t, re.M)
        if not (base and model and base.group(1) in WORN_BASES):
            continue
        att = None
        m = re.search(r"^ENT\.Attach\s*=\s*\{(.*?)^\}", t, re.M | re.S)
        if m:
            body = m.group(1)
            num = lambda s: [float(x) for x in s.split(",")]
            bone = re.search(r'bone\s*=\s*"([^"]+)"', body)
            pos = re.search(r"pos\s*=\s*Vector\(([^)]*)\)", body)
            ang = re.search(r"ang\s*=\s*Angle\(([^)]*)\)", body)
            scale = re.search(r"scale\s*=\s*([\d.]+)", body)
            att = {
                "bone": bone.group(1) if bone else "ValveBiped.Bip01_Head1",
                "pos": np.array(num(pos.group(1))) if pos else np.zeros(3),
                "ang": num(ang.group(1)) if ang else [0, 0, 0],
                "scale": float(scale.group(1)) if scale else 1.0,
            }
        out.append((p.stem, model.group(1), att, "ENT.BodyFit" in t))
    return out


def vertex_weights(model):
    """Bones (N x 3) and weights (N x 3) of every vertex, in the order of mdl_render.load_model."""
    vv = mr.vvd_lod0(mr.vpk_read(model[:-4] + ".vvd"))
    used = np.arange(3)[None, :] < vv["n"][:, None]  # (only the first numbones of each vertex count)
    B = np.where(used, vv["b"].astype(int), 0)
    W = np.where(used, vv["w"].astype(np.float64), 0.0)
    return B, W


def body_bones(model):
    return {b["name"]: b["world"] for b in refbody.bones(model)}


def facing_yaw(model):
    """Direction the face looks in the reference pose (degrees), from the model's 'eyes' attachment."""
    d = mr.vpk_read(model)
    i = lambda o: struct.unpack_from("<i", d, o)[0]
    B = refbody.bones(model)
    for a in range(i(240)):
        o = i(244) + a * 92
        if mr.cstr(d, o + i(o)) == "eyes":
            L = np.vstack([np.array(struct.unpack_from("<12f", d, o + 12)).reshape(3, 4), [0, 0, 0, 1]])
            f = (B[i(o + 8)]["world"] @ L)[:3, 0]
            return math.degrees(math.atan2(f[1], f[0]))
    return -90.0  # ValveBiped reference pose: the body faces -Y


def place_item(model, att, bones):
    """Item mesh moved onto the body (body model space, reference pose)."""
    if att:
        pos, nrm, uv, tris, mats = anim0.posed_mesh(model)
        if att["bone"] not in bones:
            return None
        Bw = bones[att["bone"]]
        M = Bw[:3, :3] @ mr.rot_matrix(*att["ang"])
        t = Bw[:3, :3] @ att["pos"] + Bw[:3, 3]
        return (pos * att["scale"]) @ M.T + t, nrm @ M.T, uv, tris, mats
    pos, nrm, uv, tris, mats = mr.load_model(model)
    ib = refbody.bones(model)
    rest = anim0.rest_bones(model)
    worlds = []
    for k, b in enumerate(ib):
        if b["name"] in bones:
            W = bones[b["name"]]
        elif b["parent"] >= 0:  # not on the body: follows its parent with its own rest offset
            W = worlds[b["parent"]] @ np.linalg.inv(rest[b["parent"]]) @ rest[k]
        else:
            W = rest[k]
        worlds.append(W)
    K = np.array([worlds[k] @ np.linalg.inv(ib[k]["world"]) for k in range(len(ib))])
    B, Wt = vertex_weights(model)
    h = np.c_[pos, np.ones(len(pos))]
    P, N = np.zeros_like(pos), np.zeros_like(nrm)
    for j in range(3):
        Kj = K[B[:, j]]
        P += Wt[:, j, None] * np.einsum("nij,nj->ni", Kj, h)[:, :3]
        N += Wt[:, j, None] * np.einsum("nij,nj->ni", Kj[:, :3, :3], nrm)
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-9
    return P, N, uv, tris, mats


def load_body(model, arms=True):
    """The playermodel's mesh in its reference pose: the whole of it (arms=False: without its arms)."""
    pos, nrm, uv, tris, mats = mr.load_model(model)
    if arms:
        return pos, nrm, uv, tris, mats
    names = [b["name"] for b in refbody.bones(model)]
    B, W = vertex_weights(model)
    arm = np.array([bool(ARM_BONES.search(names[B[k, int(np.argmax(W[k]))]])) for k in range(len(pos))])
    tris = [t for t in tris if not (arm[t[0]] or arm[t[1]] or arm[t[2]])]
    return pos, nrm, uv, tris, mats


def merge(a, b):
    pa, na, ua, ta, ma = a
    pb, nb, ub, tb, mb = b
    off, moff = len(pa), len(ma)
    tris = ta + [(i0 + off, i1 + off, i2 + off, t + moff) for i0, i1, i2, t in tb]
    return np.r_[pa, pb], np.r_[na, nb], np.r_[ua, ub], tris, ma + mb


def label(img, text):
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 8 + 7 * len(text), 18), fill=(0, 0, 0))
    d.text((4, 3), text, fill=(240, 240, 240))
    return img


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    models = sys.argv[2:] or DEFAULT_MODELS
    bodies = {m: (load_body(m), body_bones(m), facing_yaw(m)) for m in models}
    fits = model_fits()
    for cls, model, att0, bodyfit in worn_items():
        sheet = Image.new("RGB", (SIZE * len(VIEWS), SIZE * len(models)), (40, 42, 46))
        for row, pm in enumerate(models):
            body, bones, face = bodies[pm]
            att = attach_for(cls, att0, pm, fits)
            item = place_item(model, att, bones)
            if item is None:
                print(f"{cls}: bone {att['bone']} missing on {pm}")
                continue
            ipos = item[0][sorted({t[k] for t in item[3] for k in range(3)})]
            c = (ipos.min(0) + ipos.max(0)) / 2
            r = np.linalg.norm(ipos.max(0) - ipos.min(0)) / 2
            near = body[0][np.linalg.norm(body[0] - c, axis=1) < r * 1.6 + 4]
            fit = np.r_[ipos, near]
            scene = merge(body, item)
            for col, (name, yaw, pitch) in enumerate(VIEWS):
                img = mr.rasterize(*scene, face + yaw, pitch, fit, size=SIZE)
                bg = Image.new("RGBA", img.size, (78, 82, 90, 255))
                bg.alpha_composite(img)
                sheet.paste(label(bg.convert("RGB"), f"{Path(pm).stem} - {name}"), (col * SIZE, row * SIZE))
        sheet.save(out / f"{cls}.png")
        how = f"Attach {att0['bone'].split('.')[-1]}" if att0 else "bonemerge"
        print(f"ok {cls} ({how}{', BodyFit not simulated' if bodyfit else ''})")


if __name__ == "__main__":
    mr.WORK.mkdir(parents=True, exist_ok=True)
    main()
