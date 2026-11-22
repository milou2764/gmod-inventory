AddCSLuaFile()

-- Prop non riggé : seau retourné, fixé sur l'os de la tête.
-- Décalage calculé d'après la tête de Barney ; à affiner avec advinv_attach_editor si besoin.
ENT.Base = "advinv_base_helmet"
ENT.PrintName = AdvInv.T("Bucket", "Seau")
ENT.Category = AdvInv.T("Inventory: Gear", "Inventaire : équipement")
ENT.Spawnable = true

ENT.Model = "models/props_junk/metalbucket01a.mdl"
ENT.Armor = 25
ENT.Attach = {
    bone = "ValveBiped.Bip01_Head1",
    pos = Vector(2.53, -0.75, -0.07),
    ang = Angle(90.0, -170.1, 0.0),
    scale = 0.7,
}
ENT.Mass = 30 -- encombrement (points)
