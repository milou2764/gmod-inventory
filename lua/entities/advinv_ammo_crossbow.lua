AddCSLuaFile()

ENT.Base = "advinv_base_ammobox"
ENT.PrintName = AdvInv.T("Crossbow bolts", "Carreaux d'arbalète")
ENT.Category = AdvInv.T("Inventory: Ammo", "Inventaire : munitions")
ENT.Spawnable = true
-- Icône du menu de spawn : celle des munitions HL2, fournie avec Garry's Mod.
ENT.IconOverride = "entities/item_ammo_crossbow.png"

ENT.Model = "models/items/crossbowrounds.mdl"
ENT.Ammo = "XBowBolt"
ENT.Rounds = 6
ENT.Capacity = 6
ENT.Mass = 12 -- encombrement (points)
