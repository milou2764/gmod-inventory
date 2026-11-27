"""Pose of a model as the game draws it at rest: first frame of its first sequence (dev tool, not in
the .gma). Weapon world models (w_*.mdl) are stored with the gun along -Y; their idle animation
turns it along +X, and that is what ClientsideModel / dropped weapons show.

    posed_mesh(model) -> (pos, nrm, uv, tris, mats) like mdl_render.load_model, in the rest pose
    rest_bones(model) -> list of 4x4 bone -> model matrices of that pose

Format: studiohdr (v44-49) -> seqdesc 0 -> animdesc -> mstudioanim_t per animated bone (raw or
RLE-compressed rotation / position); bones without data keep their default pos / quat.
Static props (header flag STUDIOHDR_FLAGS_STATIC_PROP) are not animated by the engine: they are drawn
in their stored (bind) pose, so that is what rest_bones returns for them.
"""
import math
import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mdl_render as mr  # noqa: E402

RAWPOS, RAWROT, ANIMPOS, ANIMROT, DELTA, RAWROT2 = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20
STATIC_PROP = 0x10  # studiohdr flags
# Models the game draws in their bind pose turned to face +x, not in their first sequence's: the
# Escape From Tarkov PMC playermodels, whose first sequence ("reference", 101 frames) stores a taller
# skeleton the game doesn't show (measured in game: pelvis, spine, chest, head and hands exactly at
# their bind places, turned a quarter; the feet a little off). Lowercase paths; modelgear_pack.py adds
# a pack's with "bind_positions".
BIND_POSITIONS = set()
_TURN = np.array([[0.0, -1.0, 0.0, 0.0], [1.0, 0.0, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0], [0.0, 0.0, 0.0, 1.0]])


