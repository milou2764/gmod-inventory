local done = ASYNC(20)
local I = AdvInv
local idOf = {}
for id, c in pairs(AdvInv.IDClass) do idOf[c] = id end
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
local out = {}
local function summary(items)
    local t = {}
    for _, it in ipairs(items) do t[#t + 1] = (AdvInv.IDClass[it.id] or "?") .. "(" .. (it.r or 0) .. ")" end
    table.sort(t)
    return table.concat(t, " ")
end
local function call(fn, ply, q)
    local real = { net.ReadUInt, net.ReadEntity, net.ReadString, net.ReadBool }
    local k = 0
    local function nxt() k = k + 1 return q[k] end
    net.ReadUInt, net.ReadEntity, net.ReadString, net.ReadBool = nxt, nxt, nxt, nxt
    I.Actor = ply
    local ok, a, b = pcall(fn, ply)
    I.Actor = nil
    net.ReadUInt, net.ReadEntity, net.ReadString, net.ReadBool = real[1], real[2], real[3], real[4]
    if not ok then return "ERROR " .. tostring(a) end
    return { a, b }
end
-- the check that follows every item index in an action (I.ItemCheck: the item the client saw)
local function ck(holder, cid, index)
    local it = AdvInv.Get(holder, AdvInv.IDCont[cid])[index]
    return it and AdvInv.ItemCheck(it) or 0
end
local H, ACT = I.ActHandlers, I.ACT
local function stacks(class)
    local t = {}
    for _, e in ipairs(ents.FindByClass(class)) do t[#t + 1] = e:GetNWInt("AdvInvCount", 1) end
    return t
end
player.CreateNextBot("Stacker")
timer.Simple(1, function()
    local p = player.GetBots()[1]
    I.SetDefaults(p)
    p:SetPos(Vector(-2800, -1800, -140))
    p:SetEyeAngles(Angle(30, 0, 0))
    for _, e in ipairs(ents.FindByClass("advinv_ammo_ar2")) do e:Remove() end
    for _ = 1, 3 do I.Store(p, { id = idOf.advinv_ammo_ar2, r = 20 }) end
    out.drop3 = call(H[ACT.DROP], p, { p, I.ContID.Uniform, 1, ck(p, I.ContID.Uniform, 1), 3 })
    out.afterDrop3 = stacks("advinv_ammo_ar2")
    for _ = 1, 2 do I.Store(p, { id = idOf.advinv_ammo_ar2, r = 20 }) end
    out.drop2 = call(H[ACT.DROP], p, { p, I.ContID.Uniform, 1, ck(p, I.ContID.Uniform, 1), 2 })
    out.afterMerge = stacks("advinv_ammo_ar2")
    -- pick up: 40 points of pockets, 10 a box -> 4 taken, 1 stays
    local stack = ents.FindByClass("advinv_ammo_ar2")[1]
    I.PickupEntity(p, stack)
    out.afterPickup = { pockets = summary(I.Get(p, "Uniform")), ground = stacks("advinv_ammo_ar2") }
    -- split a box: 20 -> 15 + 5
    I.Set(p, "Uniform", { { id = idOf.advinv_ammo_ar2, r = 20 } })
    out.split = call(H[ACT.SPLIT], p, { p, I.ContID.Uniform, 1, ck(p, I.ContID.Uniform, 1), 5 })
    out.afterSplit = summary(I.Get(p, "Uniform"))
    out.splitTooMuch = call(H[ACT.SPLIT], p, { p, I.ContID.Uniform, 1, ck(p, I.ContID.Uniform, 1), 15 })
    -- a stack thrown into a crate
    local crate = ents.Create("advinv_crate") crate:SetPos(p:GetPos() + Vector(100, 0, 20)) crate:Spawn()
    local s = I.SpawnItem({ id = idOf.advinv_ammo_pistol, r = 18 }, crate:GetPos() + Vector(0, 0, 60), nil, 4)
    I.StoreEntityIn(crate, s)
    out.crate = { items = summary(I.Get(crate, "Storage")), groundLeft = IsValid(s) and not s.AdvInvStored }
    -- a stack of 2 pistols: Use equips one, one stays
    local w = I.SpawnItem({ id = idOf.advinv_hl2_pistol, r = 18 }, p:GetPos() + Vector(30, 0, 10), nil, 2)
    p.AdvInvUseDelay = 0
    I.Use(p, w)
    out.useStack = { equipped = p:GetNWInt("SecondaryWep") == idOf.advinv_hl2_pistol, groundCount = IsValid(w) and w:GetNWInt("AdvInvCount", 1) or 0 }
    crate:Remove()
    if IsValid(w) then w:Remove() end
    for _, e in ipairs(ents.FindByClass("advinv_ammo_ar2")) do e:Remove() end
    done(out)
end)
