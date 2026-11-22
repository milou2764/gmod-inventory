AddCSLuaFile()

ENT.Base = "advinv_base_ammobox"
ENT.PrintName = AdvInv.T("Rocket", "Roquette")
ENT.Category = AdvInv.T("Inventory: Ammo", "Inventaire : munitions")
ENT.Spawnable = true
-- Icône du menu de spawn : celle des munitions HL2, fournie avec Garry's Mod.
ENT.IconOverride = "entities/item_rpg_round.png"

ENT.Model = "models/weapons/w_missile_closed.mdl"
ENT.Ammo = "RPG_Round"
ENT.Rounds = 1
ENT.Capacity = 3
ENT.Mass = 60 -- encombrement (points)
