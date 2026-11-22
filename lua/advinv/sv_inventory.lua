--[[
    Saving, and the life of the inventory.

    Inventories are saved per owner: any string or number (a SteamID, a character ID...). Who
    owns the inventory a player carries is answered by the hook AdvInv_OwnerID(ply) -> owner (a
    character system answers it). Without an answer nothing is saved, and the inventory is reset at
    every spawn (return false from AdvInv_ShouldAutoInit(ply) to keep it).

        AdvInv.Load(ply, owner)      puts the saved inventory on the player (equipped items given)
        AdvInv.Save(ply, owner)      saves what the player carries and wears
        AdvInv.Record(owner)         the saved data without a player (a table), or nil
        AdvInv.DeleteRecord(owner)   forgets it (a deleted character)
        AdvInv.CreateRecord(owner)   an empty inventory
        AdvInv.GiveWeapons(ply)      gives again the weapons of the equipped slots

    Data (JSON, table advinv_inventory): { v = 3, s = { slot = item }, c = { container = items } }
    with items packed as { id, rounds, armour, carry mode, class, extra } (I.PackItems).
--]]
local I = AdvInv

function I.GetOwnerID(ply)
    return hook.Run("AdvInv_OwnerID", ply)
end

-- Equipped weapons of the inventory are taken away (the slots are emptied after).
local function stripInventoryWeapons(ply)
    for _, cat in ipairs(I.WeaponCat) do
        local info = I.SlotInfo(ply, cat)
        if info.weaponClass and ply:HasWeapon(info.weaponClass) then ply:StripWeapon(info.weaponClass) end
    end
end

local function resetSlots(ply)
    for _, cat in ipairs(I.WeaponCat) do
        ply:SetNWString(cat .. "Class", "")
        ply:SetNWInt(cat, 1)
        ply:SetNWInt(cat .. "Rounds", 0)
    end
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

-- Gives again the weapons of the equipped slots that the player lacks (after a StripWeapons,
-- a respawn that keeps the inventory...), with the munitions saved in their slot.
function I.GiveWeapons(ply)
    for _, cat in ipairs(I.WeaponCat) do
        local info = I.SlotInfo(ply, cat)
        if info.weaponClass and not ply:HasWeapon(info.weaponClass) then
            local wep = ply:Give(info.weaponClass, (info.clipSize or 0) <= 0)
            if IsValid(wep) and wep:GetMaxClip1() > 0 then wep:SetClip1(ply:GetNWInt(cat .. "Rounds")) end
        end
    end
    I.MarkAllDirty(ply)
end

-- An inventory weapon taken away keeps its munitions in its slot, so giving it back does not
-- refill the magazine (StripWeapon/StripWeapons drop each weapon before deleting it).
hook.Add("PlayerDroppedWeapon", "AdvInv_KeepRounds", function(ply, wep)
    if not (IsValid(wep) and wep:GetMaxClip1() > 0) then return end
    for _, cat in ipairs(I.WeaponCat) do
        if I.SlotInfo(ply, cat).weaponClass == wep:GetClass() then
            ply:SetNWInt(cat .. "Rounds", math.max(wep:Clip1(), 0))
        end
    end
end)

hook.Add("PlayerSpawn", "AdvInv_AutoInit", function(ply)
    if hook.Run("AdvInv_ShouldAutoInit", ply) == false then return end
    I.SetDefaults(ply)
end)

---------------------------------------------------------------- packed items

local function packItem(it)
    if it.x then return { it.id, it.r or 0, it.a or 0, it.m or 0, it.c or "", it.x } end
    if it.c then return { it.id, it.r or 0, it.a or 0, it.m or 0, it.c } end
    return { it.id, it.r or 0, it.a or 0, it.m }
end

local function unpackItem(v)
    if not istable(v) then return end
    local id = tonumber(v[1])
    if not id or id <= 1 or not I.IDClass[id] then return end
    local c = I.IsGeneric(id) and isstring(v[5]) and v[5] ~= "" and v[5] or nil
    if I.IsGeneric(id) and not (c and I.DefTable(id, c)) then return end -- unknown class now
    local m = tonumber(v[4])
    return { id = id, r = tonumber(v[2]) or 0, a = tonumber(v[3]) or 0,
        m = (m and I.CARRY_MODES[m]) and m or nil, c = c, x = isstring(v[6]) and v[6] or nil }
