"""Contact sheets of playermodels "bare" (every bodypart that has an empty choice set to it, the others
at 0), front and back, with their bodyparts listed: what is left on the bare body is built-in gear.

    python sheets.py <tools> <pms.tsv> <out_dir> [ids...]   (MDL_EXTRA_DIRS: the collection folders)

One sheet per 12 models (sheet_NN.jpg) and index.txt: sheet, cell, id, model, bodyparts.
"""
import sys
from multiprocessing import Pool
from pathlib import Path

TOOLS, TSV, OUT = sys.argv[1], sys.argv[2], Path(sys.argv[3])
ONLY = set(sys.argv[4:])
sys.path.insert(0, TOOLS)
S = 190


def render(row):
    from PIL import Image
    import modelgear_pack as mp
    import mdl_render as mr
    import mount_check as mc
    wid, model = row[0], row[1]
    try:
        parts = mp.bodyparts(model)
        sel = {b: 0 for b in range(len(parts))}
        sel.update(mp.empty_choices(parts))
        P, N, uv, tris, mats = mp.posed(model, sel)
        face = mc.facing_yaw(model)
        out = []
        for yaw in (15, 195):
            img = mr.rasterize(P, N, uv, tris, mats, face + yaw, 8, P, size=S)
            bg = Image.new("RGBA", img.size, (96, 100, 108, 255))
            bg.alpha_composite(img)
            out.append(bg.convert("RGB").tobytes())
        return row, out, None
    except Exception as ex:  # noqa: BLE001
        return row, None, str(ex)[:60]


if __name__ == "__main__":
    from PIL import Image, ImageDraw
    rows = [l.rstrip("\n").split("\t") for l in open(TSV, encoding="utf-8")]
    rows = [r for r in rows if r[3] == "ok" and r[5] == "VB" and (not ONLY or r[0] in ONLY)]
    OUT.mkdir(parents=True, exist_ok=True)
    with Pool(6) as pool:
        done = pool.map(render, rows, chunksize=1)
    per = 12
    index = []
    for k in range(0, len(done), per):
        chunk = done[k:k + per]
        sheet = Image.new("RGB", (4 * 2 * S, 3 * (S + 34)), (22, 22, 24))
        d = ImageDraw.Draw(sheet)
        for c, (row, imgs, err) in enumerate(chunk):
            x, y = (c % 4) * 2 * S, (c // 4) * (S + 34)
            if imgs:
                for v, raw in enumerate(imgs):
                    sheet.paste(Image.frombytes("RGB", (S, S), raw), (x + v * S, y))
            d.text((x + 3, y + S + 1), f"{c}: {row[0]} {row[1].split('/')[-1]}", fill=(250, 220, 110))
            d.text((x + 3, y + S + 16), (err or row[6])[:64], fill=(200, 200, 200))
            index.append(f"sheet_{k // per:02d}\t{c}\t{row[0]}\t{row[1]}\t{row[6]}")
        sheet.save(OUT / f"sheet_{k // per:02d}.jpg", quality=85)
    (OUT / "index.txt").write_text("\n".join(index) + "\n", encoding="utf-8")
    print(len(done), "models,", (len(done) + per - 1) // per, "sheets")
