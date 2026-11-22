"""Lecture des modèles compilés de Source (.mdl, .vvd) : os (pose de référence), attachements,
sommets par os. Sert à reprendre le squelette d'un modèle du jeu (animations par $includemodel) et à
placer un nouveau maillage exactement là où était l'ancien.

    python studio.py <modele.mdl>          -> os, attachements, boîtes des sommets par os
"""
import math
import struct
import sys
from pathlib import Path

import numpy as np


def _cstr(data, off):
    end = data.index(b"\0", off)
    return data[off:end].decode("latin-1")


def quat_to_matrix(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


class Model:
    def __init__(self, mdl_bytes, vvd_bytes=None):
        d = mdl_bytes
        self.data = d
        ident, self.version = struct.unpack_from("<4si", d, 0)
        assert ident == b"IDST", "pas un .mdl"
        self.name = d[12:76].split(b"\0")[0].decode("latin-1")
        numbones, boneindex = struct.unpack_from("<ii", d, 156)
        self.bones = []
        for i in range(numbones):
            o = boneindex + i * 216
            nameidx, parent = struct.unpack_from("<ii", d, o)
            pos = struct.unpack_from("<3f", d, o + 32)
            quat = struct.unpack_from("<4f", d, o + 44)
            rot = struct.unpack_from("<3f", d, o + 60)
            pose_to_bone = np.array(struct.unpack_from("<12f", d, o + 96)).reshape(3, 4)
            flags, = struct.unpack_from("<i", d, o + 160)
            self.bones.append({
                "name": _cstr(d, o + nameidx), "parent": parent, "pos": pos, "quat": quat, "rot": rot,
                "poseToBone": pose_to_bone, "flags": flags,
            })
        numatt, attindex = struct.unpack_from("<ii", d, 240)
        self.attachments = []
        for i in range(numatt):
            o = attindex + i * 92
            nameidx, flags, bone = struct.unpack_from("<iIi", d, o)
            local = np.array(struct.unpack_from("<12f", d, o + 12)).reshape(3, 4)
            self.attachments.append({"name": _cstr(d, o + nameidx), "bone": bone, "local": local})
        # matrices monde de la pose de référence (os -> modèle)
        self.world = []
        for b in self.bones:
            m = np.eye(4)
            m[:3, :3] = quat_to_matrix(b["quat"])
            m[:3, 3] = b["pos"]
            if b["parent"] >= 0:
                m = self.world[b["parent"]] @ m
            self.world.append(m)
        self.vertices = None
        if vvd_bytes:
            self._read_vvd(vvd_bytes)

    def _read_vvd(self, v):
        ident, version, checksum, numlods = struct.unpack_from("<4siii", v, 0)
        assert ident == b"IDSV"
        lodverts = struct.unpack_from("<8i", v, 16)
        numfixups, fixupstart, vertstart, tangstart = struct.unpack_from("<4i", v, 48)
        n = lodverts[0]
        verts = []
        if numfixups == 0:
            idx = range(n)
        else:  # LOD 0 : toutes les plages de correction dont le niveau est >= 0
            idx = []
            for i in range(numfixups):
                lod, src, count = struct.unpack_from("<3i", v, fixupstart + i * 12)
                if lod >= 0:
                    idx.extend(range(src, src + count))
        for i in idx:
            o = vertstart + i * 48
            w = struct.unpack_from("<3f", v, o)
            b = struct.unpack_from("<3B", v, o + 12)
            nb = v[o + 15]
            p = struct.unpack_from("<3f", v, o + 16)
            nrm = struct.unpack_from("<3f", v, o + 28)
            uv = struct.unpack_from("<2f", v, o + 40)
            verts.append((p, b[0] if nb >= 1 else -1, w[0], nrm, uv))
        self.vertices = verts

    def bone_index(self, name):
        for i, b in enumerate(self.bones):
            if b["name"].lower() == name.lower():
                return i
        return -1

    def attachment_world(self, a):
        m = np.eye(4)
        m[:3, :] = a["local"]
        return self.world[a["bone"]] @ m

    def report(self):
        print(f"{self.name} (version {self.version}) : {len(self.bones)} os, {len(self.attachments)} attachements")
        for i, b in enumerate(self.bones):
            w = self.world[i][:3, 3]
            print(f"  {i:2d} {b['name']:<34} parent {b['parent']:2d}  pos {tuple(round(x, 3) for x in b['pos'])}"
                  f"  monde ({w[0]:.2f}, {w[1]:.2f}, {w[2]:.2f})")
        for a in self.attachments:
            m = self.attachment_world(a)
            print(f"  attache {a['name']:<16} os {self.bones[a['bone']]['name']:<26} monde ({m[0, 3]:.2f}, {m[1, 3]:.2f}, {m[2, 3]:.2f})"
                  f" avant ({m[0, 0]:.2f}, {m[1, 0]:.2f}, {m[2, 0]:.2f})")
        if self.vertices:
            byb = {}
            for p, b, w, _, _ in self.vertices:
                byb.setdefault(b, []).append(p)
            for b, ps in sorted(byb.items()):
                a = np.array(ps)
                name = self.bones[b]["name"] if b >= 0 else "?"
                print(f"  sommets {name:<30} {len(ps):5d}  min {np.round(a.min(0), 2)}  max {np.round(a.max(0), 2)}")


if __name__ == "__main__":
    p = Path(sys.argv[1])
    vvd = p.with_suffix(".vvd")
    Model(p.read_bytes(), vvd.read_bytes() if vvd.exists() else None).report()
