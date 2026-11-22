include("shared.lua")

ENT.entPanelName = "AdvInvPocketVestPanel"
ENT.droppable = "Vest"

function ENT:createCSModel(target)
    local model = baseclass.Get("advinv_base_gear").createCSModel(self, target)
    model:SetBodygroup(1, self.pocketID)
    return model
end
