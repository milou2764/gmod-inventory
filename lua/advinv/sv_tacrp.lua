--[[
    TacRP (Tactical RP Weapons and its packs), when installed: server side (sh_tacrp.lua: grenades,
    holsters). Its weapons are generic items like any other; this file joins the base's own features to
    the inventory:
      - the attachments travel with the item (taken off, stored, dropped, looted, saved), with the fire
        mode, the second pistol's magazine of a pair (Clip2) and the ammunition the attachments make it
        use (unloading gives boxes of that one). Whoever equips the weapon gets them as they were, at
        once (no window without them): TacRP's own attachment inventory, its bench rule and the
        client's autosaved loadout are not consulted for the item's own loadout;
      - rounds TacRP gives back to the reserve (a magazine taken out by an attachment that changes the
        ammunition or the magazine size, unloading) go into ammo boxes: the reserve is the boxes;
      - a weapon picked up again gives no free magazine (its EquipAmmo); a quick grenade is thrown only
        while there is one (an item moved away while priming is not thrown); a grenade a dying player
        was priming is taken from his items;
      - its ammo bag and crate: the magazine they hand out goes into ammo boxes; the surplus ammunition
        attachments' refunds too.
    Recommended: tacrp_infiniteammo, tacrp_infinitelaunchers, tacrp_infinitegrenades 0 (an infinite
    magazine refills from nothing: the inventory's items would be filled for free).
--]]
local I = AdvInv

local BASE = "tacrp_base"

---------------------------------------------------------------- attachments and state

local function slotAccepts(w, i, name)
    local att = TacRP and TacRP.Attachments and TacRP.Attachments[name]
    local slot = w.Attachments[i]
    if not (istable(att) and istable(slot)) then return false end
    if att.Compatibility then
        local ok, r = pcall(att.Compatibility, w)
        if ok and r == true then return true end
        if ok and r == false then return false end
    end
    local cats = istable(slot.Category) and slot.Category or { slot.Category }
    local own = istable(att.Category) and att.Category or { att.Category }
    for _, c in pairs(own) do
        if table.HasValue(cats, c) then return true end
    end
    return false
end

table.insert(I.WeaponDataAdapters, {
    immediate = true, -- (TacRP sets a weapon up in full when it is given)
    match = function(w) return w.ArcticTacRP == true and istable(w.Attachments) and w.NetworkWeapon ~= nil end,
    save = function(w)
        local a = {}
        for i, slot in pairs(w.Attachments) do
            if isnumber(i) and istable(slot) and isstring(slot.Installed) and not slot.Integral then a[tostring(i)] = slot.Installed end
        end
        local d = { a = a }
        if w.GetFiremode then d.f = w:GetFiremode() end
        if w.GetValue and w:GetValue("DualAkimbo") then d.c2 = math.max(w:Clip2(), 0) end
        local am = w.Primary and w.Primary.Ammo
        if isstring(am) and am ~= "" and string.lower(am) ~= "none" then d.am = am end
        if w:GetNWBool("TacRP_PoliceBiocode") then d.pb = true end
        return util.TableToJSON(d) -- (even with no attachment: the item's loadout, not the client's autosave)
    end,
    load = function(w, s)
        local d = util.JSONToTable(s)
        if not istable(d) then return end
        local owner = w:GetOwner()
        local ply = IsValid(owner) and owner:IsPlayer() and owner or nil
        local clip = w:Clip1()
        w:SetClip1(0) -- (a smaller magazine set up below hands nothing back: the excess is handled here)
        local want = istable(d.a) and d.a or {}
        for i, slot in pairs(w.Attachments) do
            if isnumber(i) and istable(slot) and not slot.Integral then
                local name = want[tostring(i)]
                slot.Installed = (isstring(name) and slotAccepts(w, i, name)) and name or nil
            end
        end
        if w.InvalidateCache then w:InvalidateCache() end
        if w.SetBaseSettings then w:SetBaseSettings() end
        if w.NetworkWeapon then w:NetworkWeapon() end
        if isnumber(d.f) and w.SetFiremode and w.GetFiremodeAmount then
            w:SetFiremode(math.Clamp(math.floor(d.f), 1, math.max(w:GetFiremodeAmount(), 1)))
        end
        local cap = w:GetMaxClip1()
        if cap > 0 then
            local keep = math.min(clip, cap)
            w:SetClip1(keep)
            if ply and clip > keep then I.GiveRounds(ply, w.Primary.Ammo, clip - keep) end
        else
            w:SetClip1(clip)
        end
        if isnumber(d.c2) and w.GetValue and w:GetValue("DualAkimbo") then
            local cap2 = w.GetCapacity2 and w:GetCapacity2() or d.c2
            w:SetClip2(math.Clamp(math.floor(d.c2), 0, math.max(cap2, 0)))
        end
        if d.pb then w:SetNWBool("TacRP_PoliceBiocode", true) end
        w.AdvInvTacRPLoaded = CurTime()
    end,
})

---------------------------------------------------------------- reserve gains -> ammo boxes

local function reserves(ply)
    local t = {}
    for id = 1, 1024 do
        local name = game.GetAmmoName(id)
        if not name then break end
        t[name] = ply:GetAmmoCount(id)
    end
    return t
end

local function gainsToBoxes(f)
    return function(self, ...)
        local o = self:GetOwner()
        if not (IsValid(o) and o:IsPlayer()) or self.AdvInvAmmoWatch then return f(self, ...) end
        self.AdvInvAmmoWatch = true -- (the outer call only: Attach calls SetBaseSettings and Unload)
        local before = reserves(o)
        I.BeginGainConversion(o)
        local r = { pcall(f, self, ...) }
        self.AdvInvAmmoWatch = nil
        local types = {}
        if IsValid(o) then
            local gained = false
            for name, n in pairs(reserves(o)) do
                local diff = n - (before[name] or 0)
                -- (grenades: their own reconciliation makes them items, sv_grenades.lua)
                if diff > 0 and not (I.GrenadeOfAmmo and I.GrenadeOfAmmo(name)) then
                    I.GiveRounds(o, name, diff, I.IsBoundJobWeapon and I.IsBoundJobWeapon(o, self))
                    gained, types[name] = true, true
                end
            end
            if gained then I.SyncAmmo(o) end
        end
        I.EndGainConversion(o, types)
        if not r[1] then error(r[2], 0) end
        return unpack(r, 2)
    end
end

local function nadeOf(w)
    if not (TacRP and TacRP.QuickNades) then return end
    local pg = w.GetValue and w:GetValue("PrimaryGrenade")
    if pg then return TacRP.QuickNades[pg] end
    return w.GetGrenade and w:GetGrenade() or nil
end

local function finite(nade)
    return istable(nade) and isstring(nade.Ammo) and not nade.Singleton
        and not (TacRP.IsGrenadeInfiniteAmmo and TacRP.IsGrenadeInfiniteAmmo(nade))
end

hook.Add("PreRegisterSWEP", "AdvInv_TacRP", function(swep, class)
    if class ~= BASE or swep.AdvInvTacRPPatched then return end
    for _, name in ipairs({ "Unload", "Attach", "Detach", "SetBaseSettings" }) do
        local f = rawget(swep, name)
        if isfunction(f) then swep[name] = gainsToBoxes(f) end
    end
    -- a weapon of a class he already has, picked up: no free magazine for a player (the reserve is the boxes)
    local equipAmmo = rawget(swep, "EquipAmmo")
    if isfunction(equipAmmo) then
        swep.EquipAmmo = function(self, ply, ...)
            if IsValid(ply) and ply:IsPlayer() then return end
            return equipAmmo(self, ply, ...)
        end
    end
    -- the client's autosaved loadout sent when the weapon first thinks: not over the item's own
    local receive = rawget(swep, "ReceivePreset")
    if isfunction(receive) then
        swep.ReceivePreset = function(self, ...)
            if self.AdvInvTacRPLoaded and CurTime() - self.AdvInvTacRPLoaded < 5 then return end
            return gainsToBoxes(receive)(self, ...)
        end
    end
    -- a quick grenade thrown only while there is one (an item moved or dropped while priming)
    local throw = rawget(swep, "ThrowGrenade")
    if isfunction(throw) then
        swep.ThrowGrenade = function(self, ...)
            local o = self:GetOwner()
            local nade = nadeOf(self)
            if IsValid(o) and o:IsPlayer() and finite(nade) and o:GetAmmoCount(nade.Ammo) < 1 then
                if self.SetPrimedGrenade then self:SetPrimedGrenade(false) end
                return
            end
            return throw(self, ...)
        end
    end
    swep.AdvInvTacRPPatched = true
end)

---------------------------------------------------------------- refunds, entities, death

-- the surplus ammunition attachments give rounds back after a shot (their Hook_PostShoot): boxes
local REFUND = { ammo_surplus = true, ammo_surplus2 = true, ammo_rpg_improvised = true }
local function allowRefund(wep)
    local o = IsValid(wep) and wep:GetOwner()
    if not (IsValid(o) and o:IsPlayer() and istable(wep.Attachments)) then return end
    for _, slot in pairs(wep.Attachments) do
        if istable(slot) and REFUND[slot.Installed] then
            local id = wep:GetPrimaryAmmoType()
            if id and id >= 0 then I.AllowAmmoGain(o, game.GetAmmoName(id)) end
            return
        end
    end
end
hook.Add("TacRP_Hook_PreShoot", "AdvInv_TacRP", function(wep) allowRefund(wep) end)
hook.Add("TacRP_Hook_PreShootEnt", "AdvInv_TacRP", function(wep) allowRefund(wep) end)

local function setup()
    if not TacRP then return end
    -- its ammo bag and crate: one magazine of the weapon in hand (and a grenade: a grenade item)
    for class in pairs(scripted_ents.GetList()) do
        if class == "tacrp_ammo" or scripted_ents.IsBasedOn(class, "tacrp_ammo") then
            local stored = scripted_ents.GetStored(class)
            local t = stored and stored.t
            local apply = t and rawget(t, "ApplyAmmo")
            if apply and not rawget(t, "AdvInvApplyAmmo") then
                t.AdvInvApplyAmmo = apply
                t.ApplyAmmo = function(self, ply, ...)
                    local w = IsValid(ply) and ply:GetActiveWeapon()
                    if IsValid(w) then
                        local at = w.ArcticTacRP and w.GetAmmoType and w:GetAmmoType() or w:GetPrimaryAmmoType()
                        if isnumber(at) then at = game.GetAmmoName(at) end
                        if isstring(at) and at ~= "" then I.AllowAmmoGain(ply, at) end
                    end
                    return apply(self, ply, ...)
                end
            end
        end
        -- a thrown knife picked up gives its crossbow bolt back
        if class == "tacrp_proj_knife" then
            local stored = scripted_ents.GetStored(class)
            local t = stored and stored.t
            local touch = t and rawget(t, "Touch")
            if touch and not rawget(t, "AdvInvTouch") then
                t.AdvInvTouch = touch
                t.Touch = function(self, ent, ...)
                    if IsValid(ent) and ent:IsPlayer() and self.HasAmmo then I.AllowAmmoGain(ent, "xbowbolt") end
                    return touch(self, ent, ...)
                end
            end
        end
    end
    -- a dying player's primed grenade is thrown without its ammunition being taken: one item less
    local death = hook.GetTable().DoPlayerDeath
    local drop = death and death.TacRP_DropGrenade
    if isfunction(drop) and not I.TacRPDropWrapped then
        I.TacRPDropWrapped = true
        hook.Add("DoPlayerDeath", "TacRP_DropGrenade", function(ply, ...)
            local wep = ply:GetActiveWeapon()
            local nade = IsValid(wep) and wep.ArcticTacRP and wep.GetPrimedGrenade and wep:GetPrimedGrenade() and nadeOf(wep)
            local r = { drop(ply, ...) }
            if finite(nade) and I.GrenadeDroppedAtDeath then I.GrenadeDroppedAtDeath(ply, nade.Ammo) end
            return unpack(r)
        end)
    end
    for _, cv in ipairs({ "tacrp_infiniteammo", "tacrp_infinitelaunchers", "tacrp_infinitegrenades" }) do
        local c = GetConVar(cv)
        if c and c:GetBool() then
            MsgC(Color(255, 180, 80), "[Advanced Inventory] " .. cv .. " is on: magazines refill from nothing, "
                .. "and the inventory keeps those rounds in its items. Set it to 0 to keep ammunition limited.\n")
        end
    end
end

hook.Add("InitPostEntity", "AdvInv_TacRP", setup)
setup() -- Lua refresh

-- DarkRP: a weapon TacRP itself dropped (its attachments as ID numbers on the dropped weapon) keeps them
local function fromIDs(ent)
    if not (IsValid(ent) and TacRP and ent.AdvInvExtra == nil and istable(ent.Attachments)) then return end
    local a = {}
    for slot, id in pairs(ent.Attachments) do
        local name = isnumber(id) and TacRP.Attachments_Index and TacRP.Attachments_Index[id] or id
        if isstring(name) and TacRP.Attachments[name] then a[tostring(slot)] = name end
    end
    if next(a) then ent.AdvInvExtra = util.TableToJSON({ a = a }) end
end
hook.Add("onDarkRPWeaponDropped", "AdvInv_TacRP", function(_, ent)
    timer.Simple(0, function() fromIDs(ent) end)
end)
hook.Add("onPocketItemDropped", "AdvInv_TacRP", function(_, ent)
    timer.Simple(0, function() fromIDs(ent) end)
end)
