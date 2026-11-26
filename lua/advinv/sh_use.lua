--[[
    Using items from the inventory, and unloading weapons (server: sv_use.lua).

    Consumables, by entity class (an registered item's class, or a generic item's class):
        AdvInv.Consumables["item_healthkit"] = { health = 25, sound = "items/smallmedkit1.wav" }
            health / armor  points given (up to the player's maximum)
            sound           played when used
    An registered item can also set ENT.Consumable = { ... } (same fields), or define
    ENT:OnUseItem(ply, item) -> true if it was used up (any effect).
    Hook (server): AdvInv_UseItem(ply, item) -> false to forbid.

    Unloading a weapon puts the rounds of its magazine back into ammo boxes of its ammunition (the
    started ones first, then new ones); an equipped weapon is unloaded the same way.
--]]
local I = AdvInv

I.Consumables = I.Consumables or {}
for class, d in pairs({
    item_healthkit = { health = 25, sound = "items/smallmedkit1.wav" },
    item_healthvial = { health = 10, sound = "items/smallmedkit1.wav" },
    item_battery = { armor = 15, sound = "items/battery_pickup.wav" },
}) do
    if I.Consumables[class] == nil then I.Consumables[class] = d end
end

-- How an item is used: the consumable table, or the item's own OnUseItem; nil if it can't be.
function I.UseOf(item)
    if not item then return end
    if I.IsGeneric(item.id) then
        if item.id == I.GENERIC_AMMO then
            local grenade = I.GrenadeOfAmmo and I.GrenadeOfAmmo(item.c)
            return grenade and { grenade = grenade } or nil -- in the hands (not used up here)
        end
        return item.id == I.GENERIC_ENTITY and I.Consumables[item.c] or nil
    end
    local t = I.EntTable(item.id)
    if not t then return end
    return t.Consumable or I.Consumables[t.ClassName] or (t.OnUseItem and { custom = true }) or nil
end

-- Ammo box item for an ammunition type: its registered ammo item (lowercase lookup), else a generic
-- ammo box of that type. -> id, class (nil if the type doesn't exist)
local boxFor
function I.AmmoBoxFor(ammo)
    if not ammo or ammo == "" then return end
    local id = I.RegisteredAmmoBox(ammo)
    if id then return id, nil end
    if game.GetAmmoID(ammo) ~= -1 then return I.GENERIC_AMMO, ammo end
end

function I.RegisteredAmmoBox(ammo)
    if not boxFor then
        boxFor = {}
        for id in pairs(AdvInv.IDClass or {}) do
            if id > 1 and not I.IsGeneric(id) then
                local info = I.Info(id)
                if info.isBox and info.ammo and not boxFor[string.lower(info.ammo)] then
                    boxFor[string.lower(info.ammo)] = id
                end
            end
        end
    end
    return boxFor[string.lower(ammo)]
end
hook.Add("AdvInv_ItemsInitialized", "AdvInv_AmmoBoxes", function() boxFor = nil end)

-- Ammunition type of a weapon item (nil for weapons without one).
function I.WeaponAmmo(id, c)
    local info = I.Info(id, c)
    if not info.isWeapon then return end
    local t = I.DefTable(id, c)
    local ammo = t and t.Ammo
    if (not ammo or ammo == "") and info.weaponClass then
        ammo = I.SwepAmmo(weapons.Get(info.weaponClass))
    end
    if ammo == "" then return end
    return ammo
end

-- Can this weapon be unloaded (rounds in it, and a box for its ammunition)?
function I.CanUnload(id, c, rounds)
    return (rounds or 0) > 0 and I.AmmoBoxFor(I.WeaponAmmo(id, c)) ~= nil
end
