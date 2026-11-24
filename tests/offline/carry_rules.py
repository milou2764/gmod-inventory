"""Offline checks of the carry modes: syntax of every touched Lua file, then the real sh_carry.lua /
sv_carry.lua rules (lupa) with stub players, gear and items."""
import sys
from pathlib import Path

import lupa

ROOT = Path(__file__).resolve().parents[2] / "lua"
D = ROOT / "advinv"
FILES = ["sh_carry.lua", "sv_carry.lua", "cl_carry.lua", "cl_carry_tools.lua", "cl_carry_data.lua",
         "cl_weapons.lua", "sh_lang.lua", "sv_inventory.lua", "sh_containers.lua"]

L = lupa.LuaRuntime(unpack_returned_tuples=True)
bad = 0
for f in FILES:
    src = (D / f).read_text(encoding="utf-8")
    fn, err = L.eval("function(s, n) local f, e = load(s, n) return f ~= nil, e end")(src, f)
    if not fn:
        print("SYNTAX", f, err)
        bad += 1
for f in ["advinv/sv_containers.lua", "advinv/cl_inventory.lua", "entities/advinv_base_rucksack/shared.lua",
          "entities/advinv_base_vest/shared.lua", "autorun/advinv_loader.lua"]:
    src = (ROOT / f).read_text(encoding="utf-8").replace("!=", "~=").replace("continue", "goto continue")
    fn, err = L.eval("function(s, n) local f, e = load(s, n) return f ~= nil, e end")(src, f)
    if not fn and "goto" not in str(err):
        print("SYNTAX?", f, err)
print("syntax:", "ok" if not bad else f"{bad} files with errors")

L.execute(r"""
FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY = 1, 2, 4
CVARS = { advinv_language = "en", advinv_carry_refuse_gear = "0" }
function CreateConVar(name, def)
    CVARS[name] = CVARS[name] or def
    return { GetString = function() return CVARS[name] end, GetBool = function() return CVARS[name] == "1" end }
end
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function table.HasValue(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
function table.Copy(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
function IsValid(x) return x ~= nil end
HOOKS = {}
hook = { Add = function() end, Run = function(name, ...) local f = HOOKS[name] if f then return f(...) end end }
timer = { Simple = function(_, f) f() end }
AdvInv = {}
AdvInv.GearCat = { NVGs = true, Helmet = true, Gasmask = true, Rucksack = true, Vest = true, Radio = true, Uniform = true }
ENTS = {
    [10] = { WeaponClass = "weapon_ar2", PrintName = "AR2", AdvInvCategory = "PrimaryWep" },
    [11] = { WeaponClass = "weapon_rpg", PrintName = "RPG", AdvInvCategory = "RocketLauncher" },
    [12] = { WeaponClass = "weapon_pistol", PrintName = "Pistol", AdvInvCategory = "SecondaryWep" },
    [20] = { PrintName = "Backpack", AdvInvCategory = "Rucksack", BlocksCarryZones = { back = true } }, -- (as advinv_base_rucksack)
    [21] = { PrintName = "Vest", AdvInvCategory = "Vest", BlocksCarryZones = { front = false } },
    [22] = { PrintName = "Chest rig", AdvInvCategory = "Vest", BlocksCarryZones = { front = true } },
}
function AdvInv.EntityTable(id) return ENTS[id] end
local I = AdvInv
function I.Info(id) local t = ENTS[id] return { name = t and t.PrintName or "?" } end
function I.IsGeneric() return false end
function I.DefTable(id) return ENTS[id] end
function I.SlotRef(ent, cat) if AdvInv.GearCat[cat] then return ent:GetNW2Int(cat) end return ent:GetNWInt(cat) end
function I.SlotInfo(ent, cat) return I.Info(I.SlotRef(ent, cat)) end
TOLD = {}
function I.Tell(ply, text) TOLD[#TOLD + 1] = text end
CHANGED = {}
HOOKS.OnCarryModeChanged = function(ply, item, mode, old) CHANGED[#CHANGED + 1] = item.cat .. ":" .. old .. ">" .. mode end
function newPly()
    local p = { nw = {}, nw2 = {} }
    function p:GetNWInt(k, d) local v = self.nw[k] if v == nil then return d or 0 end return v end
    function p:SetNWInt(k, v) self.nw[k] = v end
    function p:GetNW2Int(k, d) local v = self.nw2[k] if v == nil then return d or 0 end return v end
    function p:SetNW2Int(k, v) self.nw2[k] = v end
    return p
end
""")
for f in ("sh_lang.lua", "sh_carry.lua", "sv_carry.lua"):
    L.execute((D / f).read_text(encoding="utf-8"))

