--[[
    TacRP (Tactical RP Weapons and its packs: ExoOps, Scavenger's Spoils...), when installed. Its weapons
    are generic items like any other (sh_generic.lua reads their ammunition and magazine from SWEP.Ammo
    and SWEP.ClipSize, their slot from their type and menu slot); here, shared:
      - its throwables are grenade items like the others (sh_grenades.lua): each quick grenade with a
        weapon of its own and an ammunition type no other grenade uses (flashbang, smoke, gas, thermite,
        breaching charge, healing grenade). Its frag grenade uses the game's "Grenade": that one stays the
        Half-Life 2 grenade's (a grenade item; TacRP's quick-throw throws it all the same). C4 has no
        weapon to put in the hands: its charges stay ammunition boxes;
      - its weapons drawn on the body: the inventory draws the ones in its slots (carried, holstered),
        TacRP's own holster models are not drawn for those (no gun drawn twice).
    Server side: sv_tacrp.lua.
--]]
local I = AdvInv

I.WeaponCategory = I.WeaponCategory or {}
if I.WeaponCategory.tacrp_c4_detonator == nil then I.WeaponCategory.tacrp_c4_detonator = "SecondaryWep" end
-- its first aid kit is a tool, like the game's and JMod's medkits: not an inventory weapon
if I.WeaponBlacklist and I.WeaponBlacklist.tacrp_medkit == nil then I.WeaponBlacklist.tacrp_medkit = true end

local function register()
    if not (TacRP and istable(TacRP.QuickNades)) then return end
    for _, q in pairs(TacRP.QuickNades) do
        local class, ammo = istable(q) and q.GrenadeWep, istable(q) and q.Ammo
        if isstring(class) and isstring(ammo) and ammo ~= "" and not q.Singleton and not q.AdminOnly
            and I.Grenades[class] == nil and weapons.GetStored(class) and game.GetAmmoID(ammo) ~= -1
            and not I.GrenadeOfAmmo(ammo) then
            I.Grenades[class] = ammo
        end
    end
end

hook.Add("InitPostEntity", "AdvInv_TacRPGrenades", register)
if TacRP then register() end -- Lua refresh

if CLIENT then
    -- TacRP keeps the weapons to draw on the body in ply.TacRP_Holster (its PostPlayerDraw hook): the
    -- ones in the inventory's slots are the inventory's to draw
    hook.Add("PrePlayerDraw", "AdvInv_TacRPHolster", function(ply)
        local h = ply.TacRP_Holster
        if not istable(h) then return end
        for k, wep in pairs(h) do
            if IsValid(wep) then
                local class = wep:GetClass()
                for _, cat in ipairs(I.WeaponCat or {}) do
                    if ply:GetNWString(cat .. "Class", "") == class then
                        h[k] = nil -- (TacRP removes its model of it)
                        break
                    end
                end
            end
        end
    end)
end
