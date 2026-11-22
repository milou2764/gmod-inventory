AddCSLuaFile()

ENT.Base = "advinv_base_ammobox"
ENT.PrintName = AdvInv.T("Shotgun shells", "Munitions de fusil à pompe")
ENT.Category = AdvInv.T("Inventory: Ammo", "Inventaire : munitions")
ENT.Spawnable = true
-- Icône du menu de spawn : celle des munitions HL2, fournie avec Garry's Mod.
ENT.IconOverride = "entities/item_box_buckshot.png"

ENT.Model = "models/items/boxbuckshot.mdl"
ENT.Ammo = "Buckshot"
ENT.Rounds = 20
ENT.Capacity = 20
ENT.Mass = 10 -- encombrement (points)
