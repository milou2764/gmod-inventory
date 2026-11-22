AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel(self.Model)
    self:PhysicsInit(SOLID_VPHYSICS)
    if not IsValid(self:GetPhysicsObject()) then
        -- Modèle sans collision (.phy) : boîte autour du modèle, ou ENT.PhysBox = { mins, maxs }.
        local mins, maxs = self:GetModelBounds()
        if self.PhysBox then
            mins, maxs = self.PhysBox[1], self.PhysBox[2]
        end
        if (maxs - mins):Length() < 1 then
            mins, maxs = Vector(-4, -4, -4), Vector(4, 4, 4)
        end
        self:PhysicsInitBox(mins, maxs)
    end
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    self:PhysWake()
    self:SetUseType(SIMPLE_USE)
    -- un objet posé au sol disparaît au bout de 30 s, sauf s'il contient quelque chose
    timer.Simple(30, function()
        if IsValid(self) and not (self.AdvInvContents and #self.AdvInvContents > 0) then
            self:Remove()
        end
    end)
end

-- Touche Utiliser : l'équiper si son emplacement est libre, sinon le ranger (voir sv_containers.lua).
function ENT:Use(activator)
    if IsValid(activator) and activator:IsPlayer() then
        AdvInv.Use(activator, self)
    end
end