def quat_matrix(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def euler_quat(a):
    """Source AngleQuaternion(RadianEuler): a = (x, y, z) radians."""
    sr, cr = math.sin(a[0] / 2), math.cos(a[0] / 2)
    sp, cp = math.sin(a[1] / 2), math.cos(a[1] / 2)
    sy, cy = math.sin(a[2] / 2), math.cos(a[2] / 2)
    return (sr * cp * cy - cr * sp * sy, cr * sp * cy + sr * cp * sy, cr * cp * sy - sr * sp * cy,
            cr * cp * cy + sr * sp * sy)


def half(h):
    return float(np.frombuffer(struct.pack("<H", h), dtype=np.float16)[0])


def rest_bones(model):
    d = mr.vpk_read(model)
    i = lambda o: struct.unpack_from("<i", d, o)[0]
    if i(152) & STATIC_PROP:
        import refbody  # noqa: E402
        return [b["world"] for b in refbody.bones(model)]
    if model.lower() in BIND_POSITIONS:
        import refbody  # noqa: E402
        return [_TURN @ b["world"] for b in refbody.bones(model)]
    nb, bi = i(156), i(160)
    bones = []
    for k in range(nb):
        o = bi + k * 216
        bones.append({
            "parent": i(o + 4), "pos": list(struct.unpack_from("<3f", d, o + 32)),
            "quat": struct.unpack_from("<4f", d, o + 44), "rot": struct.unpack_from("<3f", d, o + 60),
            "posscale": struct.unpack_from("<3f", d, o + 72), "rotscale": struct.unpack_from("<3f", d, o + 84),
        })
    local = {k: (b["pos"][:], b["quat"]) for k, b in enumerate(bones)}
    if i(188) > 0:
        seq = i(192)
        anim_idx = struct.unpack_from("<h", d, seq + i(seq + 60))[0]
        ad = i(184) + anim_idx * 100
        if i(ad + 52) == 0:  # data in the .mdl (not an external animation block)
            a = ad + i(ad + 56)
            if i(ad + 84) and i(ad + 80):  # sections: frame 0 is in section 0
                a = ad + struct.unpack_from("<i", d, ad + i(ad + 80) + 4)[0]
            while True:
                bone, flags, nxt = d[a], d[a + 1], struct.unpack_from("<h", d, a + 2)[0]
                if bone >= len(bones):
                    break  # unexpected data: keep what was read
                b = bones[bone]
                p = a + 4
                q = b["quat"]
                if flags & RAWROT:
                    x, y, zw = struct.unpack_from("<HHH", d, p)
                    qx, qy, qz = (x - 32768) / 32768.0, (y - 32768) / 32768.0, ((zw & 0x7FFF) - 16384) / 16384.0
                    qw = math.sqrt(max(0.0, 1 - qx * qx - qy * qy - qz * qz)) * (-1 if zw & 0x8000 else 1)
                    q = (qx, qy, qz, qw)
                    p += 6
                if flags & RAWROT2:
                    v = struct.unpack_from("<Q", d, p)[0]
                    qx = ((v & 0x1FFFFF) - 1048576) / 1048576.5
                    qy = (((v >> 21) & 0x1FFFFF) - 1048576) / 1048576.5
                    qz = (((v >> 42) & 0x1FFFFF) - 1048576) / 1048576.5
                    qw = math.sqrt(max(0.0, 1 - qx * qx - qy * qy - qz * qz)) * (-1 if v >> 63 else 1)
                    q = (qx, qy, qz, qw)
                    p += 8
                if flags & ANIMROT:
                    offs = struct.unpack_from("<3h", d, p)
                    ang = []
                    for j in range(3):
                        val = 0
                        if offs[j]:
                            vp = p + offs[j]
                            if d[vp] > 0:  # valid values in the first run: frame 0 is the first one
                                val = struct.unpack_from("<h", d, vp + 2)[0]
                        ang.append(val * b["rotscale"][j] + (0 if flags & DELTA else b["rot"][j]))
                    q = euler_quat(ang)
                    p += 6
                pos = b["pos"][:]
                if flags & RAWPOS:
                    pos = [half(h) for h in struct.unpack_from("<3H", d, p)]
                elif flags & ANIMPOS:
                    offs = struct.unpack_from("<3h", d, p)
                    for j in range(3):
                        val = 0
                        if offs[j]:
                            vp = p + offs[j]
                            if d[vp] > 0:
                                val = struct.unpack_from("<h", d, vp + 2)[0]
                        pos[j] = val * b["posscale"][j] + (0 if flags & DELTA else b["pos"][j])
                local[bone] = (pos, q)
                if not nxt:
                    break
                a += nxt
    world = []
    for k, b in enumerate(bones):
        m = np.eye(4)
        m[:3, :3] = quat_matrix(local[k][1])
        m[:3, 3] = local[k][0]
        if b["parent"] >= 0:
            m = world[b["parent"]] @ m
        world.append(m)
    return world


def posed_mesh(model, textures=True):
    """mdl_render.load_model, skinned into the rest pose (dominant bone of each vertex)."""
    import refbody  # noqa: E402  (bind matrices)
    pos, nrm, uv, tris, mats = mr.load_model(model, textures)
    world = rest_bones(model)
    bind = [b["world"] for b in refbody.bones(model)]
    K = np.array([world[k] @ np.linalg.inv(bind[k]) for k in range(len(world))])
    vvd = mr.vpk_read(model[:-4] + ".vvd")
    import mount_check  # noqa: E402  (vertex weights in load_model order)
    B, W = mount_check.vertex_weights(model)
    h = np.c_[pos, np.ones(len(pos))]
    P, N = np.zeros_like(pos), np.zeros_like(nrm)
    for j in range(3):
        Kj = K[B[:, j]]
        P += W[:, j, None] * np.einsum("nij,nj->ni", Kj, h)[:, :3]
        N += W[:, j, None] * np.einsum("nij,nj->ni", Kj[:, :3, :3], nrm)
    N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-9
    return P, N, uv, tris, mats


if __name__ == "__main__":
    for name in sys.argv[1:]:
        m = name if name.endswith(".mdl") else f"models/weapons/{name}.mdl"
        P, *_rest, tris, _m = posed_mesh(m)
        used = sorted({t[k] for t in tris for k in range(3)})
        d = mr.vpk_read(m)
        hull = np.round(struct.unpack_from("<6f", d, 104), 1)
        print(f"{name:18} rest pose {np.round(P[used].min(0), 1)} .. {np.round(P[used].max(0), 1)} | hull {hull[:3]} .. {hull[3:]}")
