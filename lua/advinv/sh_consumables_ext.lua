--[[
    Consumables of other addons that work like grenades: a weapon to hold, an ammunition type of its
    own, one round used up per use, the weapon gone with the last one. The inventory treats them as it
    treats grenades (sh_grenades.lua): one item per use, stored and stacked like any item, right-click >
    Use puts the weapon in the hands, each one used takes an item away. Registered when the addon is
    installed (its weapon and its ammunition exist) and no other weapon already uses that ammunition.
      - No More Room in Hell consumables (Workshop 3297936273): bandage, first aid kit, gene therapy,
        Phalanx pills;
      - S.T.A.L.K.E.R. 2 Consumables (Workshop 3426614364): medkits, bandage, antirad, pills, food and
        drinks (14). Its bandage and No More Room in Hell's use the same ammunition ("bandage"): with both
        installed, the bandage items are the first one's, the other stays an ordinary weapon.
    Throwables of weapon packs with a munition of their own, the same way: Metro 2033 Weapon's grenade
    (Workshop 3030181128), S.T.A.L.K.E.R. STCoP's F1 and RGD-5 (2808355959), the S.T.A.L.K.E.R. TFA
    pack's grenade, mine and bolts (3357280711). (Throwables that use the game's "Grenade" munition,
    ASTW2's, NC SWEPs', share the Half-Life 2 grenade items: their addon pools them already.)
    (EFT Supply's food, drinks and medicine, Workshop 3845009964, have several uses in their own magazine:
    ordinary weapon items in a sidearm slot, their uses kept with the item, never unloaded: sh_use.lua
    I.UsesInMagazine.)
    Servers add theirs (shared): AdvInv.ConsumableWeapons["weapon_class"] = "ammo type".
--]]
local I = AdvInv

I.ConsumableWeapons = I.ConsumableWeapons or {}
for class, ammo in pairs({
    weapon_nmrih_bandage = "bandage", weapon_nmrih_medkit = "medkit",
    weapon_nmrih_genetherapy = "genetherapy", weapon_nmrih_phalanx = "phalanx",
    weapon_stalker2_antirad = "antirad", weapon_stalker2_bandage = "bandage", weapon_stalker2_bread = "bread",
    weapon_stalker2_canned = "canned", weapon_stalker2_energy = "energy", weapon_stalker2_medkit = "medkit_general",
    weapon_stalker2_medkit_army = "medkit_army", weapon_stalker2_medkit_scientific = "medkit_scientific",
    weapon_stalker2_milk = "milk", weapon_stalker2_pills_endurance = "enhancers",
    weapon_stalker2_pills_revitalis = "regenerator", weapon_stalker2_sausage = "sausage",
    weapon_stalker2_vodka = "vodka", weapon_stalker2_water = "water",
    w_metro_grenade = "metro_granate", weapon_cop_f1 = "COP_F1", weapon_cop_rgd5 = "COP_RGD5",
    tfa_st_gd5 = "st_ammo_gd5", tfa_st_mine = "st_ammo_mine", tfa_st_bolt = "st_ammo_bbolt",
}) do
    if I.ConsumableWeapons[class] == nil then I.ConsumableWeapons[class] = ammo end
end

local function register()
    for class, ammo in pairs(I.ConsumableWeapons) do
        if isstring(ammo) and I.Grenades[class] == nil and weapons.GetStored(class) and game.GetAmmoID(ammo) ~= -1
            and not I.GrenadeOfAmmo(ammo) then
            I.Grenades[class] = ammo
        end
    end
end

hook.Add("InitPostEntity", "AdvInv_ConsumableWeapons", register)
register() -- Lua refresh (and addons loaded before this file)
