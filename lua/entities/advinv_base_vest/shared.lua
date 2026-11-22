ENT.Type = "anim"
ENT.Base = "advinv_base_gear"
-- A chest rig may take the front zone from carried weapons: set { front = true } on such vests.
ENT.BlocksCarryZones = { front = false }
ENT.PrintName = AdvInv.T("Tactical vest", "Gilet Tactique")
ENT.Category = AdvInv.T("Inventory: Gear", "Inventaire : équipement")

-- Modèle par défaut (jeu de base) : chaque objet définit son ENT.Model.
ENT.Model = "models/props_junk/cardboard_box004a.mdl"
ENT.Armor = 100
ENT.AdvInvCategory = "Vest"
