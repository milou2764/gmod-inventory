from pathlib import Path
import lupa
import sys
R = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "lua"
L = lupa.LuaRuntime()
chk = L.eval("function(s, n) local f, e = load(s, n) return f ~= nil, e end")
bad = 0
files = sorted(R.rglob("*.lua"))
for f in files:
    src = f.read_text(encoding="utf-8")
    # GMod Lua extras: != and continue are not standard Lua
    src2 = src.replace("!=", "~=")
    ok, err = chk(src2, str(f.relative_to(R)))
    if not ok:
        bad += 1
        print("ERR", f.relative_to(R), err)
print(len(files), "files,", bad, "with syntax errors")
