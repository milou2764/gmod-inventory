include("shared.lua")

ENT.entPanelName = "AdvInvPocketVestPanel"
ENT.droppable = "Vest"

function ENT:createCSModel(target)
    local model = baseclass.Get("advinv_base_gear").createCSModel(self, target)
    if self.pocketID then model:SetBodygroup(1, self.pocketID) end
    return model
end
