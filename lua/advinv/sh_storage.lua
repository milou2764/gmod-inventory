--[[
    Storage features (server: sv_storage.lua, client: cl_storage.lua).

    Crates (advinv_crate) have settings (context menu > "Storage settings", admins):
        permanent   saved with the map, contents included, put back at every start
        personal    each player has their own contents in it (kept per player or character)
        shared name crates with the same name share one contents, anywhere on the map
        capacity    its own capacity (0: AdvInv.Config.CrateLoad)
        loot table  refilled with random items from a loot table when empty, every N minutes
    Owners (the player who spawned or bought it) and admins can lock a crate, with an optional
    code: others can open it with the code.

    Banks (advinv_bank): every bank opens the same personal store of the player (capacity
    AdvInv.Config.BankLoad), kept between sessions.
    Loot spawns (advinv_loot_spawn, admin menu > Loot spawns): invisible points where a random item
    of a loot table appears, again some time after it was taken.

    Loot tables (shared), entries: item = registered item class / weapon = weapon class / entity = a
    whitelisted entity class; weight = chance against the others; count = { min, max } items.
        AdvInv.LootTables["my_table"] = { rolls = { 1, 3 }, items = { { item = "advinv_ammo_ar2", weight = 5 }, ... } }
--]]
local I = AdvInv
local C = I.Config

C.BankLoad = C.BankLoad or 300
C.LootSpawnEvery = C.LootSpawnEvery or 300 -- seconds before a taken loot spawn item comes back
C.LootRefillEvery = C.LootRefillEvery or 30 -- minutes before an emptied loot crate is refilled

I.LootTables = I.LootTables or {}
local defaults = {
    supplies = { rolls = { 1, 3 }, items = {
        { item = "advinv_ammo_pistol", weight = 6 }, { item = "advinv_ammo_smg1", weight = 5 },
        { item = "advinv_ammo_buckshot", weight = 4 }, { item = "advinv_ammo_ar2", weight = 3 },
        { item = "advinv_ammo_357", weight = 2 }, { entity = "item_healthvial", weight = 5 },
        { entity = "item_healthkit", weight = 3 }, { entity = "item_battery", weight = 3 },
    } },
    medical = { rolls = { 1, 2 }, items = {
        { entity = "item_healthvial", weight = 6 }, { entity = "item_healthkit", weight = 3 },
        { entity = "item_battery", weight = 2 },
    } },
    weapons = { rolls = { 1, 1 }, items = {
        { item = "advinv_hl2_pistol", weight = 6 }, { item = "advinv_hl2_smg1", weight = 4 },
        { item = "advinv_hl2_shotgun", weight = 3 }, { item = "advinv_hl2_357", weight = 2 },
        { item = "advinv_hl2_ar2", weight = 1 }, { weapon = "weapon_crowbar", weight = 4 },
        { weapon = "weapon_frag", weight = 2, count = { 1, 2 } },
    } },
}
for name, t in pairs(defaults) do
    if I.LootTables[name] == nil then I.LootTables[name] = t end
end

function I.LootTableNames()
    local names = table.GetKeys(I.LootTables)
    table.sort(names)
    return names
end

-- Owner of a storage: the player who spawned or bought it (or the prop protection's owner).
function I.StorageOwnerID(ent)
    local sid = ent:GetNWString("AdvInvOwner", "")
    if sid ~= "" then return sid end
    if ent.CPPIGetOwner then
        local o = ent:CPPIGetOwner()
        if IsValid(o) and o:IsPlayer() then return o:SteamID64() end
    end
end

function I.IsStorageOwner(ply, ent)
    return IsValid(ply) and ply:IsPlayer() and I.StorageOwnerID(ent) == ply:SteamID64()
end
