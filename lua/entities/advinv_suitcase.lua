AddCSLuaFile()

-- Prop non riggé : valise portée en travers du dos, fixée sur l'os Spine2.
-- Décalage calculé d'après le dos de Barney ; à affiner avec advinv_attach_editor si besoin.
ENT.Base = "advinv_base_rucksack"
ENT.PrintName = AdvInv.T("Suitcase", "Valise")
ENT.Category = AdvInv.T("Inventory: Gear", "Inventaire : équipement")
ENT.Spawnable = true

ENT.AdvInvCategory = "Rucksack"
ENT.Model = "models/props_c17/suitcase001a.mdl"
ENT.MaxLoad = 100 -- capacité (points)
ENT.Attach = {
    bone = "ValveBiped.Bip01_Spine2",
    pos = Vector(0.99, -9.60, 0.00),
    ang = Angle(90.0, 0.9, 0.0),
    scale = 1,
}
ENT.Mass = 40 -- encombrement (points)
