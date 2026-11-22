"""Écrit lua/advinv/cl_bodyfit_data.lua à partir de bodyfit.json.

Utilisation : python bodyfit_lua.py <bodyfit.json> <out.lua>
"""
import json
import sys
from pathlib import Path

d = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
ax = d["_axes"]
ref = d["models"][d["_ref"]]
L = [
    "-- Mesures du torse des playermodels fournis avec Garry's Mod, autour de l'os Spine4",
    "-- (pose de référence). Fichier généré par tools/bodyfit.py + tools/bodyfit_lua.py : ne pas",
    "-- modifier à la main. Valeurs : { avant de la poitrine, dos, dessus de l'épaule }, en unités.",
    "-- Un addon peut ajouter ses playermodels : AdvInv.BodyFit.models[\"models/x.mdl\"] = { av, dos, ép }",
    "AdvInv.BodyFit = AdvInv.BodyFit or {}",
    "local BF = AdvInv.BodyFit",
    "",
    f'BF.ref = "{d["_ref"]}" -- corps sur lequel les objets « BodyFit » sont ajustés',
    f'BF.refMetrics = {{ {ref["front"]}, {ref["back"]}, {ref["shoulder"]} }}',
    "-- axes « arrière » et « haut » dans le repère local de l'os Spine4",
    f'BF.axes = {{ back = Vector({ax["back"][0]}, {ax["back"][1]}, {ax["back"][2]}), '
    f'up = Vector({ax["up"][0]}, {ax["up"][1]}, {ax["up"][2]}) }}',
    "BF.models = BF.models or {}",
    "local M = BF.models",
]
for mdl, m in sorted(d["models"].items()):
    L.append(f'M["{mdl}"] = {{ {m["front"]}, {m["back"]}, {m["shoulder"]} }}')
Path(sys.argv[2]).write_text("\n".join(L) + "\n", encoding="utf-8", newline="\n")
print(len(d["models"]), "playermodels écrits dans", sys.argv[2])
