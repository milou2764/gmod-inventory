AddCSLuaFile()

ENT.Base = "advinv_base_ammobox"
ENT.PrintName = AdvInv.T("AR2 energy ball", "Boule d'énergie AR2")
ENT.Category = AdvInv.T("Inventory: Ammo", "Inventaire : munitions")
ENT.Spawnable = true
-- Icône du menu de spawn : celle des munitions HL2, fournie avec Garry's Mod.
ENT.IconOverride = "entities/item_ammo_ar2_altfire.png"

ENT.Model = "models/items/combine_rifle_ammo01.mdl"
ENT.Ammo = "AR2AltFire"
ENT.Rounds = 1
ENT.Capacity = 3
ENT.Mass = 10 -- encombrement (points)
