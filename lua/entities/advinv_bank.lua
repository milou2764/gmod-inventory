--[[
    Bank (sh_storage.lua): every bank opens the same personal store of the player who uses it
    (per character with a character system), kept between sessions. Capacity:
    AdvInv.Config.BankLoad. Spawned by admins; make it permanent from the context menu.
--]]
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = AdvInv.T("Bank locker", "Casier de banque")
ENT.Category = AdvInv.T("Inventory: Furniture", "Inventaire : mobilier")
ENT.Model = "models/props_c17/lockers001a.mdl" -- (spawn menu icon)
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.AdvInvStorage = true

function ENT:StorageTitle()
    return AdvInv.L("bank_title")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_c17/lockers001a.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        self.AdvInvPersonal = true
        self.AdvInvSyncName = "bank"
        self:SetNWBool("AdvInvPersonal", true)
        self:SetNWString("AdvInvSync", "bank")
        self:SetNWInt("AdvInvCap", AdvInv.Config.BankLoad)
    end

    function ENT:Use(activator)
        AdvInv.StorageUse(self, activator)
    end
else
    function ENT:Draw()
        self:DrawModel()
    end
end