ok = 0
fail = 0


def check(name, got, want):
    global ok, fail
    if got == want:
        ok += 1
    else:
        fail += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


run = L.eval
run("function() P = newPly() end")()
I = "AdvInv"
mode = lambda cat: run(f'function() return {I}.CarryMode(P, "{cat}") end')()
# the real flows: weapon equip = check, then set + validate; gear = check, then set + validate
def equip(cat, id, m="nil"):
    r = run(f'''function() local okc, why = {I}.CarryEquipCheck(P, "{cat}", {{ id = {id}, m = {m} }})
        if not okc then return okc, why end
        P:SetNWInt("{cat}", {id}) {I}.CarryOnEquip(P, "{cat}", {{ id = {id}, m = {m} }}) {I}.ValidateCarry(P, true, "{cat}") return true end''')()
    return r
def gear(cat, id):
    return run(f'''function() if {id} > 1 then local okc, why = {I}.CarryGearCheck(P, {id}, "{cat}") if not okc then return okc, why end end
        P:SetNW2Int("{cat}", {id}) {I}.ValidateCarry(P, true) return true end''')()
req = lambda cat, m: run(f'function() return {I}.RequestCarryMode(P, "{cat}", "{m}") end')()
told = lambda: run("function() local t = TOLD TOLD = {} return table.concat(t, ' / ') end")()
hookset = lambda body: run(f"function() HOOKS.CanChangeCarryMode = {body} end")()

