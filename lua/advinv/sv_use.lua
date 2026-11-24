--[[
    Using items and unloading weapons, server side (rules in sh_use.lua).
        ACT.USE     holder, container, index           use an item of one's own containers
        ACT.UNLOAD  false, holder, container, index    unload a stored weapon
                    true, slot                         unload an equipped weapon
--]]
local I = AdvInv
local handlers = I.ActHandlers

-- Uses item (taken from ply's containers by the caller if this returns true, unless keep).
-- -> ok, reason, keep
function I.UseItem(ply, item)
    local use = I.UseOf(item)
    if not use then return false, I.L("use_cannot") end
    if hook.Run("AdvInv_UseItem", ply, item) == false then return false end
    if use.grenade then -- the grenade weapon in the hands; the item goes when it is thrown
        if not ply:HasWeapon(use.grenade) then ply:Give(use.grenade, true) end
        ply:SelectWeapon(use.grenade)
        I.MarkDirty(ply, "Uniform") -- its reserve: the grenade items
        return true, nil, true
    end
    if use.custom then
        local t = I.EntTable(item.id)
        return t:OnUseItem(ply, item) == true
    end
    local hp, maxHp = ply:Health(), ply:GetMaxHealth()
    local ar, maxAr = ply:Armor(), (ply.GetMaxArmor and ply:GetMaxArmor() or 100)
    local gainHp = math.max(math.min((use.health or 0), maxHp - hp), 0)
    local gainAr = math.max(math.min((use.armor or 0), maxAr - ar), 0)
    if gainHp <= 0 and gainAr <= 0 then return false, I.L("use_not_needed") end
    if gainHp > 0 then ply:SetHealth(hp + gainHp) end
    if gainAr > 0 then ply:SetArmor(ar + gainAr) end
    if use.sound then ply:EmitSound(use.sound) end
    return true
end

handlers[I.ACT.USE] = function(ply)
    local holder, cont, index = net.ReadEntity(), I.ReadCont(), net.ReadUInt(8)
    if holder ~= ply or not cont or not ply:Alive() then return end
    local items = I.Get(ply, cont)
    local item = items[index]
    if not item then return end
    local ok, why, keep = I.UseItem(ply, item)
    if not ok then return false, why end
    if keep then return true end
    if items[index] == item then table.remove(items, index) end
    I.MarkDirty(ply, cont)
    return true
end

-- Puts rounds of ammo into ply's ammo boxes: the started ones first, then new boxes (into the
-- containers, else on the ground). -> rounds that found no place (always 0: the ground takes them)
function I.GiveRounds(ply, ammo, rounds)
    local boxID, boxC = I.AmmoBoxFor(ammo)
    if not boxID or rounds <= 0 then return rounds end
    local info = I.Info(boxID, boxC)
    local size = math.max(info.boxRounds or 0, 1)
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        for _, it in ipairs(I.Get(ply, cont)) do
            if rounds <= 0 then break end
            if it.id == boxID and it.c == boxC and (it.r or 0) < size then
                local add = math.min(size - (it.r or 0), rounds)
                it.r = (it.r or 0) + add
                rounds = rounds - add
                I.MarkDirty(ply, cont)
            end
        end
    end
    while rounds > 0 do
        local box = { id = boxID, c = boxC, r = math.min(size, rounds), a = 0 }
        rounds = rounds - box.r
        if not I.Store(ply, box) then I.SpawnItem(box, I.DropPos(ply)) end
    end
    return 0
end

handlers[I.ACT.UNLOAD] = function(ply)
    if not ply:Alive() then return end
    if net.ReadBool() then -- an equipped weapon
        local cat = AdvInv.IDCategory[net.ReadUInt(4)]
        if not (cat and table.HasValue(AdvInv.WeaponCat, cat)) then return end
        local id, c = I.SlotRef(ply, cat)
        local info = I.Info(id, c)
        if not info.isWeapon then return end
        local wep = info.weaponClass and ply:GetWeapon(info.weaponClass)
        local rounds = IsValid(wep) and math.max(wep:Clip1(), 0) or ply:GetNWInt(cat .. "Rounds")
        local ammo = I.WeaponAmmo(id, c)
        if not I.CanUnload(id, c, rounds) then return false, I.L("unload_cannot") end
        if IsValid(wep) then wep:SetClip1(0) end
        ply:SetNWInt(cat .. "Rounds", 0)
        I.GiveRounds(ply, ammo, rounds)
        return true
    end
    local holder, cont, index = net.ReadEntity(), I.ReadCont(), net.ReadUInt(8)
    if not (cont and I.CanAccess(ply, holder) and I.CanTakeFrom(ply, holder)) then return end
    local item = I.Get(holder, cont)[index]
    if not item then return end
    local ammo = I.WeaponAmmo(item.id, item.c)
    if not I.CanUnload(item.id, item.c, item.r) then return false, I.L("unload_cannot") end
    local rounds = item.r
    item.r = 0
    I.MarkDirty(holder, cont)
    I.GiveRounds(ply, ammo, rounds)
    return true
end
