AddCSLuaFile()

-- Prop non riggé : porté dans le dos, fixé sur l'os Spine2.
-- Décalage calculé d'après le dos de Barney ; à affiner avec advinv_attach_editor si besoin.
ENT.Base = "advinv_base_rucksack"
ENT.PrintName = AdvInv.T("Jetpack (backpack)", "Jetpack (sac)")
ENT.Category = AdvInv.T("Inventory: Gear", "Inventaire : équipement")
ENT.Spawnable = true

ENT.AdvInvCategory = "Rucksack"
ENT.Model = "models/thrusters/jetpack.mdl"
ENT.MaxLoad = 40 -- capacité (points)
ENT.Attach = {
    bone = "ValveBiped.Bip01_Spine2",
    pos = Vector(-1.48, -6.82, 0.54),
    ang = Angle(0.0, -89.1, -90.0),
    scale = 1,
}
ENT.Mass = 80 -- encombrement (points)
