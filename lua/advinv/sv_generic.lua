--[[
    Weapons and whitelisted entities lying in the world go into the inventory (sh_generic.lua).

    - A weapon lying in the world (dropped, spawned from the menu, left by a map) is not picked up
      by walking over it: the Use key takes it, into its slot if free, else into the containers.
      It becomes its registered item if there is one (weapon_ar2 -> advinv_hl2_ar2), else a generic weapon.
      Weapons given by code (loadouts, jobs, ply:Give) are not touched.
    - A weapon given from the spawn menu goes straight into the inventory.
    - Whitelisted entities (HL2 health kit, vial, battery) and HL2 ammo are taken with Use too
      (touching them no longer uses them); HL2 ammo becomes the matching ammo box.
--]]
local I = AdvInv
local FLAGS = { FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED }

local pickWeapons = CreateConVar("advinv_pickup_weapons", "1", FLAGS,
    "Weapons lying in the world are taken with Use into the inventory (not by walking over them)", 0, 1)
local anyWeapon = CreateConVar("advinv_pickup_any_weapon", "1", FLAGS,
    "Weapons with no registered item of their own become generic inventory items", 0, 1)
local pickEntities = CreateConVar("advinv_pickup_entities", "1", FLAGS,
    "Whitelisted entities (health kits, batteries, HL2 ammo...) are taken with Use into the inventory", 0, 1)

-- Is ent being handed to ply by code (ply:Give)? The engine creates it at the player's feet and
-- gives it at once; a weapon lying in the world is elsewhere, or older.
local function beingGiven(ent, ply)
    if not IsValid(ent) then return false end
    return CurTime() - (ent:GetCreationTime() or 0) < 0.1 and ent:GetPos():DistToSqr(ply:GetPos()) < 4
end

-- Item for a weapon class (its registered item, else a generic weapon), with rounds in the magazine.
function I.ItemForWeaponClass(class, rounds)
    if I.WeaponBlacklist[class] then return end
    local reg = I.ItemForWeapon(class)
    if reg then return { id = reg, r = rounds or 0 } end
    if anyWeapon:GetBool() and I.DefTable(I.GENERIC_WEAPON, class) then
        return { id = I.GENERIC_WEAPON, c = class, r = rounds or 0 }
    end
end

