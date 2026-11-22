local done = ASYNC(20)
local I = AdvInv
local idOf = {}
for id, c in pairs(AdvInv.IDClass) do idOf[c] = id end
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
local out = {}
local function summary(items)
    local t = {}
    for _, it in ipairs(items) do t[#t + 1] = (AdvInv.IDClass[it.id] or "?") .. (it.c and ("[" .. it.c .. "]") or "") .. "(" .. (it.r or 0) .. ")" end
    table.sort(t)
    return table.concat(t, " ")
end
local function call(fn, ply, q)
    local real = { net.ReadUInt, net.ReadEntity, net.ReadString, net.ReadBool }
    local k = 0
    local function nxt() k = k + 1 return q[k] end
    net.ReadUInt, net.ReadEntity, net.ReadString, net.ReadBool = nxt, nxt, nxt, nxt
    local ok, a, b = pcall(fn, ply)
    net.ReadUInt, net.ReadEntity, net.ReadString, net.ReadBool = real[1], real[2], real[3], real[4]
    if not ok then return "ERROR " .. tostring(a) end
    return { a, b }
end
local H, ACT = I.ActHandlers, I.ACT
player.CreateNextBot("User")
timer.Simple(1, function()
    local p = player.GetBots()[1]
    I.SetDefaults(p)
    I.Store(p, { id = I.GENERIC_ENTITY, c = "item_healthkit" })
    I.Store(p, { id = I.GENERIC_ENTITY, c = "item_battery" })
    I.Store(p, { id = idOf.advinv_ammo_ar2, r = 5 }) -- a started box
    p:SetHealth(50) p:SetArmor(0)
    out.useKit = call(H[ACT.USE], p, { p, I.ContID.Uniform, 1 })
    out.afterKit = { hp = p:Health(), uniform = summary(I.Get(p, "Uniform")) }
    p:SetHealth(p:GetMaxHealth())
    -- battery is now index 1
    out.useBatteryFullHp = call(H[ACT.USE], p, { p, I.ContID.Uniform, 1 })
    out.afterBattery = { armor = p:Armor(), uniform = summary(I.Get(p, "Uniform")) }
    I.Store(p, { id = I.GENERIC_ENTITY, c = "item_healthvial" })
    out.vialNotNeeded = call(H[ACT.USE], p, { p, I.ContID.Uniform, #I.Get(p, "Uniform") })
    out.useAmmoBox = call(H[ACT.USE], p, { p, I.ContID.Uniform, 1 })
    -- unload: equipped AR2 with 25 rounds -> the 5-round box gets 15 (to 20), then a new box of 10
    I.Equip(p, { id = idOf.advinv_hl2_ar2, r = 25 })
    out.unloadEquipped = call(H[ACT.UNLOAD], p, { true, AdvInv.CategoryID.PrimaryWep })
    local wep = p:GetWeapon("weapon_ar2")
    out.afterUnloadEquipped = { clip = IsValid(wep) and wep:Clip1(), uniform = summary(I.Get(p, "Uniform")), reserve = p:GetAmmoCount("AR2") }
    -- unload a stored weapon item
    I.Store(p, { id = idOf.advinv_hl2_pistol, r = 12 })
    local idx
    for k, it in ipairs(I.Get(p, "Uniform")) do if it.id == idOf.advinv_hl2_pistol then idx = k end end
    out.unloadStored = call(H[ACT.UNLOAD], p, { false, p, I.ContID.Uniform, idx })
    out.afterUnloadStored = summary(I.Get(p, "Uniform"))
    out.unloadEmpty = call(H[ACT.UNLOAD], p, { false, p, I.ContID.Uniform, idx })
    timer.Simple(0.2, function()
        out.reserveAfterSync = { ar2 = p:GetAmmoCount("AR2"), pistol = p:GetAmmoCount("Pistol") }
        done(out)
    end)
end)