end

function I.PackItems(items)
    local out = {}
    for k, it in ipairs(items or {}) do out[k] = packItem(it) end
    return out
end

function I.UnpackItems(list)
    local out = {}
    for _, v in ipairs(list or {}) do out[#out + 1] = unpackItem(v) end
    return out
end

---------------------------------------------------------------- save / load

function I.Serialize(ply)
    local data = { v = 3, s = {}, c = {} }
    for _, cat in ipairs(I.WeaponCat) do
        local id, c = I.SlotRef(ply, cat)
        if id > 1 then
            local info = I.Info(id, c)
            local wep = info.weaponClass and ply:GetWeapon(info.weaponClass)
            data.s[cat] = packItem({
                id = id, c = c,
                r = IsValid(wep) and math.max(wep:Clip1(), 0) or ply:GetNWInt(cat .. "Rounds"),
                m = I.CarryConfig(id, c) and ply:GetNWInt(cat .. "Carry") or nil,
                x = IsValid(wep) and I.WeaponExtra and I.WeaponExtra(wep) or nil,
            })
        end
    end
    for cat in pairs(I.GearCat) do
        local id = ply:GetNW2Int(cat)
        if id > 1 then data.s[cat] = packItem({ id = id, a = ply:GetNWInt(cat .. "Armor") }) end
    end
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do data.c[cont] = I.PackItems(I.Get(ply, cont)) end
    return util.TableToJSON(data)
end

function I.Record(owner)
    if owner == nil then return end
    local v = sql.QueryValue("SELECT Data FROM " .. I.TABLE .. " WHERE OwnerID = " .. SQLStr(tostring(owner)))
    local data = v and util.JSONToTable(v)
    return istable(data) and data or nil
end

-- Item in a saved slot (for previews of characters...): { id, ... } or nil.
function I.RecordSlot(record, cat)
    return record and record.s and unpackItem(record.s[cat]) or nil
end

function I.Save(ply, owner)
    if owner == nil then return end
    return I.SQLRequest("REPLACE INTO " .. I.TABLE .. " (OwnerID, Data) VALUES (" ..
        SQLStr(tostring(owner)) .. ", " .. SQLStr(I.Serialize(ply)) .. ")")
end

function I.CreateRecord(owner)
    if owner == nil then return end
    return I.SQLRequest("REPLACE INTO " .. I.TABLE .. " (OwnerID, Data) VALUES (" ..
        SQLStr(tostring(owner)) .. ", " .. SQLStr(util.TableToJSON({ v = 3, s = {}, c = {} })) .. ")")
end

function I.DeleteRecord(owner)
    if owner == nil then return end
    return I.SQLRequest("DELETE FROM " .. I.TABLE .. " WHERE OwnerID = " .. SQLStr(tostring(owner)))
end

-- Order of equipping: the uniform first (pockets), then the gear, then the weapons.
local GEAR_ORDER = { "Uniform", "Vest", "Rucksack", "Helmet", "Gasmask", "NVGs", "Radio" }

function I.Load(ply, owner)
    I.Clear(ply)
    local data = I.Record(owner)
    if data and istable(data.s) then
        local conts = istable(data.c) and data.c or {}
        for _, cat in ipairs(GEAR_ORDER) do
            local it = I.GearCat[cat] and unpackItem(data.s[cat])
            if it then
                local contents = (cat == "Vest" or cat == "Rucksack") and I.UnpackItems(conts[cat]) or nil
                I.Equip(ply, it, contents)
            end
        end
        for _, cat in ipairs(I.WeaponCat) do
            local it = unpackItem(data.s[cat])
            if it then I.Equip(ply, it) end
        end
        I.Set(ply, "Uniform", I.UnpackItems(conts.Uniform))
        I.ValidateCarry(ply, false)
    end
    net.Start("advinv_gear_playerspawn")
    net.WriteEntity(ply)
    net.Broadcast()
end
