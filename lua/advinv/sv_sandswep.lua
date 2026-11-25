--[[
    Sandstorm SWEPs (the Workshop's "Sandstorm SWEP Base" and its packs: assault rifles, pistols,
    Ready or Not pistols...), when installed. Its weapons are generic items like any other
    (sh_generic.lua); this file joins the base's own features to the inventory:
      - the attachments and their skins travel with the item (I.WeaponDataAdapters, sv_generic.lua),
        with the magazine that goes with them (the clip stays as it was saved);
      - its spare magazines are the inventory's munitions. The base keeps spare magazines inside the
        weapon: it hands out 4 to 8 full ones with every new weapon and pulls the reserve into them.
        Here, for a player's weapon, they only show the reserve, which is the ammo boxes
        (sv_containers.lua): a reload takes its rounds from the reserve, so from the boxes, and the
        rounds of a magazine taken out (another magazine attached, a reload interrupted) go back into
        them. No free magazines, nothing hidden in the weapon.
    Weapons of NPCs and weapons lying in the world keep the base's own behaviour.
--]]
local I = AdvInv

local BASE = "weapon_sand_base"

---------------------------------------------------------------- attachments

table.insert(I.WeaponDataAdapters, {
    match = function(w) return w.IsSandSwep and w.GetAttData ~= nil and w.ApplyLoadout ~= nil end,
    save = function(w)
        return util.TableToJSON({ a = w:GetAttData() or "", s = w.GetAttSkins and w:GetAttSkins() or "" })
    end,
    load = function(w, s)
        local d = util.JSONToTable(s)
        if not istable(d) then return end
        local clip = w:Clip1()
        w:ApplyLoadout(tostring(d.a or ""), tostring(d.s or ""))
        -- the new magazine size recorded at once: else the base's Think would take this magazine
        -- out (its rounds into the spares) as when a player changes magazines
        w._lastMagKey = nil
        if w.UpdateMagSize then w:UpdateMagSize() end
        if w.GetMagSize then w:SetClip1(math.min(clip, w:GetMagSize() + (w.ChamberRound and 1 or 0))) end
    end,
})

---------------------------------------------------------------- spare magazines = the reserve

local function playerOwner(w)
    local o = w:GetOwner()
    if IsValid(o) and o:IsPlayer() and not w.Rocket and w:GetPrimaryAmmoType() >= 0 then return o end
end

local orig = {} -- the base's own functions

-- the spare magazines shown: the reserve in full magazines
local function mirror(w)
    local o = playerOwner(w)
    if not o or not orig.SetMags then return end
    local n = o:GetAmmoCount(w:GetPrimaryAmmoType())
    local size = math.max(w:GetMagSize(), 1)
    local mags = {}
    while n > 0 and w:HasMagRoom(#mags) do
        local f = math.min(n, size)
        mags[#mags + 1] = f
        n = n - f
    end
    orig.SetMags(w, mags)
end

-- rounds the base took from its spare magazines (a reload) or put back (a magazine taken out)
local function account(o, w, delta)
    local ammo = game.GetAmmoName(w:GetPrimaryAmmoType())
    if not ammo or delta == 0 then return end
    if delta < 0 then
        o:RemoveAmmo(-delta, ammo) -- the boxes are emptied by the reserve going down (sv_containers.lua)
    else
        I.GiveRounds(o, ammo, delta)
        I.SyncAmmo(o)
    end
end

local wrap = {}

function wrap.SetMags(f)
    return function(self, mags)
        local o = playerOwner(self)
        if not o or self.AdvInvMirroring then return f(self, mags) end
        local after = 0
        for _, r in ipairs(mags or {}) do
            if r > 0 then after = after + math.floor(r) end
        end
        account(o, self, after - self:GetSpareRounds())
        mirror(self)
    end
end

-- every 0.25 s while held, on deploy and on equip: the reserve stays in the boxes
function wrap.AbsorbReserveAmmo(f)
    return function(self, ...)
        if not playerOwner(self) then return f(self, ...) end
        mirror(self)
    end
end

-- given to a player (the inventory gives its weapons): its free magazines and what the base's own
-- session loadout does to them don't count; then the reserve
function wrap.Equip(f)
    return function(self, ply, ...)
        if not (IsValid(ply) and ply:IsPlayer()) then return f(self, ply, ...) end
        self.AdvInvMirroring = true
        local r = { f(self, ply, ...) }
        self.AdvInvMirroring = nil
        mirror(self)
        return unpack(r)
    end
end

-- a second weapon of a class the player has: its magazines are no munitions
function wrap.EquipAmmo(f)
    return function(self, ply, ...)
        if IsValid(ply) and ply:IsPlayer() then return end
        return f(self, ply, ...)
    end
end

-- another magazine attached: the one in the weapon comes out, its rounds back into the boxes (the
-- base would put them into its spares, up to their limit, and lose the rest)
function wrap.UpdateMagSize(f)
    return function(self, ...)
        local o = playerOwner(self)
        if not o then return f(self, ...) end
        local last = self._lastMagKey
        self._lastMagKey = nil
        f(self, ...) -- records the magazine, changes nothing
        if not last or self._lastMagKey == last then return end
        if self:IsReloading() then self:CancelReload() end
        local chambered = (self.ChamberRound and self:IsChambered()) and 1 or 0
        local loose = self:Clip1() - chambered
        self:SetClip1(chambered)
        local shared = SandSwep and SandSwep.BaseShared
        if self.SetReloadStage then self:SetReloadStage(shared and shared.STAGE_NONE or 0) end
        if self.SetReloadSaveTime then self:SetReloadSaveTime(0) end
        if loose > 0 then account(o, self, loose) end
        mirror(self)
    end
end

local function patch(t)
    if not istable(t) or t.AdvInvSandPatched then return end
    for name, make in pairs(wrap) do
        local f = rawget(t, name)
        if isfunction(f) then
            orig[name] = f
            t[name] = make(f)
        end
    end
    t.AdvInvSandPatched = true
end

-- the base registers after the inventory: patched as it registers (and at once on a Lua refresh)
hook.Add("PreRegisterSWEP", "AdvInv_SandSwep", function(swep, class)
    if class == BASE then patch(swep) end
end)
patch(weapons.GetStored(BASE))

-- dropped by a player: its magazines were only the player's reserve
hook.Add("PlayerDroppedWeapon", "AdvInv_SandSwep", function(_, wep)
    if IsValid(wep) and wep.IsSandSwep and wep.SetMagData then wep:SetMagData("") end
end)
