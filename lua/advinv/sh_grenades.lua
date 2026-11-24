--[[
    Grenades are items, not weapons in a slot. A grenade is one round of its ammunition type (a
    generic ammo item of size 1, named and shown like the grenade): they are stored and stacked like
    any item, taken from the ground with Use, and right-click > Use puts the grenade weapon in the
    hands. The player has as many grenade items as grenades (in reserve + loaded in the weapon):
    each one thrown takes an item away, and the weapon goes when the last one is gone (sv_grenades.lua).

    Other grenades (shared): AdvInv.Grenades["weapon_class"] = "ammo type".
--]]
local I = AdvInv

I.Grenades = I.Grenades or {}
for class, ammo in pairs({
    weapon_frag = "Grenade",                 -- Half-Life 2
    cw_frag_grenade = "Frag Grenades",       -- CW 2.0
    cw_flash_grenade = "Flash Grenades",
    cw_smoke_grenade = "Smoke Grenades",
}) do
    if I.Grenades[class] == nil then I.Grenades[class] = ammo end
end

-- Ammunition type of a grenade weapon, or nil.
function I.GrenadeAmmo(class)
    return class and I.Grenades[class]
end

-- Grenade weapon of an ammunition type (any case), or nil.
function I.GrenadeOfAmmo(ammo)
    if not isstring(ammo) then return end
    local l = string.lower(ammo)
    for class, a in pairs(I.Grenades) do
        if string.lower(a) == l then return class end
    end
end
