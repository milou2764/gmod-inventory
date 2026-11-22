include("shared.lua")

function ENT:getGearModelPath()
    return self.Model
end

--[[
    Affichage de l'objet porté (voir AdvInv.MountGearModel dans lua/advinv/cl_gear.lua) :
    - sans ENT.Attach : bonemerge, pour un modèle riggé sur le squelette ValveBiped ;
    - avec ENT.Attach : n'importe quel prop, fixé sur un os avec un décalage.
--]]
function ENT:createCSModel(target)
    local modelPath = self:getGearModelPath()
    local model = ClientsideModel(modelPath)
    AdvInv.MountGearModel(model, target, self.Attach, self.BodyFit, self.ClassName)

    return model
end

function ENT:unmount(target)
    local userid
    if target.UserID then
        userid = target:UserID()
    else
        userid = target:EntIndex()
    end
    AdvInv.mountedGear[userid] = AdvInv.mountedGear[userid] or {}
    local model = AdvInv.mountedGear[userid][self.AdvInvCategory]
    if IsValid(model) and model.Remove then
        table.RemoveByValue(AdvInv.mountedGear[userid], model)
        model:Remove()
    end
end
