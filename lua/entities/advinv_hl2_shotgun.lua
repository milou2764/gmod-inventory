AddCSLuaFile()

ENT.Base = "advinv_base_wep"
ENT.PrintName = AdvInv.T("Shotgun (HL2)", "Fusil à pompe (HL2)")
ENT.Category = AdvInv.T("Inventory: Weapons", "Inventaire : armes")
ENT.Spawnable = true
ENT.AdvInvCategory = "PrimaryWep"
-- Icône du menu de spawn : celle de l'arme HL2, fournie avec Garry's Mod.
ENT.IconOverride = "entities/weapon_shotgun.png"

ENT.Model = "models/weapons/w_shotgun.mdl"
ENT.WeaponClass = "weapon_shotgun"
ENT.Ammo = "Buckshot"
ENT.Rounds = 6
ENT.ClipSize = 6
ENT.Mass = 70 -- encombrement (points)
