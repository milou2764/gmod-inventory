-- Item IDs are class names (sh_config.lua, sv_inventory.lua): saves name items by class, saves made
-- before (numbers, v = 3) still load, an entry of a missing addon is kept as saved. Needs a bot.
local I, C = AdvInv, AdvInv.ClassID
local b = player.GetBots()[1]
if not IsValid(b) then return { skipped = "no bot" } end
if not b:Alive() then b:Spawn() end
local out = {}
local OWNER = "advinv_test_ids"

-- every registered item has a session number, both ways
local missing = 0
for class in pairs(I.Items) do
    local id = C[class]
    if not (id and I.IDClass[id] == class) then missing = missing + 1 end
end
out.everyItemNumbered = missing == 0                                -- true
out.legacyKept = C.advinv_barney_helmet == 104 and C.advinv_any_weapon == 100 -- true (older numbers stay)

-- a save names items by class
I.SetDefaults(b)
I.Equip(b, { id = C.advinv_barney_helmet, a = 77 })
I.Set(b, "Uniform", { { id = C.advinv_ammo_pistol, r = 12 }, { id = I.GENERIC_WEAPON, c = "weapon_crowbar" } })
I.Save(b, OWNER)
local rec = I.Record(OWNER)
out.version = rec.v                                                 -- 4
out.slotByClass = rec.s.Helmet and rec.s.Helmet[1]                  -- "advinv_barney_helmet"
out.itemsByClass = rec.c.Uniform and rec.c.Uniform[1][1] .. "," .. rec.c.Uniform[2][1] -- "advinv_ammo_pistol,advinv_any_weapon"
out.genericClassKept = rec.c.Uniform and rec.c.Uniform[2][5]        -- "weapon_crowbar"

-- loading it back
I.Load(b, OWNER)
out.loadedHelmet = b:GetNW2Int("Helmet") == C.advinv_barney_helmet  -- true
out.loadedArmor = b:GetNWInt("HelmetArmor")                         -- 77
local u = I.Get(b, "Uniform")
out.loadedPockets = #u == 2 and u[1].id == C.advinv_ammo_pistol and u[1].r == 12 and u[2].c == "weapon_crowbar" -- true

-- a save made before class names (numbers), with an item of a missing addon (by number and by class)
sql.Query("REPLACE INTO " .. I.TABLE .. " (OwnerID, Data) VALUES (" .. SQLStr(OWNER) .. ", " .. SQLStr(util.TableToJSON({
    v = 3, s = { Helmet = { 104, 0, 55 } },
    c = { Uniform = { { 116, 30, 0 }, { 1999, 0, 0 }, { "advinv_somebody_missing_item", 0, 0 } } },
})) .. ")")
I.Load(b, OWNER)
out.oldHelmet = b:GetNW2Int("Helmet") == C.advinv_barney_helmet     -- true
out.oldArmor = b:GetNWInt("HelmetArmor")                            -- 55
u = I.Get(b, "Uniform")
out.oldPockets = #u >= 1 and u[1].id == C.advinv_ammo_pistol and u[1].r == 30 -- true
I.Save(b, OWNER)
rec = I.Record(OWNER)
local kept = {}
for _, v in ipairs(rec.c.Uniform or {}) do kept[#kept + 1] = tostring(v[1]) end
out.rewritten = table.concat(kept, ",")                             -- "advinv_ammo_pistol,1999,advinv_somebody_missing_item" (1999 kept only if no compatible addon has it)
out.slotRewritten = rec.s.Helmet and rec.s.Helmet[1]                -- "advinv_barney_helmet"

I.DeleteRecord(OWNER)
I.SetDefaults(b)
return out
