AddCSLuaFile()

-- Rigged on the head bone, but shown with ENT.Attach (same place as its bonemerge, see
-- tools/mount_check.py) so that it can be made bigger: at 1.17 it covers Kleiner's hair.
ENT.Base = "advinv_base_helmet"
ENT.PrintName = AdvInv.T("Top hat", "Haut-de-forme")
ENT.Category = AdvInv.T("Inventory: Gear", "Inventaire : équipement")
ENT.Spawnable = true

ENT.Model = "models/player/items/humans/top_hat.mdl"
ENT.Attach = {
    bone = "ValveBiped.Bip01_Head1",
    pos = Vector(-1.40, -1.63, 0.00),
    ang = Angle(0.0, -80.1, -90.0),
    scale = 1.17,
}
ENT.Armor = 0
ENT.Mass = 10 -- encombrement (points)
