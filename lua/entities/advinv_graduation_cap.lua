AddCSLuaFile()

-- Rigged on the head bone (with a swinging tassel), shown with ENT.Attach at the place of its
-- bonemerge so that it can be fitted to each playermodel (cl_fits_data.lua).
ENT.Base = "advinv_base_helmet"
ENT.PrintName = AdvInv.T("Graduation cap", "Chapeau de diplômé")
ENT.Category = AdvInv.T("Inventory: Gear", "Inventaire : équipement")
ENT.Spawnable = true

ENT.Model = "models/player/items/humans/graduation_cap.mdl"
ENT.Attach = {
    bone = "ValveBiped.Bip01_Head1",
    pos = Vector(-0.78, -1.46, 0.00),
    ang = Angle(0.0, -80.1, -90.0),
    scale = 1,
}
ENT.Armor = 0
ENT.Mass = 6 -- encombrement (points)
