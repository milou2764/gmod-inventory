--[[
    Ammo box of any ammunition type that has no registered ammo item (weapons of ARC9, TFA, CW 2.0,
    M9K...): a generic item (sh_generic.lua, I.GENERIC_AMMO) put back into the world. Its type
    is the NW string "AdvInvAmmo", its rounds the NW int "AdvInvRounds".
--]]
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "advinv_base_ammobox"
ENT.PrintName = AdvInv.T("Ammo box", "Boîte de munitions")
ENT.Spawnable = false
ENT.Model = "models/items/boxmrounds.mdl"
ENT.Rounds = 0
ENT.Capacity = 30
