AddCSLuaFile()

-- Prop non riggé : fixé sur l'os de la tête.
-- Décalage calculé d'après la tête de Barney ; à affiner avec advinv_attach_editor si besoin.
ENT.Base = "advinv_base_helmet"
ENT.PrintName = AdvInv.T("Barney's helmet", "Casque de Barney")
ENT.Category = AdvInv.T("Inventory: Gear", "Inventaire : équipement")
ENT.Spawnable = true

ENT.Model = "models/barneyhelmet.mdl"
ENT.Armor = 100
ENT.NVGsHolder = true
ENT.Attach = {
    bone = "ValveBiped.Bip01_Head1",
    pos = Vector(2.41, -1.51, -0.07),
    ang = Angle(0.0, -80.1, -90.0),
    scale = 1,
}
ENT.Mass = 40 -- encombrement (points)
