AddCSLuaFile()

ENT.Base = "advinv_base_ammobox"
ENT.PrintName = AdvInv.T("SMG grenade", "Grenade de SMG")
ENT.Category = AdvInv.T("Inventory: Ammo", "Inventaire : munitions")
ENT.Spawnable = true
-- Icône du menu de spawn : celle des munitions HL2, fournie avec Garry's Mod.
ENT.IconOverride = "entities/item_ammo_smg1_grenade.png"

ENT.Model = "models/items/ar2_grenade.mdl"
ENT.Ammo = "SMG1_Grenade"
ENT.Rounds = 1
ENT.Capacity = 3
ENT.Mass = 10 -- encombrement (points)
