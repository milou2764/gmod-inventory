"""Reviewers' classification (BRIEF.md TSVs) -> the inventory's playermodel tables.

    python apply_review.py <addon dir> <pms.tsv> <items.json> <out_summary.txt> <result.tsv> [...]

- tools/playermodels_workshop.txt: the models (skip = '-'), grouped under "# <title> (Workshop <id>)",
  appended once (models already listed are left alone).
- tools/playermodel_bodygroups.txt: their measuring selection: every removable gear at its "none"
  value; a conditional slot whose built-in values include 0 measured on its first other value.
- lua/advinv/sh_modelgear.lua: a generated block (between markers, replaced on each run):
  def(model, { slots = { Slot = { [bp] = none } } }) for removable gear (our item takes theirs off; their
  choice comes back after), builtin(model, Slot) for built-in gear, builtin(model, Slot, { [bp] = {..} })
  for conditional gear.
"""
import json
import re
import sys
from collections import OrderedDict
from pathlib import Path

ADDON, PMS, ITEMS, SUMMARY = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
RESULTS = sys.argv[5:]
SLOTS = ("Helmet", "Gasmask", "Vest", "Rucksack", "NVGs", "Radio")
BEGIN = "-- BEGIN generated: Workshop playermodels (tools via apply_review.py)"
END = "-- END generated: Workshop playermodels"

wid_of, title = {}, {}
for l in open(PMS, encoding="utf-8"):
    f = l.rstrip("\n").split("\t")
    wid_of[f[1].lower()] = f[0]
for d in json.load(open(ITEMS, encoding="utf-8"))["response"]["publishedfiledetails"]:
    title[d["publishedfileid"]] = " ".join(str(d.get("title", "?")).split())  # (titles may hold line breaks)

rows = OrderedDict()
problems = []
for path in RESULTS:
    for n, l in enumerate(open(path, encoding="utf-8"), 1):
        f = l.rstrip("\n").split("\t")
        if len(f) < 5 or not f[0].lower().endswith(".mdl"):
            continue
        f += [""] * (6 - len(f))
        model, builtin, removable, conditional, skip, note = (x.strip() for x in f[:6])
        rows[model.lower()] = (builtin, removable, conditional, skip, note)


def parse_list(s):
    return [] if s in ("", "-") else [x.strip() for x in s.split(",") if x.strip()]


def parse_pairs(s):
    """Slot:bp=v[,v...];... -> [(slot, bp, [v...])]"""
    out = []
    if s in ("", "-"):
        return out
    for part in s.split(";"):
        part = part.strip()
        m = re.match(r"(\w+)\s*:\s*(\d+)\s*=\s*([\d,\s]+)$", part)
        if not m or m.group(1) not in SLOTS:
            problems.append(f"bad entry {part!r}")
            continue
        out.append((m.group(1), int(m.group(2)), [int(v) for v in m.group(3).split(",") if v.strip()]))
    return out


lua, models_by_wid, measure = [BEGIN, "-- (made from the reviewed contact sheets; edit the review TSVs, not this block)"], OrderedDict(), {}
for model, (builtin, removable, conditional, skip, note) in rows.items():
    if skip not in ("", "-"):
        continue
    wid = wid_of.get(model, "?")
    models_by_wid.setdefault(wid, []).append(model)
    sel = {}
    slots = {}
    for slot, bp, vals in parse_pairs(removable):
        slots.setdefault(slot, {})[bp] = vals[0]
        sel[bp] = vals[0]
    for slot, bp, vals in parse_pairs(conditional):
        if bp not in sel and 0 in vals:
            other = next((v for v in range(1, 64) if v not in vals), 0)
            sel[bp] = other
    measure[model] = sel
    if slots:
        inner = ", ".join(f"{s} = {{ {', '.join(f'[{bp}] = {v}' for bp, v in sorted(t.items()))} }}" for s, t in slots.items())
        lua.append(f'def("{model}", {{ slots = {{ {inner} }} }})')
    for slot in parse_list(builtin):
        if slot in SLOTS:
            lua.append(f'builtin("{model}", "{slot}")')
        else:
            problems.append(f"{model}: bad builtin slot {slot}")
    for slot, bp, vals in parse_pairs(conditional):
        lua.append(f'builtin("{model}", "{slot}", {{ [{bp}] = {{ {", ".join(f"[{v}] = true" for v in vals)} }} }})')
lua.append(END)

# sh_modelgear.lua: the block goes at the end of the file (after the local helpers it uses)
p = ADDON / "lua" / "advinv" / "sh_modelgear.lua"
s = p.read_text(encoding="utf-8")
if BEGIN in s:
    s = s[:s.index(BEGIN)] + s[s.index(END) + len(END):].lstrip("\n")
# (the helpers def/builtin are file locals: insert right after the last builtin( line of the file)
lines = s.rstrip("\n").split("\n")
last = max(i for i, l in enumerate(lines) if l.startswith("builtin("))
lines[last + 1:last + 1] = [""] + lua
p.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")

# tool lists
pw = ADDON / "tools" / "playermodels_workshop.txt"
have = {l.strip().lower() for l in pw.read_text(encoding="utf-8").splitlines()}
add = []
for wid, ms in models_by_wid.items():
    new = [m for m in ms if m not in have]
    if new:
        add.append(f"# {title.get(wid, '?')} (Workshop {wid})")
        add += new
if add:
    pw.write_text(pw.read_text(encoding="utf-8").rstrip("\n") + "\n" + "\n".join(add) + "\n", encoding="utf-8", newline="\n")
pb = ADDON / "tools" / "playermodel_bodygroups.txt"
haveb = {l.split()[0].lower() for l in pb.read_text(encoding="utf-8").splitlines() if l.strip() and not l.startswith("#")}
addb = [f"{m} " + " ".join(f"{bp}={v}" for bp, v in sorted(sel.items())) for m, sel in measure.items() if sel and m not in haveb]
if addb:
    pb.write_text(pb.read_text(encoding="utf-8").rstrip("\n") + "\n# Workshop playermodels (apply_review.py): no removable gear\n"
                  + "\n".join(addb) + "\n", encoding="utf-8", newline="\n")
summary = [f"{len(rows)} reviewed, {sum(len(v) for v in models_by_wid.values())} registered, "
           f"{sum(1 for r in rows.values() if r[3] not in ('', '-'))} skipped, {len(lua) - 3} rule lines, "
           f"{len([a for a in add if not a.startswith('#')])} new in playermodels_workshop.txt, {len(addb)} measuring lines"]
summary += problems
Path(SUMMARY).write_text("\n".join(summary) + "\n", encoding="utf-8")
print("\n".join(summary))
