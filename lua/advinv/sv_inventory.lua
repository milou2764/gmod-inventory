--[[
    Saving, and the life of the inventory.

    Inventories are saved per owner: any string or number (a SteamID, a character ID...). Who
    owns the inventory a player carries is answered by the hook AdvInv_OwnerID(ply) -> owner (a
    character system answers it). Without an answer nothing is saved, and the inventory is reset at
    first spawn and after a death that left everything on the body (return false from
    AdvInv_ShouldAutoInit(ply) to keep it).

        AdvInv.Load(ply, owner)      puts the saved inventory on the player (equipped items given)
        AdvInv.Save(ply, owner)      saves what the player carries and wears
        AdvInv.Record(owner)         the saved data without a player (a table), or nil
        AdvInv.DeleteRecord(owner)   forgets it (a deleted character)
        AdvInv.CreateRecord(owner)   an empty inventory
        AdvInv.GiveWeapons(ply)      gives again the weapons of the equipped slots

    Data (JSON, table advinv_inventory): { v = 4, s = { slot = item }, c = { container = items } }
    with items packed as { class name, rounds, armour, carry mode, generic class, extra } (I.PackItems).
    Saves made before (v = 3) name items by their number then (AdvInv.LegacyID): read the same, written
    back with class names.
    Items whose definition is missing (an addon not loaded) are kept as they were saved and written
    back, so they come back with their addon. A record that can't be read is copied into the table
    advinv_inventory_bad before being replaced.
--]]
local I = AdvInv

function I.GetOwnerID(ply)
    return hook.Run("AdvInv_OwnerID", ply)
end

local function ownerKey(owner)
    if isnumber(owner) and math.abs(owner) >= 2 ^ 53 then
        I.Log.e("Inventory", "owner id " .. tostring(owner) .. " is too large for a number: return it as a string")
    end
    return tostring(owner)
end

-- Equipped weapons of the inventory are taken away (the slots are emptied after).
local function stripInventoryWeapons(ply)
    for _, cat in ipairs(I.WeaponCat) do
        local info = I.SlotInfo(ply, cat)
        if info.weaponClass and ply:HasWeapon(info.weaponClass) then ply:StripWeapon(info.weaponClass) end
    end
end

local function resetSlots(ply)
    -- (before: what is worn is still in its slot; an addon wearing it otherwise takes it off too)
    hook.Run("AdvInv_SlotsReset", ply)
    for _, cat in ipairs(I.WeaponCat) do
        ply:SetNWString(cat .. "Class", "")
        ply:SetNWInt(cat, 1)
        ply:SetNWInt(cat .. "Rounds", 0)
    end
    ply.AdvInvSlotExtra = {}
    ply.AdvInvJobSlot = {}
    for cat in pairs(I.GearCat) do ply:SetNWInt(cat .. "Armor", 0) end -- HelmetArmor, VestArmor...
    for _, cat in ipairs(I.CARRY_CATS) do ply:SetNWInt(cat .. "Carry", I.CARRY_INDEX.stowed) end
    for cat in pairs(I.GearCat) do ply:SetNW2Int(cat, 1) end
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do I.Set(ply, cont, {}) end
end

-- Empties the whole inventory (equipment and containers).
function I.Clear(ply)
    stripInventoryWeapons(ply)
    resetSlots(ply)
end

-- Starting inventory: nothing equipped, empty pockets.
function I.SetDefaults(ply)
    resetSlots(ply)
end

-- Frees a weapon slot without taking the weapon away (it left the player another way).
function I.ReleaseSlot(ply, cat)
    ply:SetNWInt(cat .. "Carry", I.CARRY_INDEX.stowed)
    ply:SetNWString(cat .. "Class", "")
    ply:SetNWInt(cat, 1)
    ply:SetNWInt(cat .. "Rounds", 0)
    if ply.AdvInvSlotExtra then ply.AdvInvSlotExtra[cat] = nil end
    if ply.AdvInvJobSlot then ply.AdvInvJobSlot[cat] = nil end
    I.MarkDirty(ply, "Uniform")
end

