local done = ASYNC(45)
local I = AdvInv
local idOf = {}
for id, c in pairs(AdvInv.IDClass) do idOf[c] = id end
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
for _, cls in ipairs({ "advinv_crate", "advinv_bank", "advinv_loot_spawn" }) do
    for _, e in ipairs(ents.FindByClass(cls)) do I.RemovePermanent(e) e:Remove() end
end
-- (and those of earlier runs not spawned yet: they come back 2 s after the map loads)
sql.Query("DELETE FROM advinv_storage WHERE Map = " .. SQLStr(game.GetMap()))
sql.Query("DELETE FROM advinv_stores")
I.Stores = {}
local out = {}
local function summary(items)
    local t = {}
    for _, it in ipairs(items) do t[#t + 1] = (AdvInv.IDClass[it.id] or "?") .. (it.c and ("[" .. it.c .. "]") or "") end
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
local H, ACT = I.ActHandlers, I.ACT
local setR, codeR = net.Receivers["advinv_storage_set"], net.Receivers["advinv_storage_code"]
local function spawn(class, pos)
    local e = ents.Create(class) e:SetPos(pos) e:Spawn() e:Activate()
    return e
end
player.CreateNextBot("Alice") player.CreateNextBot("Bob") player.CreateNextBot("Boss")
timer.Simple(1, function()
    local a, b, boss = player.GetBots()[1], player.GetBots()[2], player.GetBots()[3]
    boss:SetUserGroup("superadmin")
    local base = Vector(-2800, -1800, -120)
    for k, p in ipairs({ a, b, boss }) do I.SetDefaults(p) p:SetPos(base + Vector(0, 40 * k, -20)) end
    local function give(p) I.Store(p, { id = idOf.advinv_ammo_ar2, r = 20 }) end
    -- shared crates
    local c1, c2 = spawn("advinv_crate", base + Vector(60, 0, 0)), spawn("advinv_crate", base + Vector(60, 80, 0))
    call(function(p) setR(0, p) end, boss, { c1, "sync", "depot" })
    call(function(p) setR(0, p) end, boss, { c2, "sync", "depot" })
    give(a)
    out.moveIntoShared = call(H[ACT.MOVE], a, { a, I.ContID.Uniform, 1, c1, I.ContID.Storage, 1 })
    out.sharedSeenInOther = summary(I.Get(c2, "Storage"))
    -- non-admin can't change settings
    call(function(p) setR(0, p) end, a, { c1, "sync", "hack" })
    out.nonAdminSync = c1.AdvInvSyncName
    -- personal crate
    local pc = spawn("advinv_crate", base + Vector(-60, 0, 0))
    call(function(p) setR(0, p) end, boss, { pc, "personal", "1" })
    give(a)
    out.movePersonal = call(H[ACT.MOVE], a, { a, I.ContID.Uniform, 1, pc, I.ContID.Storage, 1 })
    out.personal = { alice = summary(I.Get(pc, "Storage", a)), bob = summary(I.Get(pc, "Storage", b)) }
    -- bank: two lockers, same store for the same player
    local b1, b2 = spawn("advinv_bank", base + Vector(0, -80, 0)), spawn("advinv_bank", base + Vector(0, -160, 0))
    give(b)
    out.bankMove = call(H[ACT.MOVE], b, { b, I.ContID.Uniform, 1, b1, I.ContID.Storage, 1 })
    out.bank = { bobInOther = summary(I.Get(b2, "Storage", b)), aliceInOther = summary(I.Get(b2, "Storage", a)), cap = I.MaxLoad(b2, "Storage") }
    -- lock + code (Alice owns the crate)
    local lc = spawn("advinv_crate", base + Vector(60, -80, 0))
    lc:SetNWString("AdvInvOwner", a:SteamID64() or "")
    out.ownerIsAlice = { I.IsStorageOwner(a, lc), I.IsStorageOwner(b, lc) }
    call(function(p) setR(0, p) end, b, { lc, "locked", "1" })
    out.bobCantLock = lc:GetNWBool("AdvInvLocked")
    call(function(p) setR(0, p) end, a, { lc, "locked", "1" })
    call(function(p) setR(0, p) end, a, { lc, "code", "1234" })
    b:SetPos(lc:GetPos() + Vector(0, 40, 0))
    out.lock = { locked = lc:GetNWBool("AdvInvLocked"), bobAccess = I.CanAccess(b, lc), aliceAccess = I.CanAccess(a, lc) or "far", bossAccess = I.CanOpenLocked(boss, lc) }
    b.AdvInvCodeWait = 0
    call(function(p) codeR(0, p) end, b, { lc, "0000" })
    out.wrongCode = I.CanAccess(b, lc)
    b.AdvInvCodeWait = 0
    call(function(p) codeR(0, p) end, b, { lc, "1234" })
    out.rightCode = I.CanAccess(b, lc)
    -- loot crate and loot spawn
    local loot = spawn("advinv_crate", base + Vector(120, 0, 0))
    call(function(p) setR(0, p) end, boss, { loot, "loot", "medical" })
    local ls = spawn("advinv_loot_spawn", base + Vector(160, 0, -10))
    ls.AdvInvLoot = "weapons"
    ls.AdvInvSpawnEvery = 10
    -- permanent: the shared crate c1 and a normal crate with contents
    local keep = spawn("advinv_crate", base + Vector(200, 0, 0))
    I.Set(keep, "Storage", { { id = idOf.advinv_ammo_357, r = 6 }, { id = I.GENERIC_ENTITY, c = "item_battery" } })
    local rowsBefore = tonumber(sql.QueryValue("SELECT COUNT(*) FROM advinv_storage WHERE Map = " .. SQLStr(game.GetMap()))) or 0
    call(function(p) setR(0, p) end, boss, { keep, "permanent", "1" })
    call(function(p) setR(0, p) end, boss, { c1, "permanent", "1" })
    call(function(p) setR(0, p) end, boss, { b1, "permanent", "1" })
    -- rows this run added (the database keeps the crates of earlier runs: they are permanent)
    out.permanentRows = (tonumber(sql.QueryValue("SELECT COUNT(*) FROM advinv_storage WHERE Map = " .. SQLStr(game.GetMap()))) or 0) - rowsBefore
    timer.Simple(17, function()
        out.lootCrate = summary(I.Get(loot, "Storage"))
        out.lootSpawn = IsValid(ls.AdvInvSpawned) and ls.AdvInvSpawned:GetClass() or "none"
        timer.Simple(4, function()
            out.storesSaved = tonumber(sql.QueryValue("SELECT COUNT(*) FROM advinv_stores"))
            done(out)
        end)
    end)
end)
