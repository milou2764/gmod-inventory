ENT.Type = "anim"
ENT.Base = "advinv_base_gear"
ENT.Category = AdvInv.T("Inventory: Gear", "Inventaire : équipement")
ENT.Spawnable = false

-- Modèle par défaut (jeu de base) : chaque objet définit son ENT.Model.
ENT.Model = "models/props_junk/cardboard_box004a.mdl"
-- Body zones this gear takes from carried weapons (sh_carry.lua): a backpack covers the back.
-- (the back carry; sling arms stays: the rifle hangs from the shoulder, beside the pack)
ENT.BlocksCarryZones = { back = true }
ENT.PrintName = AdvInv.T("Backpack", "Sac à dos")
ENT.Capacity = 10
