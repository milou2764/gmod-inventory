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
    local grenade = I.GrenadeAmmo(class) -- a grenade is an item: one round of its ammunition
    if grenade and game.GetAmmoID(grenade) ~= -1 then return { id = I.GENERIC_AMMO, c = grenade, r = 1 } end
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

--[[
    Rounds in an underbarrel launcher: an ArcCW UBGL (Clip2, of its UBGL_Ammo), CW 2.0's M203 (one
    40MM round chambered), another base's Clip2 (its secondary ammunition). The item keeps only the
    magazine: when the weapon leaves its slot (taken off, stripped, its owner dead) they go back into
    ammo boxes, else they would be lost. -> ammo, rounds, clear() (nil when there are none)
--]]
function I.UnderbarrelRounds(wep)
    if not IsValid(wep) then return end
    if wep.CW20Weapon then
        -- (M203Chamber is true on every CW 2.0 weapon by default: a round only with the M203 fitted)
        if not (wep.M203Chamber and istable(wep.ActiveAttachments) and wep.ActiveAttachments.md_m203) then return end
        return "40MM", 1, function()
            -- (set here; CW's own setter messages the owner, who may be gone: dropped, stripped)
            wep.M203Chamber = false
            local o = wep:GetOwner()
            if wep.networkM203Chamber and IsValid(o) and o:IsPlayer() then wep:networkM203Chamber() end
        end
    end
    local n = wep:Clip2()
    if not (n and n > 0) then return end
    local ammo = wep.ArcCW and wep.GetBuff_Override and wep:GetBuff_Override("UBGL_Ammo") or nil
    if (not isstring(ammo) or ammo == "") and wep.ArcCW and ArcCW and ArcCW.AttachmentTable then
        -- (the buff cache may not have it: the installed attachment's own table)
        for _, a in pairs(wep.Attachments or {}) do
            local att = a.Installed and ArcCW.AttachmentTable[a.Installed]
            if att and isstring(att.UBGL_Ammo) then ammo = att.UBGL_Ammo break end
        end
    end
    if not isstring(ammo) or ammo == "" then ammo = game.GetAmmoName(wep:GetSecondaryAmmoType()) end
    if not (isstring(ammo) and ammo ~= "" and I.AmmoBoxFor(ammo)) then return end
    return ammo, n, function() wep:SetClip2(0) end
end

-- A weapon the inventory has just given: its underbarrel launcher starts empty (the round it had was
-- put into boxes when it left its slot; CW 2.0 chambers one on every new weapon, Give may fill a
-- Clip2): else every equip would make a round, and every take-off a box of it.
function I.EmptyUnderbarrel(wep)
    if not IsValid(wep) then return end
    if wep.CW20Weapon and wep.M203Chamber then
        -- set here, told to the owner's client a moment later: CW's message names the weapon, which a
        -- client doesn't know yet in the tick it is given (its receiver would index a NULL entity)
        wep.M203Chamber = false
        if wep.networkM203Chamber then
            timer.Simple(0.5, function()
                if IsValid(wep) and IsValid(wep:GetOwner()) and wep:GetOwner():IsPlayer() and not wep.M203Chamber then
                    wep:networkM203Chamber()
                end
            end)
        end
    end
    if (wep:Clip2() or 0) > 0 then wep:SetClip2(0) end
end

function I.UnloadUnderbarrel(ply, wep)
    local ammo, n, clear = I.UnderbarrelRounds(wep)
    if not ammo then return 0 end
    clear()
    I.GiveRounds(ply, ammo, n)
    return n
end

function I.WeaponExtra(wep)
    if not IsValid(wep) then return end
    if wep.AdvInvExtraPending then return wep.AdvInvExtraPending end -- not on yet (I.ApplyWeaponExtra)
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
    wep.AdvInvExtraPending = data -- until they are on, its attachments are these (I.WeaponExtra)
    timer.Simple(0.2, function() -- the weapon base sets itself up first
        if not IsValid(wep) then return end
        if wep.AdvInvExtraPending ~= data then return end -- applied again meanwhile: that one counts
        wep.AdvInvExtraPending = nil
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

-- light: only whether it is an item (no attachment data: hooks that run every tick).
function I.GenericItemFromEntity(ent, light)
    if not IsValid(ent) then return end
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
            clip = I.SwepClipSize(swep) or (reg and I.Info(reg).clipSize) or 0
        end
        local item = I.ItemForWeaponClass(wclass, math.max(clip, 0))
        if item then
            item.x = ent.AdvInvExtra
            if ent.AdvInvCarryMode then item.m = ent.AdvInvCarryMode end
        end
        return item
    end
    if ent:IsWeapon() then
        if IsValid(ent:GetOwner()) or not pickWeapons:GetBool() then return end
        local item = I.ItemForWeaponClass(class, math.max(ent:Clip1(), 0))
        if item and ent.AdvInvCarryMode then item.m = ent.AdvInvCarryMode end
        -- attachments kept from when it was dropped (a weapon lying in the world may not show them)
        if item and not light then item.x = ent.AdvInvExtra or I.WeaponExtra(ent) end
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
    if I.GenericItemFromEntity(wep, true) then return false end
end)

-- Ammo type of an ammo entity (HL2 ammo, other bases' ammo, DarkRP's), nil for anything else.
local function entityAmmo(ent)
    local conv = I.PickupConvert[ent:GetClass()]
    local id = conv and AdvInv.ClassID[conv]
    if id then return I.Info(id).ammo end
    return (baseAmmo(ent))
end

hook.Add("PlayerCanPickupItem", "AdvInv_WorldItems", function(ply, item)
    if not pickEntities:GetBool() or beingGiven(item, ply) then
        I.AllowAmmoGain(ply, entityAmmo(item)) -- picked up the game's way: its rounds become boxes
        return
    end
    local class = item:GetClass()
    if I.PickupWhitelist[class] or I.PickupConvert[class] then return false end
end)

-- Use key: into the inventory (registered items handle Use themselves).
hook.Add("PlayerUse", "AdvInv_WorldItems", function(ply, ent)
    local id = AdvInv.ClassID[ent:GetClass()]
    if id and not I.IsGeneric(id) then return end
    if I.GenericItemFromEntity(ent, true) then
        I.Use(ply, ent)
        return false
    end
    -- not taken into the inventory (advinv_pickup_entities 0): an ammo entity's own Use puts its
    -- rounds into the reserve; they become boxes
    I.AllowAmmoGain(ply, entityAmmo(ent))
end)

-- Spawn menu (gm_giveswep): the gamemode decides as usual (DarkRP: adminweapons, arrested...).
-- This hook gives nothing and returns nothing; the weapon the gamemode then gives goes into the
-- inventory on the next tick (equipped if its slot is free, else stored, else on the ground).
hook.Add("PlayerGiveSWEP", "AdvInv_GiveSWEP", function(ply, class)
    if I.GrenadeAmmo(class) then return end -- grenades: given grenades become items (sv_grenades.lua)
    if pickWeapons:GetBool() and I.ItemForWeaponClass(class, 0) then
        -- only the Give that follows on this tick (the gamemode may refuse: nothing given then)
        local g = { class = class, tick = engine.TickCount() }
        ply.AdvInvGiveSWEP = g
        timer.Simple(0, function()
            if IsValid(ply) and ply.AdvInvGiveSWEP == g then ply.AdvInvGiveSWEP = nil end
        end)
    end
end)

hook.Add("WeaponEquip", "AdvInv_GiveSWEP", function(wep, ply)
    local g = IsValid(ply) and ply.AdvInvGiveSWEP
    if not (g and IsValid(wep) and g.class == wep:GetClass() and g.tick == engine.TickCount()) then return end
    ply.AdvInvGiveSWEP = nil
    timer.Simple(0, function()
        if not (IsValid(ply) and ply:Alive() and IsValid(wep) and wep:GetOwner() == ply) then return end
        local class = wep:GetClass()
        for _, cat in ipairs(I.WeaponCat) do
            if I.SlotInfo(ply, cat).weaponClass == class then return end -- already the slot's weapon
        end
        local item = I.ItemForWeaponClass(class, math.max(wep:Clip1(), 0))
        if not item then return end
        ply:StripWeapon(class)
        local ok, why = I.Equip(ply, item)
        if not ok and not I.Store(ply, item) then
            I.Tell(ply, why or I.L("msg_no_room_for", I.Info(item.id, item.c).name))
            I.SpawnItem(item, I.DropPos(ply))
        end
    end)
end)
