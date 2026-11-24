ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.Spawnable = false
ENT.DisableDuplicator = true -- a copy would be a free item

function ENT:AdvInvRegisterModel()
    AdvInv.entityModels[self.ClassName] = self.Model
end
