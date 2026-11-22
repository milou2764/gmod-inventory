"""Mesures du torse des playermodels autour de leur os Spine4 (pose de référence), qui servent à
placer gilets et sacs sur chaque playermodel (outil de développement, non inclus dans le .gma).

Repère : axes de l'os Spine4 de male_07 (même convention pour tout squelette ValveBiped), en unités.
  avant    : surface de la poitrine (négatif = devant Spine4)
  dos      : surface du dos (positif = derrière Spine4)
  épaule   : dessus de l'épaule, là où passent les bretelles (au-dessus de Spine4)
  largeur  : largeur du torse à hauteur de poitrine

Utilisation (depuis ce dossier) :
    python bodyfit.py bodyfit.json playermodels.txt
    python bodyfit_lua.py bodyfit.json ../lua/advinv/cl_bodyfit_data.lua
playermodels.txt : un modèle par ligne (uniquement ceux fournis avec Garry's Mod).
"""
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import refbody  # noqa: E402

REF = refbody.REF
_ref = {b["name"]: b["world"] for b in refbody.bones(REF)}
_R = np.linalg.inv(_ref["ValveBiped.Bip01_Spine4"][:3, :3])
AX = {"back": _R @ [0, 1.0, 0], "up": _R @ [0, 0, 1.0], "lat": _R @ [1.0, 0, 0]}  # en coordonnées locales de Spine4


def metrics(model):
    bones = refbody.bones(model)
    names = [b["name"] for b in bones]
    need = ["ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine4"]
    if any(n not in names for n in need):
        return None
    W = bones[names.index("ValveBiped.Bip01_Spine4")]["world"]
    inv = np.linalg.inv(W)
    P, dom = refbody.skinned_vertices(model)
    L = (np.c_[P, np.ones(len(P))] @ inv.T)[:, :3]
    up, lat, back = L @ AX["up"], L @ AX["lat"], L @ AX["back"]
    s2 = ((inv @ bones[names.index("ValveBiped.Bip01_Spine2")]["world"][:, 3])[:3]) @ AX["up"]
    spine = [names.index(n) for n in names if n.startswith("ValveBiped.Bip01_Spine")]
    chest = np.isin(dom, spine) & (up > s2) & (up < 0) & (np.abs(lat) < 6)
    shoulder_ids = [names.index(n) for n in names
                    if n in ("ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_L_Clavicle", "ValveBiped.Bip01_R_Clavicle")]
    sh = np.isin(dom, shoulder_ids) & (np.abs(lat) > 3) & (np.abs(lat) < 6)
    if chest.sum() < 10 or sh.sum() < 5:
        return None
    return {
        "front": round(float(back[chest].min()), 2),
        "back": round(float(back[chest].max()), 2),
        "shoulder": round(float(up[sh].max()), 2),
        "width": round(float(lat[chest].max() - lat[chest].min()), 2),
    }


LIMITS = {"back": (-2.0, 2.0), "up": (-2.5, 3.5)}  # évite les extrêmes (cols, paquetages, monstres)


def offset_parts(kind, m, ref):
    """(profondeur, hauteur) du décalage d'un objet `kind` sur un corps de mesures m."""
    if kind == "vest":
        d_back = (m["front"] + m["back"]) / 2 - (ref["front"] + ref["back"]) / 2
        d_up = m["shoulder"] - ref["shoulder"]
    elif kind == "back":
        d_back = m["back"] - ref["back"]
        d_up = 0.5 * (m["shoulder"] - ref["shoulder"])
    else:
        return 0.0, 0.0
    return float(np.clip(d_back, *LIMITS["back"])), float(np.clip(d_up, *LIMITS["up"]))


def offset(kind, m, ref):
    """Local offset (in Spine4 coordinates) to apply to a gear of `kind` on a body with metrics m."""
    d_back, d_up = offset_parts(kind, m, ref)
    return AX["back"] * d_back + AX["up"] * d_up


if __name__ == "__main__":
    models = [l.strip() for l in Path(sys.argv[2]).read_text(encoding="utf-8").splitlines() if l.strip()]
    out = {"_ref": REF, "_axes": {k: [round(float(x), 6) for x in v] for k, v in AX.items()}, "models": {}}
    ref = metrics(REF)
    for m in models:
        try:
            r = metrics(m)
        except Exception as e:  # noqa: BLE001
            print(f"{m}: erreur {e}")
            continue
        if r is None:
            print(f"{m}: ignoré (pas de squelette ValveBiped exploitable)")
            continue
        out["models"][m] = r
        dv = offset("vest", r, ref)
        print(f"{m:46} avant {r['front']:+6.2f} dos {r['back']:+6.2f} épaule {r['shoulder']:+6.2f} "
              f"largeur {r['width']:5.1f} | gilet: profondeur {dv @ AX['back']:+5.2f} hauteur {dv @ AX['up']:+5.2f}")
    Path(sys.argv[1]).write_text(json.dumps(out, indent=1), encoding="utf-8")
    print(len(out["models"]), "playermodels mesurés")
