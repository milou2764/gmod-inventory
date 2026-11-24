AddCSLuaFile()

-- Prop non riggé : fixé sur l'os de la tête (le modèle est couché sur le côté : redressé ici).
-- Pour les playermodels sans ajustement (cl_fits_data.lua) : celui de male_07 (tools/fit_items.py).
ENT.Base = "advinv_base_helmet"
ENT.PrintName = AdvInv.T("Barney's helmet", "Casque de Barney")
ENT.Category = AdvInv.T("Inventory: Gear", "Inventaire : équipement")
ENT.Spawnable = true

ENT.Model = "models/barneyhelmet.mdl"
ENT.Armor = 100
ENT.NVGsHolder = true
ENT.Attach = {
    bone = "ValveBiped.Bip01_Head1",
    pos = Vector(1.19, -0.48, -0.05),
    ang = Angle(0.0, -160.1, -90.0),
    scale = 1.12,
}
ENT.Mass = 40 -- encombrement (points)