-- Takes away the job's weapons (advinv_darkrp_loadout_to_inventory): from their slots and the
-- pockets. Called when the player changes job and when he dies; the next loadout gives them again.
function I.RemoveJobItems(ply)
    for cat in pairs(ply.AdvInvJobSlot or {}) do
        if I.SlotRef(ply, cat) > 1 then I.TakeOff(ply, cat) end -- gone with its weapon
    end
    ply.AdvInvJobSlot = {}
    -- job grenades removed this tick (I.GrenadeDroppedAtDeath: a grenade primed at death is a job's
    -- one first, as when thrown, whichever death hook runs first)
    local gone = { t = CurTime() }
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        local items = I.Get(ply, cont)
        for k = #items, 1, -1 do
            local it = items[k]
            if it.j then
                if it.id == I.GENERIC_AMMO and isstring(it.c) then
                    local key = string.lower(it.c)
                    gone[key] = (gone[key] or 0) + (it.r or 1)
                end
                table.remove(items, k)
                I.MarkDirty(ply, cont)
            end
        end
    end
    ply.AdvInvJobAmmoGone = gone
end

local function slotOfClass(ply, class)
    for _, cat in ipairs(I.WeaponCat) do
        if I.SlotInfo(ply, cat).weaponClass == class then return cat end
    end
end
I.SlotOfWeaponClass = slotOfClass

-- Gives again the weapons of the equipped slots that the player lacks (after a StripWeapons,
-- a job change...), with the munitions and attachments kept in their slot.
function I.GiveWeapons(ply)
    for _, cat in ipairs(I.WeaponCat) do
        local info = I.SlotInfo(ply, cat)
        local wep = info.weaponClass and ply:GetWeapon(info.weaponClass)
        ply.AdvInvSlotWep = ply.AdvInvSlotWep or {}
        -- the slot's own weapon still held (a loadout without a strip: DarkRP's norespawn job change
        -- with keepPickedUp...): nothing to give back. Another one of that class is the loadout's
        -- copy (full magazine, no attachments): it gets the slot's.
        if info.weaponClass and not (IsValid(wep) and ply.AdvInvSlotWep[cat] == wep) then
            if not IsValid(wep) then wep = ply:Give(info.weaponClass, true) end -- the reserve is the boxes
            if IsValid(wep) and wep:GetMaxClip1() > 0 then wep:SetClip1(ply:GetNWInt(cat .. "Rounds")) end
            if I.EmptyUnderbarrel then I.EmptyUnderbarrel(wep) end -- (its round, if any, is in the boxes)
            local x = ply.AdvInvSlotExtra and ply.AdvInvSlotExtra[cat]
            if IsValid(wep) and x then I.ApplyWeaponExtra(wep, x) end
            ply.AdvInvSlotWep[cat] = IsValid(wep) and wep or nil
        end
    end
    I.MarkAllDirty(ply)
end

