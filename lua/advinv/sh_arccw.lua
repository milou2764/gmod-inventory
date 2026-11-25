--[[
    ArcCW's throwables are grenade items like the others (sh_grenades.lua): with arccw_equipmentammo
    on (its default), each grenade, flash, smoke... has an ammunition type of its own, named after the
    weapon (made by ArcCW on Initialize). One whose ammunition another grenade already uses (the game's
    "Grenade" with arccw_equipmentammo off) stays an ordinary weapon item.
--]]
local I = AdvInv

local function register()
    if not ArcCW then return end
    for _, t in ipairs(weapons.GetList()) do
        local class = t.ClassName
        -- (not its bases: arccw_base_nade is no grenade)
        local w = class and I.Grenades[class] == nil and not string.find(class, "base", 1, true) and weapons.Get(class)
        if w and w.ArcCW and (w.Throwing or w.Disposable) and not w.Singleton then
            local ammo = w.Primary and w.Primary.Ammo
            if isstring(ammo) and ammo ~= "" and string.lower(ammo) ~= "none" and game.GetAmmoID(ammo) ~= -1
                and not I.GrenadeOfAmmo(ammo) then
                I.Grenades[class] = ammo
            end
        end
    end
end

hook.Add("InitPostEntity", "AdvInv_ArcCWGrenades", register)
if ArcCW then register() end -- Lua refresh
