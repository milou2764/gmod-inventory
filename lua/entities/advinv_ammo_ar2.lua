AddCSLuaFile()

ENT.Base = "advinv_base_ammobox"
ENT.PrintName = AdvInv.T("AR2 ammo", "Munitions AR2")
ENT.Category = AdvInv.T("Inventory: Ammo", "Inventaire : munitions")
ENT.Spawnable = true
-- Icône du menu de spawn : celle des munitions HL2, fournie avec Garry's Mod.
ENT.IconOverride = "entities/item_ammo_ar2.png"

ENT.Model = "models/items/combine_rifle_cartridge01.mdl"
ENT.Ammo = "AR2"
ENT.Rounds = 20
ENT.Capacity = 20
ENT.Mass = 10 -- encombrement (points)
