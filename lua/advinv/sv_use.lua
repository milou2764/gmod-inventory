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
    local holder, cont = net.ReadEntity(), I.ReadCont()
    local index, check = I.ReadItemRef()
    if holder ~= ply or not cont or not ply:Alive() then return end
    index = I.ResolveItemRef(ply, cont, index, check)
    if not index then return false end
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

-- A job's weapon in its slot while job items are bound (DarkRP: dropspawnedweapons off): what its
-- magazine gives back (an attachment changing magazines, a magazine taken out) is the job's too.
function I.IsBoundJobWeapon(ply, wep)
    if not (IsValid(wep) and I.JobItemsBound and I.JobItemsBound()) then return false end
    local cat = I.SlotOfWeaponClass and I.SlotOfWeaponClass(ply, wep:GetClass())
    return cat ~= nil and ply.AdvInvJobSlot ~= nil and ply.AdvInvJobSlot[cat] == true
end

-- Puts rounds of ammo into ply's ammo boxes: the started ones first, then new boxes (into the
-- containers, else on the ground). job: the rounds of a job's weapon: job boxes (kept on him, gone
-- at death like the weapon; else each loadout's full magazine became boxes to give away), and only
-- job boxes are topped up with them (ordinary rounds never go into a job box either).
-- -> rounds that found no place (always 0: the ground takes them)
function I.GiveRounds(ply, ammo, rounds, job)
    job = job and true or false
    local boxID, boxC = I.AmmoBoxFor(ammo)
    if not boxID or rounds <= 0 then return rounds end
    local info = I.Info(boxID, boxC)
    local size = math.max(info.boxRounds or 0, 1)
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        for _, it in ipairs(I.Get(ply, cont)) do
            if rounds <= 0 then break end
            if it.id == boxID and it.c == boxC and (it.r or 0) < size and (it.j and true or false) == job then
                local add = math.min(size - (it.r or 0), rounds)
                it.r = (it.r or 0) + add
                rounds = rounds - add
                I.MarkDirty(ply, cont)
            end
        end
    end
    while rounds > 0 do
        local box = { id = boxID, c = boxC, r = math.min(size, rounds), a = 0, j = job or nil }
        rounds = rounds - box.r
        if not I.Store(ply, box) then
            local pockets = I.Get(ply, "Uniform")
            if job and #pockets < I.MAX_ITEMS then
                pockets[#pockets + 1] = box -- (a job's box never goes down: in the pockets, over their load)
                I.MarkDirty(ply, "Uniform")
            elseif not job then
                I.SpawnItem(box, I.DropPos(ply))
            end -- (a job's box with 255 items in the pockets: gone, never an ordinary one)
        end
    end
    return 0
end

handlers[I.ACT.UNLOAD] = function(ply)
    if not ply:Alive() then return end
    if net.ReadBool() then -- an equipped weapon
        local cat = AdvInv.IDCategory[net.ReadUInt(4)]
        if not (cat and table.HasValue(AdvInv.WeaponCat, cat)) then return end
        -- a job's weapon, while job items are bound to the player (DarkRP's dropspawnedweapons off):
        -- not unloaded (its rounds into ordinary boxes, and a full magazine at each loadout: a farm)
        if ply.AdvInvJobSlot and ply.AdvInvJobSlot[cat] and I.JobItemsBound() then return false, I.L("unload_job") end
        local id, c = I.SlotRef(ply, cat)
        local info = I.Info(id, c)
        if not info.isWeapon then return end
        local wep = info.weaponClass and ply:GetWeapon(info.weaponClass)
        local rounds = IsValid(wep) and math.max(wep:Clip1(), 0) or ply:GetNWInt(cat .. "Rounds")
        local ammo = I.WeaponAmmo(id, c)
        -- the weapon in hand: the ammunition it really uses (an attachment may change it: TFA, ArcCW)
        local live = IsValid(wep) and wep:GetPrimaryAmmoType() or -1
        if live >= 0 and I.AmmoBoxFor(game.GetAmmoName(live)) then ammo = game.GetAmmoName(live) end
        if not I.CanUnload(id, c, rounds) then return false, I.L("unload_cannot") end
        if IsValid(wep) then wep:SetClip1(0) end
        ply:SetNWInt(cat .. "Rounds", 0)
        I.GiveRounds(ply, ammo, rounds)
        return true
    end
    local holder, cont = net.ReadEntity(), I.ReadCont()
    local index, check = I.ReadItemRef()
    if not (cont and I.CanAccess(ply, holder) and I.CanTakeFrom(ply, holder)) then return end
    index = I.ResolveItemRef(holder, cont, index, check)
    if not index then return false end
    local item = I.Get(holder, cont)[index]
    if not item then return end
    -- (a searched player's weapon he may not take, a job's one: its rounds may not be taken either;
    -- a job's weapon would refill at each loadout)
    if I.SearchMayTakeItem then
        local may, why = I.SearchMayTakeItem(ply, holder, item)
        if not may then return false, why end
    end
    if item.j and I.JobItemsBound() then return false, I.L("unload_job") end -- (as above)
    local ammo = I.WeaponAmmo(item.id, item.c)
    if not I.CanUnload(item.id, item.c, item.r) then return false, I.L("unload_cannot") end
    local rounds = item.r
    item.r = 0
    I.MarkDirty(holder, cont)
    I.GiveRounds(ply, ammo, rounds)
    return true
end
