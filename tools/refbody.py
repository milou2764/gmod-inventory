"""Reference ValveBiped body (male_07): bones (local pos/rot, world bind matrices) and skinned vertices."""
import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mdl_render as mr  # noqa: E402

REF = "models/player/group01/male_07.mdl"


def cstr(d, off):
    return d[off:d.index(b"\0", off)].decode("latin-1")


def bones(model=REF):
    d = mr.vpk_read(model)
    i = lambda o: struct.unpack_from("<i", d, o)[0]
    out = []
    for k in range(i(d, 156) if False else struct.unpack_from("<i", d, 156)[0]):
        b = struct.unpack_from("<i", d, 160)[0] + k * 216
        name = cstr(d, b + struct.unpack_from("<i", d, b)[0])
        parent = struct.unpack_from("<i", d, b + 4)[0]
        pos = np.array(struct.unpack_from("<3f", d, b + 32))
        rot = np.array(struct.unpack_from("<3f", d, b + 60))
        p2b = np.array(struct.unpack_from("<12f", d, b + 96)).reshape(3, 4)
        m = np.eye(4)
        m[:3, :] = p2b
        world = np.linalg.inv(m)  # bind pose: bone -> model space
        out.append({"name": name, "parent": parent, "pos": pos, "rot": rot, "world": world})
    return out


def skinned_vertices(model=REF):
    """Positions (model space) and dominant bone index of every LOD0 vertex used by triangles."""
    vvd = mr.vpk_read(model[:-4] + ".vvd")
    pos, nrm, uv, tris, mats = mr.load_model(model, textures=False)  # (geometry only)
    nfix, fixstart, vstart = (struct.unpack_from("<i", vvd, o)[0] for o in (48, 52, 56))
    raw_bone = []
    for k in range(struct.unpack_from("<i", vvd, 16)[0]):
        o = vstart + k * 48
        w = struct.unpack_from("<3f", vvd, o)
        b = struct.unpack_from("<3b", vvd, o + 12)
        nb = vvd[o + 15]
        raw_bone.append(b[int(np.argmax(w[:nb]))] if nb else 0)
    if nfix:
        bone = []
        for f in range(nfix):
            lod, src, num = struct.unpack_from("<3i", vvd, fixstart + f * 12)
            if lod >= 0:
                bone.extend(raw_bone[src:src + num])
    else:
        bone = raw_bone
    used = sorted({t[k] for t in tris for k in range(3)})
    return pos[used], np.array(bone)[used]


if __name__ == "__main__":
    B = bones()
    names = [b["name"] for b in B]
    print("os:", len(B))
    for b in B[:20]:
        o = b["world"][:3, 3]
        print(f"   {b['name']:32} parent={b['parent']:3} origine={np.round(o, 1)}")
    P, dom = skinned_vertices()
    print("sommets corps:", len(P), "limites", np.round(P.min(0), 1), np.round(P.max(0), 1))
    def band(bone_names):
        ids = [names.index(n) for n in bone_names if n in names]
        sel = P[np.isin(dom, ids)]
        return sel
    torso = band(["ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine4"])
    print("torse (sommets dominés par Spine*):", len(torso), "min", np.round(torso.min(0), 1), "max", np.round(torso.max(0), 1))
    head = band(["ValveBiped.Bip01_Head1"])
    print("tête:", len(head), "min", np.round(head.min(0), 1), "max", np.round(head.max(0), 1))
    for z in (36, 40, 44, 48, 52, 56, 60):
        s = P[(np.abs(P[:, 2] - z) < 1.0) & (np.abs(P[:, 1]) < 9)]
        if len(s):
            print(f"   coupe z={z}: x[{s[:,0].min():.1f}, {s[:,0].max():.1f}]  y[{s[:,1].min():.1f}, {s[:,1].max():.1f}]")
