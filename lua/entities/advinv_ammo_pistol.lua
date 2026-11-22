AddCSLuaFile()

ENT.Base = "advinv_base_ammobox"
ENT.PrintName = AdvInv.T("9 mm ammo", "Munitions 9 mm")
ENT.Category = AdvInv.T("Inventory: Ammo", "Inventaire : munitions")
ENT.Spawnable = true
-- Icône du menu de spawn : celle des munitions HL2, fournie avec Garry's Mod.
ENT.IconOverride = "entities/item_ammo_pistol.png"

ENT.Model = "models/items/boxsrounds.mdl"
ENT.Ammo = "Pistol"
ENT.Rounds = 20
ENT.Capacity = 20
ENT.Mass = 4 -- encombrement (points)
