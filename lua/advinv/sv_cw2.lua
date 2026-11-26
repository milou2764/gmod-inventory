--[[
    CW 2.0 (Customizable Weaponry 2.0, "Chuck's Weaponry 2.0" on the Workshop), when installed.
    Its weapons are generic items like any other (sh_generic.lua); this file joins CW 2.0's own
    features to the inventory:
      - cw_dropweapon on a weapon of the inventory drops it the inventory's way (out of its slot,
        lying in the world with its magazine and attachments), not as CW 2.0's dropped weapon,
        which would leave the weapon in its slot as well;
      - a CW 2.0 dropped weapon (cw_dropped_weapon) is taken with Use into the inventory, with its
        magazine and attachments;
      - the ammo of CW 2.0's ammo kits and crates goes into ammo boxes of the inventory (else it
        would sit in the reserve outside any box, and be lost at the next count).
    Attachments are kept in the item (sv_generic.lua, I.WeaponDataAdapters).
--]]
local I = AdvInv

local function pickWeapons()
    local cv = GetConVar("advinv_pickup_weapons")
    return cv and cv:GetBool()
end

local function slotOf(ply, class)
    for _, cat in ipairs(I.WeaponCat) do
        if I.SlotInfo(ply, cat).weaponClass == class then return cat end
    end
end

-- A CW 2.0 dropped weapon lying in the world -> its item.
I.EntityItemHandlers.cw_dropped_weapon = function(ent)
    if not (pickWeapons() and ent.GetWepClass) then return end
    local item = I.ItemForWeaponClass(ent:GetWepClass(), math.max(tonumber(ent.magSize) or 0, 0))
    if item and istable(ent.stringAttachmentIDs) and #ent.stringAttachmentIDs > 0 then
        local names = table.Copy(ent.stringAttachmentIDs)
        table.sort(names)
        item.x = util.TableToJSON(names)
    end
    return item
end

-- Picked up by a direct call of its Use (not through the Use key): the inventory takes it.
hook.Add("CW20_PreventCWWeaponPickup", "AdvInv_CW2", function(ent, ply)
    if not (IsValid(ply) and ply:IsPlayer() and I.ItemFromEntity(ent)) then return end
    I.Use(ply, ent)
    return true
end)

local function ammoCounts(ply)
    local t = {}
    for id = 1, 1024 do
        local name = game.GetAmmoName(id)
        if not name then break end
        t[name] = ply:GetAmmoCount(id)
    end
    return t
end

local function setup()
    local CW = CustomizableWeaponry
    if not CW then return end

    if CW.dropWeapon and not CW.AdvInvDrop then
        CW.AdvInvDrop = CW.dropWeapon
        CW.dropWeapon = function(self, ply, wep, ...)
            local w = wep or (IsValid(ply) and ply:GetActiveWeapon())
            if IsValid(w) and I.GrenadeAmmo(w:GetClass()) then return end -- grenades: dropped as items
            local cat = IsValid(ply) and IsValid(w) and slotOf(ply, w:GetClass())
            if cat then
                if w.disableDropping or not ply:Alive() then return end
                local may, why = I.MayLeaveSlot(ply, cat) -- (its job flag too)
                if not may then
                    if why then I.Tell(ply, why) end
                    return
                end
                local item = I.TakeOff(ply, cat)
                if item then I.SpawnItem(item, I.DropPos(ply)) end
                return
            end
            return CW.AdvInvDrop(self, ply, wep, ...)
        end
    end

    -- ammo kits and crates: what they put into the reserve goes into ammo boxes
    for class in pairs(scripted_ents.GetList()) do
        if class == "cw_ammo_ent_base" or scripted_ents.IsBasedOn(class, "cw_ammo_ent_base") then
            local stored = scripted_ents.GetStored(class)
            local t = stored and stored.t
            local use = t and rawget(t, "Use")
            if use and not rawget(t, "AdvInvUse") then
                t.AdvInvUse = use
                t.Use = function(self, activator, caller, ...)
                    if not (IsValid(activator) and activator:IsPlayer()) then return use(self, activator, caller, ...) end
                    local before = ammoCounts(activator)
                    local r = { use(self, activator, caller, ...) }
                    for name, n in pairs(ammoCounts(activator)) do
                        local gained = n - (before[name] or 0)
                        if gained > 0 then I.GiveRounds(activator, name, gained) end
                    end
                    return unpack(r)
                end
            end
        end
    end
end

-- Magazine and ammunition attachments empty the magazine into the reserve (cw_base's unloadWeapon,
-- a SetAmmo): those rounds go into ammo boxes, else the next count would erase them.
hook.Add("PreRegisterSWEP", "AdvInv_CW2", function(swep, class)
    if class ~= "cw_base" or rawget(swep, "AdvInvCW2Patched") then return end
    local unload = rawget(swep, "unloadWeapon")
    if isfunction(unload) then
        swep.unloadWeapon = function(self, ...)
            local owner, ammo = self.Owner, self.Primary and self.Primary.Ammo
            local before = IsValid(owner) and owner:IsPlayer() and isstring(ammo) and owner:GetAmmoCount(ammo)
            if not before then return unload(self, ...) end
            I.BeginGainConversion(owner)
            local r = { pcall(unload, self, ...) }
            local gained = IsValid(owner) and owner:GetAmmoCount(ammo) - before or 0
            if gained > 0 then I.GiveRounds(owner, ammo, gained, I.IsBoundJobWeapon and I.IsBoundJobWeapon(owner, self)) end
            I.EndGainConversion(owner, gained > 0 and { [ammo] = true } or nil)
            if not r[1] then error(r[2], 0) end
            return unpack(r, 2)
        end
    end
    swep.AdvInvCW2Patched = true
end)

-- A dying player's primed quick grenade falls without its ammunition being taken (its DoPlayerDeath
-- hook): one grenade item less, or the body would keep it too.
local function setupQuickGrenade()
    local q = CustomizableWeaponry and CustomizableWeaponry.quickGrenade
    if not q then return end
    for _, name in ipairs({ "createThrownGrenade", "createUnthrownGrenade" }) do
        local orig = q["AdvInvOrig_" .. name] or q[name]
        if isfunction(orig) then
            q["AdvInvOrig_" .. name] = orig
            q[name] = function(self, ply, ...)
                local nade = orig(self, ply, ...)
                if IsValid(nade) and IsValid(ply) and ply:IsPlayer() and not ply:Alive() and I.GrenadeDroppedAtDeath then
                    I.GrenadeDroppedAtDeath(ply, "Frag Grenades")
                end
                return nade
            end
        end
    end
end

hook.Add("InitPostEntity", "AdvInv_CW2", function() setup() setupQuickGrenade() end)
if CustomizableWeaponry then setup() setupQuickGrenade() end -- Lua refresh
