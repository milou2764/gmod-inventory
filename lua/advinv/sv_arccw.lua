--[[
    ArcCW (Arctic's Customizable Weapons), when installed. Its weapons are generic items like any
    other (sh_generic.lua); this file joins the base's own features to the inventory:
      - the installed attachments travel with the item (taken off, stored, dropped, looted, saved).
        Whoever equips the weapon is given them and ArcCW's Attach takes them back: ArcCW's own
        attachment inventory (arccw_attinv_free 0) gains or loses nothing. The client's autosaved
        loadout is not applied over them (ArcCW_DisableAutosave);
      - DarkRP's /drop: ArcCW gives the dropped weapon's attachments to the player (DarkRP's dropped
        weapon can't keep them), but the inventory keeps them on the weapon: taken back;
      - its ammo boxes: walking over one does not take it (as the game's ammo does not); Use puts its
        rounds into ammo boxes of the inventory (sv_generic.lua: ENT.AmmoType / ENT.AmmoCount).
--]]
local I = AdvInv

-- slot -> attachment installed on the weapon (its built-in slots left out)
local function installed(w)
    local t = {}
    for i, slot in pairs(w.Attachments or {}) do
        if isnumber(i) and istable(slot) and isstring(slot.Installed) and not slot.Internal then t[i] = slot.Installed end
    end
    return t
end

local function attachmentsOf(s)
    local t = {}
    for k, att in pairs(isstring(s) and util.JSONToTable(s) or {}) do
        local i = tonumber(k)
        if i and isstring(att) and ArcCW and ArcCW.AttachmentTable and ArcCW.AttachmentTable[att] then t[i] = att end
    end
    return t
end

table.insert(I.WeaponDataAdapters, {
    match = function(w) return w.ArcCW == true and istable(w.Attachments) and w.Attach ~= nil end,
    save = function(w)
        local t = {}
        for i, att in pairs(installed(w)) do t[tostring(i)] = att end
        return util.TableToJSON(t) -- (even empty: the item's loadout, not the client's autosave)
    end,
    load = function(w, s)
        local want = {}
        for i, att in pairs(attachmentsOf(s)) do
            if w.Attachments[i] then want[i] = att end
        end
        w:SetNWBool("ArcCW_DisableAutosave", true)
        local owner = w:GetOwner()
        if not IsValid(owner) then -- lying in the world: set, shown once networked
            for i, slot in pairs(w.Attachments) do
                if isnumber(i) and istable(slot) and not slot.Internal then slot.Installed = want[i] end
            end
            if w.NetworkWeapon then w:NetworkWeapon() end
            return
        end
        local ply = owner:IsPlayer() and owner or nil
        -- what the weapon has and the item hasn't: off, not into the player's attachments
        for i, att in pairs(installed(w)) do
            if want[i] ~= att then
                w:Detach(i, true, true, true)
                if ply then ArcCW:PlayerTakeAtt(ply, att, 1) end
            end
        end
        local pending = table.GetKeys(want)
        table.sort(pending)
        for _ = 1, #pending do -- again for the ones that need another attachment first
            local left = {}
            for _, i in ipairs(pending) do
                if w.Attachments[i].Installed ~= want[i] then
                    if ply then ArcCW:PlayerGiveAtt(ply, want[i], 1) end
                    w:Attach(i, want[i], true, true)
                    if w.Attachments[i].Installed ~= want[i] then
                        if ply then ArcCW:PlayerTakeAtt(ply, want[i], 1) end -- refused: not kept
                        left[#left + 1] = i
                    end
                end
            end
            if #left == 0 or #left == #pending then break end
            pending = left
        end
        if w.AdjustAtts then w:AdjustAtts() end
        if ply then ArcCW:PlayerSendAttInv(ply) end
    end,
})

-- DarkRP's /drop: the attachments ArcCW gave the player stay on the dropped weapon (sv_darkrp.lua)
hook.Add("onDarkRPWeaponDropped", "AdvInv_ArcCW", function(ply, ent, wep)
    if not (ArcCW and IsValid(wep) and wep.ArcCW) then return end
    timer.Simple(0, function() -- (after ArcCW's hook and the inventory's)
        if not (IsValid(ply) and IsValid(ent) and ent.AdvInvExtra) then return end
        for _, att in pairs(attachmentsOf(ent.AdvInvExtra)) do ArcCW:PlayerTakeAtt(ply, att, 1) end
        ArcCW:PlayerSendAttInv(ply)
    end)
end)

-- Rounds ArcCW gives back to the reserve (unloading, a smaller magazine attached, an underbarrel
-- launcher taken off or unloaded when holstered) go into the inventory's ammo boxes: the reserve is the
-- boxes (sv_containers.lua), rounds outside them would be gone at the next count.
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
        self.AdvInvAmmoWatch = true -- (the outer call only: Detach calls AdjustAtts)
        local before = reserves(o)
        local r = { pcall(f, self, ...) }
        self.AdvInvAmmoWatch = nil
        if IsValid(o) then
            local gained = false
            for name, n in pairs(reserves(o)) do
                local diff = n - (before[name] or 0)
                if diff > 0 then
                    I.GiveRounds(o, name, diff)
                    gained = true
                end
            end
            if gained then I.SyncAmmo(o) end
        end
        if not r[1] then error(r[2], 0) end
        return unpack(r, 2)
    end
end

hook.Add("PreRegisterSWEP", "AdvInv_ArcCW", function(swep, class)
    if class ~= "arccw_base" or swep.AdvInvArcCWPatched then return end
    for _, name in ipairs({ "Unload", "Detach", "AdjustAtts", "FinishHolster" }) do
        local f = rawget(swep, name)
        if isfunction(f) then swep[name] = gainsToBoxes(f) end
    end
    swep.AdvInvArcCWPatched = true
end)

-- its ammo boxes: not taken by walking over them (Use: into the inventory's ammo boxes)
local function setup()
    if not ArcCW then return end
    local pick = GetConVar("advinv_pickup_entities")
    for class in pairs(scripted_ents.GetList()) do
        if class == "arccw_ammo" or scripted_ents.IsBasedOn(class, "arccw_ammo") then
            local stored = scripted_ents.GetStored(class)
            local t = stored and stored.t
            local touch = t and rawget(t, "Touch")
            if touch and not rawget(t, "AdvInvTouch") then
                t.AdvInvTouch = touch
                t.Touch = function(self, ent, ...)
                    if IsValid(ent) and ent:IsPlayer() and pick and pick:GetBool() then return end
                    return touch(self, ent, ...)
                end
            end
        end
    end
end

hook.Add("InitPostEntity", "AdvInv_ArcCW", setup)
setup() -- Lua refresh
