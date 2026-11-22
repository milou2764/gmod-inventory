AddCSLuaFile()

-- Arme sans chargeur : ClipSize = -1. Les roquettes sont des objets de munitions
-- (advinv_ammo_rpg) rangés dans l'inventaire.
ENT.Base = "advinv_base_wep"
ENT.PrintName = AdvInv.T("Rocket launcher (HL2)", "Lance-roquettes (HL2)")
ENT.Category = AdvInv.T("Inventory: Weapons", "Inventaire : armes")
ENT.Spawnable = true
ENT.AdvInvCategory = "RocketLauncher"
-- Icône du menu de spawn : celle de l'arme HL2, fournie avec Garry's Mod.
ENT.IconOverride = "entities/weapon_rpg.png"

ENT.Model = "models/weapons/w_rocket_launcher.mdl"
ENT.WeaponClass = "weapon_rpg"
ENT.Ammo = "RPG_Round"
ENT.Rounds = 0
ENT.ClipSize = -1
ENT.Mass = 120 -- encombrement (points)
