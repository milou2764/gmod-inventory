local I = AdvInv
local out = {}
for _, cls in ipairs({ "advinv_crate", "advinv_bank" }) do
    for _, e in ipairs(ents.FindByClass(cls)) do
        local t = {}
        local key = I.StoreKey(e, player.GetAll()[1])
        for _, it in ipairs(I.Get(e, "Storage")) do t[#t + 1] = AdvInv.IDClass[it.id] .. (it.c and ("[" .. it.c .. "]") or "") end
        out[#out + 1] = { class = cls, permanent = e:GetNWBool("AdvInvPermanent"), sync = e.AdvInvSyncName, frozen = IsValid(e:GetPhysicsObject()) and not e:GetPhysicsObject():IsMotionEnabled(), items = table.concat(t, " ") }
    end
end
return out