--[[
    Extra data of a weapon (its attachments), kept in the item (x) when it is taken off, stored,
    dropped and given back. Hooks (server): AdvInv_WeaponData(wep) -> string, and
    AdvInv_ApplyWeaponData(wep, data) -> true when done. Built in, without testing on every
    version of these bases: ARC9 (preset code), TFA (selected attachments), CW 2.0 (attachments).
--]]
I.WeaponDataAdapters = I.WeaponDataAdapters or {
    { -- ARC9
        match = function(w) return w.ARC9 and (w.GeneratePresetExportCode ~= nil) end,
        save = function(w) return w:GeneratePresetExportCode() end,
        load = function(w, s)
            if w.LoadPresetFromCode then w:LoadPresetFromCode(s)
            elseif w.ImportPresetCode then w:ImportPresetCode(s) end
        end,
    },
    { -- TFA
        match = function(w) return w.IsTFAWeapon and istable(w.Attachments) end,
        save = function(w)
            local t = {}
            for k, v in pairs(w.Attachments) do
                if istable(v) and v.sel and v.sel ~= 0 and v.sel ~= -1 then t[tostring(k)] = v.sel end
            end
            return next(t) and util.TableToJSON(t) or nil
        end,
        load = function(w, s)
            for k, sel in pairs(util.JSONToTable(s) or {}) do
                if w.SetTFAAttachment then w:SetTFAAttachment(tonumber(k) or k, sel, true) end
            end
        end,
    },
    { -- CW 2.0: the names of the attachments (more in sv_cw2.lua)
        match = function(w) return w.CW20Weapon and istable(w.ActiveAttachments) end,
        save = function(w)
            local t = {}
            for name, on in pairs(w.ActiveAttachments) do
                if on then t[#t + 1] = name end
            end
            table.sort(t)
            return #t > 0 and util.TableToJSON(t) or nil
        end,
        load = function(w, s)
            local owner = w:GetOwner()
            local names = util.JSONToTable(s)
            if not (IsValid(owner) and owner:IsPlayer() and istable(names) and w.attachSpecificAttachment) then return end
            -- whoever carries the weapon owns its attachments (as CW 2.0 does for its dropped weapons)
            local CW = CustomizableWeaponry
            if CW and CW.giveAttachments then CW.giveAttachments(owner, names, true) end
            local clip = w:Clip1()
            w:SetClip1(0) -- some attachments unload the magazine: nothing to unload
            local pending = names
            for _ = 1, #names do -- again for the ones that need another attachment first
                local left = {}
                for _, name in ipairs(pending) do
                    if not w.ActiveAttachments[name] then w:attachSpecificAttachment(name) end
                    if not w.ActiveAttachments[name] then left[#left + 1] = name end
                end
                if #left == 0 or #left == #pending then break end
                pending = left
            end
            w:SetClip1(clip)
        end,
    },
}

function I.WeaponExtra(wep)
    if not IsValid(wep) then return end
    local h = hook.Run("AdvInv_WeaponData", wep)
    if h ~= nil then return isstring(h) and h ~= "" and string.sub(h, 1, 4096) or nil end
    for _, a in ipairs(I.WeaponDataAdapters) do
        local okMatch, matches = pcall(a.match, wep)
        if okMatch and matches then
            local ok, s = pcall(a.save, wep)
            if ok and isstring(s) and s ~= "" then return string.sub(s, 1, 4096) end
            return
        end
    end
end

function I.ApplyWeaponExtra(wep, data)
    if not (IsValid(wep) and isstring(data) and data ~= "") then return end
    timer.Simple(0.2, function() -- the weapon base sets itself up first
        if not IsValid(wep) then return end
        if hook.Run("AdvInv_ApplyWeaponData", wep, data) then return end
        for _, a in ipairs(I.WeaponDataAdapters) do
            local okMatch, matches = pcall(a.match, wep)
            if okMatch and matches then
                pcall(a.load, wep, data)
                return
            end
        end
    end)
end

-- Ammunition entities of other weapon bases: their type and number of rounds, if they say.
local function baseAmmo(ent)
    local t = ent.AmmoType or ent.ammoType or ent.Ammo
    local n = ent.AmmoCount or ent.AmmoAmount or ent.Amount or ent.ammoAmount or ent.AmmoGiven or ent.amountGiven
    if isstring(t) and isnumber(n) and n > 0 and game.GetAmmoID(t) ~= -1 then return t, math.floor(n) end
end

-- Item for an entity that is not an registered item: a weapon lying in the world, a whitelisted
-- entity, HL2 ammo, a generic ammo box, other weapon bases' ammo. nil if it cannot go into the
-- inventory.
I.EntityItemHandlers = I.EntityItemHandlers or {} -- [class] = function(ent) -> item or nil (sv_cw2.lua...)

function I.GenericItemFromEntity(ent)
    local class = ent:GetClass()
    local handler = I.EntityItemHandlers[class]
    if handler then return handler(ent) end
    if class == "advinv_any_ammo" then
        local ammo = ent:GetNWString("AdvInvAmmo", "")
        if ammo == "" then return end
        return { id = I.GENERIC_AMMO, c = ammo, r = math.max(math.floor(ent.Rounds or ent:GetNWInt("AdvInvRounds")), 0) }
    end
    if class == "spawned_weapon" and ent.GetWeaponClass then -- DarkRP: a weapon lying around
        if not pickWeapons:GetBool() then return end
        local wclass = ent:GetWeaponClass()
        local clip = tonumber(ent.clip1)
        if not clip then -- from a shipment: full magazine
            local swep = weapons.Get(wclass)
            local reg = I.ItemForWeapon(wclass)
            clip = (swep and swep.Primary and swep.Primary.ClipSize) or (reg and I.Info(reg).clipSize) or 0
        end
        return I.ItemForWeaponClass(wclass, math.max(clip, 0))
    end
    if ent:IsWeapon() then
        if IsValid(ent:GetOwner()) or not pickWeapons:GetBool() then return end
        local item = I.ItemForWeaponClass(class, math.max(ent:Clip1(), 0))
        if item and ent.AdvInvCarryMode then item.m = ent.AdvInvCarryMode end
        -- attachments kept from when it was dropped (a weapon lying in the world may not show them)
        if item then item.x = ent.AdvInvExtra or I.WeaponExtra(ent) end
        return item
    end
    if not pickEntities:GetBool() then return end
    local ammo, rounds = baseAmmo(ent)
    if ammo and not AdvInv.ClassID[class] then
        local id, c = I.AmmoBoxFor(ammo)
        if id then return { id = id, c = c, r = rounds } end
    end
    local conv = I.PickupConvert[class]
    local id = conv and AdvInv.ClassID[conv]
    if id then
        local info = I.Info(id)
        return { id = id, r = info.isBox and (info.boxRounds or 0) or 0 }
    end
    if I.PickupWhitelist[class] then return { id = I.GENERIC_ENTITY, c = class } end
end

-- A generic item put back into the world.
function I.SpawnGeneric(item, pos) -- (count and rounds shown: I.SpawnItem)
    if not isstring(item.c) or item.c == "" then return end
    if item.id == I.GENERIC_AMMO then
        local d = I.DefTable(item.id, item.c)
        if not d then return end
        local ent = ents.Create("advinv_any_ammo")
        ent.Model = d.Model
        ent.Rounds = item.r or 0
        ent.Capacity = d.Capacity
        ent:SetNWString("AdvInvAmmo", item.c)
        ent:SetPos(pos)
        ent:Spawn()
        return ent
    end
    local ent = ents.Create(item.c)
    if not IsValid(ent) then return end
    ent:SetPos(pos)
    ent:Spawn()
    ent:Activate()
    if item.id == I.GENERIC_WEAPON and ent.SetClip1 then ent:SetClip1(item.r or 0) end
    ent.AdvInvCarryMode = item.m
    ent.AdvInvExtra = item.x
    if item.x then I.ApplyWeaponExtra(ent, item.x) end
    return ent
end

-- Walking over a weapon or whitelisted item lying in the world does not take it.
hook.Add("PlayerCanPickupWeapon", "AdvInv_WorldWeapons", function(ply, wep)
    if not pickWeapons:GetBool() or beingGiven(wep, ply) then return end
    if I.GenericItemFromEntity(wep) then return false end
end)

hook.Add("PlayerCanPickupItem", "AdvInv_WorldItems", function(ply, item)
    if not pickEntities:GetBool() or beingGiven(item, ply) then return end
    local class = item:GetClass()
    if I.PickupWhitelist[class] or I.PickupConvert[class] then return false end
end)

-- Use key: into the inventory (registered items handle Use themselves).
hook.Add("PlayerUse", "AdvInv_WorldItems", function(ply, ent)
    local id = AdvInv.ClassID[ent:GetClass()]
    if id and not I.IsGeneric(id) then return end
    if I.GenericItemFromEntity(ent) then
        I.Use(ply, ent)
        return false
    end
end)

-- Spawn menu (sandbox): a weapon given goes into the inventory, magazine full.
hook.Add("PlayerGiveSWEP", "AdvInv_GiveSWEP", function(ply, class, swep)
    if not pickWeapons:GetBool() then return end
    local clip = swep and swep.Primary and swep.Primary.ClipSize or -1
    local item = I.ItemForWeaponClass(class, math.max(clip or 0, 0))
    if not item then return end
    local reg = I.Info(item.id, item.c)
    if (reg.clipSize or 0) > 0 and not I.IsGeneric(item.id) then item.r = reg.clipSize end
    local ok, why = I.Equip(ply, item)
    if not ok then
        if I.Store(ply, item) then
            ok = true
        else
            I.Tell(ply, why or I.L("msg_no_room_for", reg.name))
        end
    end
    return false
end)
