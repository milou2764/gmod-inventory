ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.Spawnable = false

function ENT:AdvInvRegisterModel()
    AdvInv.entityModels[self.ClassName] = self.Model
end
