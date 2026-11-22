AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

-- L'emplacement de cette catégorie est-il libre ? Un objet peut ajouter ses conditions
-- (les LVN demandent un casque qui les porte, par exemple).
function ENT:CanBeEquipped(ply)
    return ply:GetNW2Int(self.AdvInvCategory) <= 1
end

function ENT:createServerModel(target)
    local model = ents.Create("prop_dynamic")
    model:SetModel(self.Model)
    model:SetParent(target)
    model:AddEffects(EF_BONEMERGE)
    model:AddEffects(EF_BONEMERGE_FASTCULL)

    return model
end
