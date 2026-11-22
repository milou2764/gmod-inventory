local done = ASYNC(30)
local I = AdvInv
local idOf = {}
for id, c in pairs(AdvInv.IDClass) do idOf[c] = id end
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
local out = {}
local function summary(items)
    local t = {}
    for _, it in ipairs(items) do t[#t + 1] = (AdvInv.IDClass[it.id] or "?") .. (it.c and ("[" .. it.c .. "]") or "") end
    table.sort(t)
    return table.concat(t, " ")
end
-- feed a handler from a queue instead of the network
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
local H, A, ACT = I.ActHandlers, I.ADMIN, I.ACT
player.CreateNextBot("Admin") player.CreateNextBot("Target") player.CreateNextBot("Nobody")
timer.Simple(1, function()
    local adm, tgt, nob = player.GetBots()[1], player.GetBots()[2], player.GetBots()[3]
    adm:SetUserGroup("superadmin")
    for _, p in ipairs({ adm, tgt, nob }) do I.SetDefaults(p) end
    adm:SetPos(Vector(-2800, -1800, -140)) tgt:SetPos(Vector(-1000, 1000, -140))
    I.Equip(tgt, { id = idOf.advinv_hl2_ar2, r = 20 })
    I.Equip(tgt, { id = idOf.advinv_barney_helmet, a = 40 })
    for _ = 1, 3 do I.Store(tgt, { id = idOf.advinv_ammo_ar2, r = 30 }) end
    out.isAdmin = { admin = I.IsAdmin(adm), nobody = I.IsAdmin(nob) }
    out.nobodyView = call(H[ACT.ADMIN], nob, { A.VIEW, tgt })
    out.nobodyCanAccess = I.CanAccess(nob, tgt)
    out.view = call(H[ACT.ADMIN], adm, { A.VIEW, tgt })
    out.adminCanAccessFar = I.CanAccess(adm, tgt)
    -- move one ammo box from the target's uniform into the admin's uniform (MOVE action)
    out.move = call(H[ACT.MOVE], adm, { tgt, I.ContID.Uniform, 1, adm, I.ContID.Uniform, 1 })
    out.afterMove = { target = summary(I.Get(tgt, "Uniform")), admin = summary(I.Get(adm, "Uniform")) }
    out.delete = call(H[ACT.ADMIN], adm, { A.DELETE, tgt, I.ContID.Uniform, 1, 5 })
    out.afterDelete = summary(I.Get(tgt, "Uniform"))
    out.give = call(H[ACT.ADMIN], adm, { A.GIVE, tgt, idOf.advinv_ammo_pistol, "", 2 })
    out.giveWeapon = call(H[ACT.ADMIN], adm, { A.GIVE, tgt, I.GENERIC_WEAPON, "weapon_crowbar", 1 })
    out.afterGive = { uniform = summary(I.Get(tgt, "Uniform")), secondary = tgt:GetNWString("SecondaryWepClass") }
    out.take = call(H[ACT.ADMIN], adm, { A.SLOT_TAKE, tgt, AdvInv.CategoryID.PrimaryWep })
    out.afterTake = { targetPrimary = tgt:GetNWInt("PrimaryWep"), adminUniform = summary(I.Get(adm, "Uniform")) }
    out.slotDelete = call(H[ACT.ADMIN], adm, { A.SLOT_DELETE, tgt, AdvInv.CategoryID.Helmet })
    out.afterSlotDelete = tgt:GetNW2Int("Helmet")
    out.clear = call(H[ACT.ADMIN], adm, { A.CLEAR, tgt })
    out.afterClear = { uniform = #I.Get(tgt, "Uniform"), secondary = tgt:GetNWInt("SecondaryWep"), crowbar = IsValid(tgt:GetWeapon("weapon_crowbar")) }
    out.unview = call(H[ACT.ADMIN], adm, { A.UNVIEW })
    out.canAccessAfterUnview = I.CanAccess(adm, tgt)
    -- settings
    local set = net.Receivers["advinv_admin_set"]
    local before = GetConVar("advinv_death_drop"):GetString()
    call(function(p) set(0, p) end, nob, { "advinv_death_drop", "1" })
    out.nobodySet = GetConVar("advinv_death_drop"):GetString() == before
    call(function(p) set(0, p) end, adm, { "advinv_death_drop", "9" })
    out.adminSetClamped = GetConVar("advinv_death_drop"):GetString()
    call(function(p) set(0, p) end, adm, { "sv_cheats", "1" })
    out.notInList = GetConVar("sv_cheats"):GetString()
    call(function(p) set(0, p) end, adm, { "advinv_death_drop", before })
    done(out)
end)