-- An inventory weapon taken away keeps its munitions and attachments in its slot, so giving it back
-- doesn't refill the magazine nor lose the scope (StripWeapon/StripWeapons drop each weapon before
-- deleting it). A weapon really dropped (still in the world a tick later, nobody holding it) leaves
-- its slot: it is the item now. (DarkRP's /drop: sv_darkrp.lua.)
hook.Add("PlayerDroppedWeapon", "AdvInv_KeepRounds", function(ply, wep)
    if not IsValid(wep) then return end
    local cat = slotOfClass(ply, wep:GetClass())
    if not cat then return end
    if wep:GetMaxClip1() > 0 then ply:SetNWInt(cat .. "Rounds", math.max(wep:Clip1(), 0)) end
    if I.UnloadUnderbarrel then I.UnloadUnderbarrel(ply, wep) end -- (an underbarrel launcher's rounds: boxes)
    ply.AdvInvSlotExtra = ply.AdvInvSlotExtra or {}
    ply.AdvInvSlotExtra[cat] = I.WeaponExtra(wep)
    local class, mode = wep:GetClass(), ply:GetNWInt(cat .. "Carry", 0)
    timer.Simple(0, function()
        if not (IsValid(ply) and IsValid(wep)) or wep.IsBeingDarkRPDropped or IsValid(wep:GetOwner()) then return end
        if wep.IsMarkedForDeletion and wep:IsMarkedForDeletion() then return end -- stripped, being deleted
        if slotOfClass(ply, class) ~= cat then return end
        wep.AdvInvExtra = ply.AdvInvSlotExtra and ply.AdvInvSlotExtra[cat]
        if I.CarryConfig(I.SlotRef(ply, cat)) then wep.AdvInvCarryMode = mode end
        I.ReleaseSlot(ply, cat)
    end)
end)

-- Loadout (respawn kept by a character system, DarkRP job change, unarrest): the slot weapons
-- are given back. Never to an arrested player.
hook.Add("PlayerLoadout", "AdvInv_GiveWeapons", function(ply)
    timer.Simple(0, function()
        if not (IsValid(ply) and ply:Alive()) then return end
        if ply.isArrested and ply:isArrested() then return end
        I.GiveWeapons(ply)
    end)
end)

-- Reset at the first spawn, and after a death that left everything on the body. Any other spawn
-- (DarkRP's arrest, an admin's respawn, a death that left things on the player) keeps what he has.
hook.Add("PlayerSpawn", "AdvInv_AutoInit", function(ply)
    local reset = ply.AdvInvResetNextSpawn or not ply.AdvInvSpawned
    ply.AdvInvSpawned = true
    ply.AdvInvResetNextSpawn = nil
    ply.AdvInvKeepNextSpawn = nil
    if not reset then
        I.MarkAllDirty(ply) -- the reserve comes back from the boxes
        return
    end
    if hook.Run("AdvInv_ShouldAutoInit", ply) == false then return end
    I.SetDefaults(ply)
end)

---------------------------------------------------------------- packed items

-- Saved as { class name, rounds, armour, carry mode, generic class, extra }: the class name is the
-- item's ID (session numbers are never saved).
local function packItem(it)
    local id = I.IDClass[it.id] or it.id
    if it.x then return { id, it.r or 0, it.a or 0, it.m or 0, it.c or "", it.x } end
    if it.c then return { id, it.r or 0, it.a or 0, it.m or 0, it.c } end
    return { id, it.r or 0, it.a or 0, it.m }
end

-- Session number of a saved item: its class name, or the number older saves used (AdvInv.LegacyID).
local legacyClass
hook.Add("AdvInv_ItemsInitialized", "AdvInv_LegacyClass", function() legacyClass = nil end)
local function savedID(v)
    if isstring(v) then return I.ClassID[v], v end
    local n = tonumber(v)
    if not n or n <= 1 then return end
    if not legacyClass then
        legacyClass = {}
        for class, old in pairs(I.LegacyID) do legacyClass[old] = class end
    end
    local class = legacyClass[n]
    return class and I.ClassID[class], class or true
end
I.SavedID = savedID

-- -> item, or nil and true when the entry is a real item whose definition is missing now
local function unpackItem(v)
    if not istable(v) then return end
    local id, known = savedID(v[1])
    if not known then return end -- empty
    if not id then return nil, true end -- an item of an addon that is missing now
    local c = I.IsGeneric(id) and isstring(v[5]) and v[5] ~= "" and v[5] or nil
    if id == I.GENERIC_WEAPON and c and I.GrenadeAmmo(c) and game.GetAmmoID(I.GrenadeAmmo(c)) ~= -1 then
        return { id = I.GENERIC_AMMO, c = I.GrenadeAmmo(c), r = 1 } -- saved as a weapon before: now an item
    end
    if I.IsGeneric(id) and not (c and I.DefTable(id, c)) then return nil, c ~= nil end -- unknown class now
    local m = tonumber(v[4])
    return { id = id, r = tonumber(v[2]) or 0, a = tonumber(v[3]) or 0,
        m = (m and I.CARRY_MODES[m]) and m or nil, c = c, x = isstring(v[6]) and v[6] or nil }
end

function I.PackItems(items)
    local out = {}
    for k, it in ipairs(items or {}) do out[k] = packItem(it) end
    return out
end

-- unknown: a list that receives the entries whose definition is missing (kept as saved).
function I.UnpackItems(list, unknown)
    local out = {}
    for _, v in ipairs(istable(list) and list or {}) do
        local it, missing = unpackItem(v)
        if it then
            out[#out + 1] = it
        elseif missing and unknown then
            unknown[#unknown + 1] = v
        end
    end
    return out
end

---------------------------------------------------------------- save / load

function I.Serialize(ply)
    local data = { v = 4, s = {}, c = {} }
    local extra = ply.AdvInvSlotExtra or {}
    local job = ply.AdvInvJobSlot or {}
    local under = {} -- rounds in underbarrel launchers: saved as boxes (the weapon comes back empty)
    for _, cat in ipairs(I.WeaponCat) do
        local id, c = I.SlotRef(ply, cat)
        if id > 1 and not job[cat] then -- a job's weapon is not saved
            local info = I.Info(id, c)
            local wep = info.weaponClass and ply:GetWeapon(info.weaponClass)
            -- the weapon's attachments as they are (none: nil), else the ones kept in the slot
            local x
            if IsValid(wep) then x = I.WeaponExtra(wep) else x = extra[cat] end
            data.s[cat] = packItem({
                id = id, c = c,
                r = IsValid(wep) and math.max(wep:Clip1(), 0) or ply:GetNWInt(cat .. "Rounds"),
                m = I.CarryConfig(id, c) and ply:GetNWInt(cat .. "Carry") or nil,
                x = x,
            })
            local ammo2, n2 -- (not "f and f(wep)": that keeps the first value only)
            if I.UnderbarrelRounds then ammo2, n2 = I.UnderbarrelRounds(wep) end
            if ammo2 then under[#under + 1] = { ammo2, n2 } end
        end
    end
    for cat in pairs(I.GearCat) do
        local id = ply:GetNW2Int(cat)
        if id > 1 then data.s[cat] = packItem({ id = id, a = ply:GetNWInt(cat .. "Armor"), x = extra[cat] }) end
    end
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        local mine = {}
        for _, it in ipairs(I.Get(ply, cont)) do
            if not it.j then mine[#mine + 1] = it end
        end
        data.c[cont] = I.PackItems(mine)
    end
    for _, u in ipairs(under) do
        local id, c = I.AmmoBoxFor(u[1])
        local size = math.max(I.Info(id, c).boxRounds or 1, 1)
        local n = u[2]
        while n > 0 do
            local take = math.min(size, n)
            table.insert(data.c.Uniform, packItem({ id = id, c = c, r = take }))
            n = n - take
        end
    end
    -- items of addons that are missing now: written back as they were, never lost
    local uk = ply.AdvInvUnknown
    if uk then
        local function keep(cont, v)
            data.c[cont] = data.c[cont] or {}
            table.insert(data.c[cont], v)
        end
        for cat, v in pairs(uk.s) do
            local held = uk.held and uk.held[cat] or {} -- what an unknown vest or backpack holds
            -- its slot holds another item now: into the pockets, with what it held
            local into = data.s[cat] == nil and cat or "Uniform"
            if into == cat then data.s[cat] = v else keep("Uniform", v) end
            for _, e in ipairs(held) do keep(into, e) end
        end
        for cont, list in pairs(uk.c) do
            -- in a vest or a backpack no longer worn: into the pockets
            local into = (cont == "Uniform" or data.s[cont] ~= nil) and cont or "Uniform"
            for _, v in ipairs(list) do keep(into, v) end
        end
    end
    return util.TableToJSON(data)
end

-- -> data table, or nil (and "corrupt" with the raw text when the row can't be read)
function I.Record(owner)
    if owner == nil then return end
    local v = sql.QueryValue("SELECT Data FROM " .. I.TABLE .. " WHERE OwnerID = " .. SQLStr(ownerKey(owner)))
    if v == nil or v == false then return end
    local data = util.JSONToTable(v)
    if istable(data) then return data end
    return nil, "corrupt", v
end

-- Item in a saved slot (for previews of characters...): { id, ... } or nil.
function I.RecordSlot(record, cat)
    return record and record.s and (unpackItem(record.s[cat])) or nil
end

function I.Save(ply, owner)
    if owner == nil then return end
    return I.SQLRequest("REPLACE INTO " .. I.TABLE .. " (OwnerID, Data) VALUES (" ..
        SQLStr(ownerKey(owner)) .. ", " .. SQLStr(I.Serialize(ply)) .. ")")
end

function I.CreateRecord(owner)
    if owner == nil then return end
    return I.SQLRequest("REPLACE INTO " .. I.TABLE .. " (OwnerID, Data) VALUES (" ..
        SQLStr(ownerKey(owner)) .. ", " .. SQLStr(util.TableToJSON({ v = 4, s = {}, c = {} })) .. ")")
end

function I.DeleteRecord(owner)
    if owner == nil then return end
    return I.SQLRequest("DELETE FROM " .. I.TABLE .. " WHERE OwnerID = " .. SQLStr(ownerKey(owner)))
end

-- Order of equipping: the uniform first (pockets), then the gear, then the weapons.
local GEAR_ORDER = { "Uniform", "Vest", "Rucksack", "Helmet", "Gasmask", "NVGs", "Radio" }

function I.Load(ply, owner)
    I.Clear(ply)
    local uk = { s = {}, c = {}, held = {} }
    ply.AdvInvUnknown = uk
    local data, why, raw = I.Record(owner)
    if why == "corrupt" then
        sql.Query("CREATE TABLE IF NOT EXISTS advinv_inventory_bad (OwnerID TEXT, Data TEXT, Time INTEGER)")
        sql.Query("INSERT INTO advinv_inventory_bad (OwnerID, Data, Time) VALUES (" .. SQLStr(ownerKey(owner)) .. ", " ..
            SQLStr(raw) .. ", " .. os.time() .. ")")
        I.Log.e("Inventory", "the saved inventory of " .. ownerKey(owner) .. " can't be read: copied into advinv_inventory_bad")
    end
    if data and istable(data.s) then
        local conts = istable(data.c) and data.c or {}
        local pockets = {} -- items that can't be equipped any more: into the pockets, not lost
        local function slotItem(cat)
            local it, missing = unpackItem(data.s[cat])
            if not it and missing then uk.s[cat] = data.s[cat] end
            return it
        end
        local function contents(cont)
            uk.c[cont] = uk.c[cont] or {}
            return I.UnpackItems(conts[cont], uk.c[cont])
        end
        for _, cat in ipairs(GEAR_ORDER) do
            local it = I.GearCat[cat] and slotItem(cat)
            if it then
                local inside = (cat == "Vest" or cat == "Rucksack") and contents(cat) or nil
                if not I.Equip(ply, it, inside) then
                    pockets[#pockets + 1] = it
                    for _, v in ipairs(inside or {}) do pockets[#pockets + 1] = v end
                end
            elseif uk.s[cat] and (cat == "Vest" or cat == "Rucksack") and istable(conts[cat]) then
                uk.held[cat] = conts[cat] -- a vest or a backpack of a missing addon: what it holds, as saved
            end
        end
        for _, cat in ipairs(I.WeaponCat) do
            local it = slotItem(cat)
            if it and not I.Equip(ply, it) then pockets[#pockets + 1] = it end
        end
        I.Set(ply, "Uniform", contents("Uniform"))
        -- what couldn't be equipped goes where it fits; else in the pockets even over their load
        -- (still seen and movable), never past the 255 items a container can show: then the ground
        for _, it in ipairs(pockets) do
            if not I.Store(ply, it) then
                local list = I.Get(ply, "Uniform")
                if #list < I.MAX_ITEMS then list[#list + 1] = it else I.SpawnItem(it, I.DropPos(ply)) end
            end
        end
        I.MarkDirty(ply, "Uniform")
        if #pockets > 0 then I.Log.e("Inventory", #pockets .. " saved items of " .. ownerKey(owner) .. " couldn't be equipped: in the pockets") end
        I.ValidateCarry(ply, false)
    end
    net.Start("advinv_gear_playerspawn")
    net.WriteEntity(ply)
    net.Broadcast()
end
