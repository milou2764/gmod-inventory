AddCSLuaFile()

ENT.Base = "advinv_base_ammobox"
ENT.PrintName = AdvInv.T("SMG ammo", "Munitions SMG")
ENT.Category = AdvInv.T("Inventory: Ammo", "Inventaire : munitions")
ENT.Spawnable = true
-- Icône du menu de spawn : celle des munitions HL2, fournie avec Garry's Mod.
ENT.IconOverride = "entities/item_ammo_smg1.png"

ENT.Model = "models/items/boxmrounds.mdl"
ENT.Ammo = "SMG1"
ENT.Rounds = 45
ENT.Capacity = 45
ENT.Mass = 8 -- encombrement (points)
