AddCSLuaFile()

ENT.Base = "advinv_base_ammobox"
ENT.PrintName = AdvInv.T(".357 ammo", "Munitions .357")
ENT.Category = AdvInv.T("Inventory: Ammo", "Inventaire : munitions")
ENT.Spawnable = true
-- Icône du menu de spawn : celle des munitions HL2, fournie avec Garry's Mod.
ENT.IconOverride = "entities/item_ammo_357.png"

ENT.Model = "models/items/357ammo.mdl"
ENT.Ammo = "357"
ENT.Rounds = 6
ENT.Capacity = 6
ENT.Mass = 3 -- encombrement (points)
