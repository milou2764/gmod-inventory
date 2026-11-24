AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel(self.Model)
    AdvInv.SetupItemModel(self, self) -- gear drawn from a playermodel: its bodygroups, the rest hidden
    if self.PhysHull then
        -- that gear's convex hull, around the entity's origin (the gear's centre: ENT.ModelOrigin)
        self:PhysicsInitConvex(self.PhysHull)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:EnableCustomCollisions(true)
    else
        self:PhysicsInit(SOLID_VPHYSICS)
    end
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
    -- (items put on the ground by the inventory disappear after advinv_ground_item_time,
    -- sv_containers.lua; items spawned from the menu or placed by admins stay)
end

-- Touche Utiliser : l'équiper si son emplacement est libre, sinon le ranger (voir sv_containers.lua).
function ENT:Use(activator)
    if IsValid(activator) and activator:IsPlayer() then
        AdvInv.Use(activator, self)
    end
end
