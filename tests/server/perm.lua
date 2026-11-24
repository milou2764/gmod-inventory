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
-- the permanent storages of storage.lua are left nowhere: other tests drop things where they stand
for _, cls in ipairs({ "advinv_crate", "advinv_bank", "advinv_loot_spawn" }) do
    for _, e in ipairs(ents.FindByClass(cls)) do I.RemovePermanent(e) e:Remove() end
end
sql.Query("DELETE FROM advinv_storage WHERE Map = " .. SQLStr(game.GetMap()))
return out
