"""WriteItems / ReadItems round trip (real sh_containers code, stub net buffer)."""
import re, sys
from pathlib import Path
import lupa
SRC = (Path(__file__).resolve().parents[2] / "lua" / "advinv" / "sh_containers.lua").read_text(encoding="utf-8")
block = SRC[SRC.index("I.NET_ID_BITS"):SRC.index("-- Actions demandées")] + SRC[SRC.index("-- Identical items"):SRC.index("---------------------------------------------------------------- contenu vu par le client")]
L = lupa.LuaRuntime(unpack_returned_tuples=True)
L.execute("""
math.Clamp = function(v, a, b) return math.min(math.max(v, a), b) end
istable = function(v) return type(v) == "table" end
isnumber = function(v) return type(v) == "number" end
I = {}
function I.IsGeneric(id) return id == 100 or id == 103 or id == 125 end
BUF, POS = {}, 0
net = {
  WriteUInt = function(v, bits) assert(v >= 0 and v < 2 ^ bits, "overflow " .. v .. " in " .. bits) BUF[#BUF + 1] = v end,
  WriteString = function(s) BUF[#BUF + 1] = s end,
  WriteBool = function(b) BUF[#BUF + 1] = b end,
  ReadBool = function() POS = POS + 1 return BUF[POS] end,
  ReadUInt = function() POS = POS + 1 return BUF[POS] end,
  ReadString = function() POS = POS + 1 return BUF[POS] end,
}
""")
L.execute(block)
res = L.eval("""function()
  local items = { { id = 112, r = 17, a = 0, m = 2 }, { id = 100, r = 30, c = "weapon_ak472", m = 1 },
                  { id = 103, c = "item_healthkit" }, { id = 120, r = 20 }, { id = 112, r = 5, x = "scope=acog" }, { id = 125, c = "SniperRound", r = 12 } }
  I.WriteItems(items)
  local back = I.ReadItems()
  local out = {}
  for k, it in ipairs(back) do out[k] = it.id .. "/" .. it.r .. "/" .. it.a .. "/" .. tostring(it.m) .. "/" .. tostring(it.c) .. "/" .. tostring(it.x) end
  return table.concat(out, " ; "), I.StackKey(back[2]) ~= I.StackKey({ id = 100, r = 30, c = "weapon_crowbar", m = 1 })
end""")()
print(res)
