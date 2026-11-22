"""Every language: same keys as English (missing ones listed), same %s count per key."""
import re, sys
from pathlib import Path
import lupa
D = Path(__file__).resolve().parents[2] / "lua" / "advinv"
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("""
FCVAR_ARCHIVE, FCVAR_REPLICATED = 1, 2
function CreateConVar() return { GetString = function() return "en" end } end
MRP = { Inventory = {} }
""")
L.execute((D / "sh_lang.lua").read_text(encoding="utf-8"))
L.execute((D / "sh_lang_more.lua").read_text(encoding="utf-8"))
Lang = L.eval("AdvInv.Lang")
en = dict(Lang["en"].items())
for code in ("fr", "de", "es", "ru"):
    t = dict(Lang[code].items())
    missing = sorted(set(en) - set(t))
    extra = sorted(set(t) - set(en))
    bad = [k for k in t if k in en and len(re.findall(r"%[sd]", t[k])) != len(re.findall(r"%[sd]", en[k]))]
    pct = [k for k in t if k in en and ("%%" in en[k]) != ("%%" in t[k])]
    print(code, len(t), "keys | missing:", missing[:30], "| extra:", extra, "| placeholder mismatch:", bad, pct)
