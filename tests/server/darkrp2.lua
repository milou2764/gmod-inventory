local done = ASYNC(10)
local I = AdvInv
local idOf = {}
for id, c in pairs(AdvInv.IDClass) do idOf[c] = id end
local p = player.GetBots()[1]
p:Spawn()
timer.Simple(0.3, function()
    I.SetDefaults(p)
    I.Equip(p, { id = idOf.advinv_hl2_ar2, r = 30 })
    local sw = ents.Create("spawned_weapon")
    sw:SetWeaponClass("weapon_ar2") sw:SetModel("models/weapons/w_irifle.mdl") sw:SetPos(p:GetPos() + Vector(40, 0, 20)) sw:Spawn()
    local item = I.ItemFromEntity(sw)
    sw:Remove()
    p:Kill()
    local dead = hook.Run("canDropWeapon", p, p:GetWeapon("weapon_ar2"))
    done({ shipmentClip = item and item.r, deadDropAR2 = dead })
end)