check("nothing equipped", mode("PrimaryWep"), "stowed")
check("equip AR2", equip("PrimaryWep", 10), True)
check("AR2 default", mode("PrimaryWep"), "sling_up")
told()
# the RPG has only sling arms: the AR2 makes room on the shoulder, on the back (back carry)
check("equip RPG", equip("RocketLauncher", 11), True)
check("RPG default", mode("RocketLauncher"), "sling_up")
check("AR2 made room", mode("PrimaryWep"), "sling_down")
check("told", told(), "Carry mode changed - AR2: Back carry")
check("one zone each", req("PrimaryWep", "sling_up"), (False, "Shoulder occupied by RPG"))
check("cross-body removed", req("PrimaryWep", "cross_body"), (False, "Not possible with this weapon"))
check("old back carry removed", req("PrimaryWep", "back_carry"), (False, "Not possible with this weapon"))
check("stowed not possible", req("PrimaryWep", "stowed"), (False, "Not possible with this weapon"))
check("rpg not front", req("RocketLauncher", "front_hang"), (False, "Not possible with this weapon"))
check("forged mode", req("RocketLauncher", "flying"), False)
check("forged slot", req("SecondaryWep", "sling_up"), False)
told()
# backpack: only sling arms is left on the back; the AR2 (back carry) goes to the front
check("backpack accepted", gear("Rucksack", 20), True)
check("RPG stays slung", mode("RocketLauncher"), "sling_up")
check("AR2 to the front", mode("PrimaryWep"), "front_hang")
check("told one", told(), "Carry mode changed - AR2: Front carry / Hang")
check("back carry blocked by the backpack", req("PrimaryWep", "sling_down"), (False, "Back occupied by backpack"))
check("front ok", req("PrimaryWep", "front_hang"), True)
gear("Rucksack", 1)
check("modes kept after backpack off", (mode("RocketLauncher"), mode("PrimaryWep")), ("sling_up", "front_hang"))
# chest rig takes the front: the AR2 moves, the RPG keeps its place
gear("Vest", 21)
check("vest keeps front", mode("PrimaryWep"), "front_hang")
told()
gear("Vest", 22)
check("chest rig: AR2 moves, RPG stays", (mode("PrimaryWep"), mode("RocketLauncher")), ("sling_down", "sling_up"))
check("told one", told(), "Carry mode changed - AR2: Back carry")
gear("Vest", 1)
# refuse option: a backpack over an AR2 carried on the back
run('function() CVARS.advinv_carry_refuse_gear = "1" end')()
check("refuse backpack (AR2 on the back)", gear("Rucksack", 20), (False, "Change how your AR2 is carried first (Back carry)."))
run('function() CVARS.advinv_carry_refuse_gear = "0" end')()
# no place left: the AR2 may only be carried on the back (hook) -> a backpack leaves it nowhere
hookset('function(ply, item, m) if item.cat == "PrimaryWep" and m ~= "sling_down" then return false end end')
check("backpack refused: nowhere for the AR2", gear("Rucksack", 20), (False, "Your AR2 would have no place left to be carried"))
check("nothing moved", (mode("PrimaryWep"), mode("RocketLauncher")), ("sling_down", "sling_up"))
hookset("nil")
# weapon equip refused when no place is left for it
run('function() P:SetNWInt("PrimaryWep", 1) P:SetNWInt("PrimaryWepCarry", 6) end')()
gear("Rucksack", 20)
check("RPG on sling with backpack", mode("RocketLauncher"), "sling_up")
hookset('function(ply, item, m) if m ~= "sling_up" then return false end end')
check("AR2 refused", equip("PrimaryWep", 10), (False, "No place left on you to carry AR2"))
check("slot still empty", run('function() return P:GetNWInt("PrimaryWep") end')(), 1)
hookset("nil")
gear("Rucksack", 1)
# saved modes
check("equip AR2 saved on the back", equip("PrimaryWep", 10, 2), True)
check("saved back carry kept", mode("PrimaryWep"), "sling_down")
run('function() P:SetNWInt("PrimaryWep", 1) end')()
check("equip AR2 saved slung (RPG on shoulder)", equip("PrimaryWep", 10, 1), True)
check("saved mode taken -> next possible", mode("PrimaryWep"), "sling_down")
run('function() P:SetNWInt("PrimaryWep", 1) end')()
check("saved stowed from an old save -> default", equip("PrimaryWep", 10, 6), True)
check("old stowed -> back carry (sling taken)", mode("PrimaryWep"), "sling_down")
run('function() P:SetNWInt("PrimaryWep", 1) end')()
check("saved cross-body (removed)", equip("PrimaryWep", 10, 3), True)
check("removed cross-body -> back carry (sling taken)", mode("PrimaryWep"), "sling_down")
run('function() P:SetNWInt("PrimaryWep", 1) end')()
check("saved old back carry (removed)", equip("PrimaryWep", 10, 4), True)
check("removed old back carry -> back carry (sling taken)", mode("PrimaryWep"), "sling_down")
check("hooks told of changes", len(run("function() return CHANGED end")()) > 0, True)
# a weapon carried on the back goes to the front when a backpack goes on (sling arms stays possible)
run('function() P:SetNWInt("RocketLauncher", 1) P:SetNWInt("RocketLauncherCarry", 6) end')()
told()
check("backpack over a weapon on the back", gear("Rucksack", 20), True)
check("weapon to the front", mode("PrimaryWep"), "front_hang")
check("told", told(), "Carry mode changed - AR2: Front carry / Hang")
check("sling arms with a backpack", req("PrimaryWep", "sling_up"), True)
gear("Rucksack", 1)
check("back carry without a backpack", req("PrimaryWep", "sling_down"), True)
# french strings
run('function() CVARS.advinv_language = "fr" end')()
told()
gear("Rucksack", 20)
check("fr: weapon on the back moved to the front", mode("PrimaryWep"), "front_hang")
check("fr reason", req("PrimaryWep", "sling_down"), (False, "Impossible avec un sac à dos équipé"))
check("fr refused", req("PrimaryWep", "stowed"), (False, "Impossible avec cette arme"))
print(f"carry rules: {ok} ok, {fail} failed")
sys.exit(1 if fail or bad else 0)
