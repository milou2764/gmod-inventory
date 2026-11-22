AddCSLuaFile()

ENT.Base = "advinv_base_wep"
ENT.PrintName = AdvInv.T("Crossbow (HL2)", "Arbalète (HL2)")
ENT.Category = AdvInv.T("Inventory: Weapons", "Inventaire : armes")
ENT.Spawnable = true
ENT.AdvInvCategory = "PrimaryWep"
-- Icône du menu de spawn : celle de l'arme HL2, fournie avec Garry's Mod.
ENT.IconOverride = "entities/weapon_crossbow.png"

ENT.Model = "models/weapons/w_crossbow.mdl"
ENT.WeaponClass = "weapon_crossbow"
ENT.Ammo = "XBowBolt"
ENT.Rounds = 1
ENT.ClipSize = 1
ENT.Mass = 80 -- encombrement (points)
