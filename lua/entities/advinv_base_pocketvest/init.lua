AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    baseclass.Get("advinv_base_gear").Initialize(self)
    self:SetBodygroup(1, self.pocketID)
end
