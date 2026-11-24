-- Screenshot setup (server side of the local game): the player "Sam" with a full loadout.
--   python devkit/gmodclient.py srun advanced-inventory/tools/shots/sam.lua
local I = AdvInv
local C = I.ClassID
local p = Entity(1)
p:setRPName("Sam", true)
p:ConCommand("gmod_hints 0")
p:SetModel(SAM_MODEL or "models/player/group03/male_07.mdl")
p:SetHealth(100) p:SetArmor(0)
I.SetDefaults(p)
local function give(cont, list)
    for _, it in ipairs(list) do table.insert(I.Get(p, cont), it) end
    I.MarkDirty(p, cont)
end
I.Equip(p, { id = C.advinv_c_tank_crew_cvc_helmet, a = 0 })
I.Equip(p, { id = C.advinv_c_petruz_pmc_chalecopmc, a = 40 }, {
    { id = C.advinv_ammo_ar2, r = 30 }, { id = C.advinv_ammo_ar2, r = 30 }, { id = C.advinv_ammo_357, r = 6 },
    { id = I.GENERIC_AMMO, c = "Grenade", r = 1 }, { id = I.GENERIC_AMMO, c = "Grenade", r = 1 },
})
I.Equip(p, { id = C.advinv_c_fo76_backpacks_backpack_bomber, a = 0 }, {
    { id = I.GENERIC_ENTITY, c = "item_healthkit" }, { id = I.GENERIC_ENTITY, c = "item_healthkit" },
    { id = I.GENERIC_ENTITY, c = "item_battery" }, { id = C.advinv_ammo_buckshot, r = 20 },
    { id = C.advinv_hl2_shotgun, r = 6 }, { id = C.advinv_ammo_smg1, r = 45 },
})
I.Equip(p, { id = C.advinv_hl2_ar2, r = 30 })
I.Equip(p, { id = C.advinv_hl2_357, r = 6 })
give("Uniform", {
    { id = C.advinv_ammo_ar2, r = 20 }, { id = I.GENERIC_ENTITY, c = "item_healthvial" },
    { id = I.GENERIC_ENTITY, c = "item_healthvial" }, { id = C.advinv_ammo_pistol, r = 18 },
})
p:SelectWeapon("weapon_ar2")
return { ok = true, model = p:GetModel() }
