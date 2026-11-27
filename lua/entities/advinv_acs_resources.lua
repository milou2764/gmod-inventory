AddCSLuaFile()

-- Advanced Crafting System's resources as an inventory item (lua/advinv/sh_acs.lua, sv_acs.lua):
-- registered and spawnable only when that addon is installed (its model comes with it).
ENT.Base = "advinv_base_ammobox"
ENT.PrintName = AdvInv.T("Crafting resources", "Ressources d'artisanat")
ENT.Category = AdvInv.T("Inventory: Advanced Crafting System", "Inventaire : Advanced Crafting System")
ENT.Spawnable = false

ENT.Model = "models/ACS/BoxSmall.mdl"
ENT.Ammo = "advinv_acs_resources"
ENT.Rounds = 50
ENT.Capacity = 50 -- resources per bag
ENT.Mass = 3      -- encombrement (points)
