--[[
    Workbench (sh_craft.lua): Use opens the crafting window; recipes with bench = true can only
    be made within 150 units of one. Spawned by admins.
--]]
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = AdvInv.T("Workbench", "Établi")
ENT.Category = AdvInv.T("Inventory: Furniture", "Inventaire : mobilier")
ENT.Model = "models/props_wasteland/controlroom_desk001b.mdl" -- (spawn menu icon)
ENT.Spawnable = true
ENT.DisableDuplicator = true -- its contents would be copied
ENT.AdminOnly = true

if SERVER then
    util.AddNetworkString("advinv_open_crafting")

    function ENT:Initialize()
        self:SetModel("models/props_wasteland/controlroom_desk001b.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    function ENT:Use(activator)
        if not (IsValid(activator) and activator:IsPlayer()) then return end
        if not AdvInv.CraftingEnabled() then
            if AdvInv.Tell then AdvInv.Tell(activator, AdvInv.L("craft_disabled")) end
            return
        end
        net.Start("advinv_open_crafting")
        net.Send(activator)
    end
else
    function ENT:Draw()
        self:DrawModel()
    end
end
