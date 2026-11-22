AddCSLuaFile()

-- Prop non riggé : masque à gaz de la Protection civile, fixé sur l'os de la tête.
-- Même repère que le casque de Barney (modèles faits pour aller ensemble), donc même décalage.
ENT.Base = "advinv_base_gear"
ENT.PrintName = AdvInv.T("Civil Protection mask", "Masque (Protection civile)")
ENT.Category = AdvInv.T("Inventory: Gear", "Inventaire : équipement")
ENT.Spawnable = true

ENT.AdvInvCategory = "Gasmask"
ENT.Model = "models/barneyhelmet_faceplate.mdl"
ENT.Attach = {
    bone = "ValveBiped.Bip01_Head1",
    pos = Vector(2.41, -1.51, -0.07),
    ang = Angle(0.0, -80.1, -90.0),
    scale = 1,
}
ENT.Mass = 15 -- encombrement (points)
