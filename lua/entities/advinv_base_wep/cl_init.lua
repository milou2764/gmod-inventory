include("shared.lua")

ENT.entPanelName = "AdvInvWepPanel"

function ENT:unmount(target)
    local userid
    if target.UserID then
        userid = target:UserID()
    else
        userid = target:EntIndex()
    end
    AdvInv.MountedWeps[userid] = AdvInv.MountedWeps[userid] or {}
    local model = AdvInv.MountedWeps[userid][self.AdvInvCategory]
    if IsValid(model) and model.Remove then
        table.RemoveByValue(AdvInv.MountedWeps[userid], model)
        model:Remove()
    end
end
