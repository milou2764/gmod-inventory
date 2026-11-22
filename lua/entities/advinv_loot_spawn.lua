--[[
    Loot spawn (sh_storage.lua): an invisible point where a random item of a loot table appears,
    and appears again AdvInvSpawnEvery seconds after it was taken. Placed and set from the admin menu
    (Loot spawns), saved with the map; admins see the points while that tab is open.
--]]
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Loot spawn"
ENT.Spawnable = false

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/hunter/plates/plate.mdl")
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
        self:DrawShadow(false)
        self.AdvInvNextSpawn = CurTime() + 2
    end

    function ENT:UpdateTransmitState()
        return TRANSMIT_ALWAYS
    end

    function ENT:Think()
        local I = AdvInv
        local item = self.AdvInvSpawned
        local taken = not IsValid(item) or item:GetPos():DistToSqr(self:GetPos()) > 64 * 64
        if taken then
            if self.AdvInvWaiting == nil then
                self.AdvInvWaiting = true
                self.AdvInvNextSpawn = math.max(self.AdvInvNextSpawn or 0, CurTime() + (self.AdvInvSpawnEvery or I.Config.LootSpawnEvery))
                if not self.AdvInvEverSpawned then self.AdvInvNextSpawn = CurTime() + 2 end
            end
            if CurTime() >= (self.AdvInvNextSpawn or 0) then
                local items = I.RollLoot(self.AdvInvLoot or "supplies")
                local it = items[1]
                if it then
                    self.AdvInvSpawned = I.SpawnItem(it, self:GetPos() + Vector(0, 0, 8))
                    if IsValid(self.AdvInvSpawned) then I.GroundItems[self.AdvInvSpawned] = nil end -- stays until taken
                    self.AdvInvEverSpawned = true
                end
                self.AdvInvWaiting = nil
                self.AdvInvNextSpawn = CurTime() + (self.AdvInvSpawnEvery or I.Config.LootSpawnEvery)
            end
        else
            self.AdvInvWaiting = nil
        end
        self:NextThink(CurTime() + 5)
        return true
    end
else
    -- seen only by admins while the admin menu's Loot spawns tab is open (cl_storage.lua)
    function ENT:Draw() end
end
