--[[
    Storage features, server side (sh_storage.lua): keyed stores (shared, personal, banks),
    permanent storages, locks and codes, loot tables and loot spawns.

    SQLite tables (created if missing, never dropped):
        advinv_stores   StoreKey, Data      contents of shared / personal stores and banks
        advinv_storage  UID, Map, Class, Pos, Ang, Data   permanent storages (settings, contents)
--]]
local I = AdvInv
local C = I.Config

util.AddNetworkString("advinv_open_storage")
util.AddNetworkString("advinv_storage_set")
util.AddNetworkString("advinv_storage_code")
util.AddNetworkString("advinv_loot_spawns")
util.AddNetworkString("advinv_loot_spawn_act")

I.StorageClasses.advinv_bank = true

sql.Query("CREATE TABLE IF NOT EXISTS advinv_stores (StoreKey TEXT PRIMARY KEY, Data TEXT)")
sql.Query("CREATE TABLE IF NOT EXISTS advinv_storage (UID TEXT PRIMARY KEY, Map TEXT, Class TEXT, Pos TEXT, Ang TEXT, Data TEXT)")

---------------------------------------------------------------- keyed stores

function I.IsKeyed(holder)
    return IsValid(holder) and (holder.AdvInvPersonal or (holder.AdvInvSyncName or "") ~= "") or false
end

-- A player's personal key: their character (character system), else their SteamID.
function I.PersonalID(ply)
    local cid = I.GetOwnerID(ply)
    if cid then return "c" .. cid end
    return ply:SteamID64() or ply:SteamID()
end

-- A storage's own key: its permanent UID, else one given once (never its entity index, which
-- another entity gets later).
local function keyUID(holder)
    holder.AdvInvKeyUID = holder.AdvInvUID or holder.AdvInvKeyUID or (os.time() .. "_" .. math.random(100000, 999999))
    return holder.AdvInvKeyUID
end

function I.StoreKey(holder, who)
    if not I.IsKeyed(holder) then return end
    local base = (holder.AdvInvSyncName or "") ~= "" and holder.AdvInvSyncName or ("u" .. keyUID(holder))
    if holder.AdvInvPersonal then
        if not (IsValid(who) and who:IsPlayer()) then return end
        return "p:" .. base .. ":" .. I.PersonalID(who)
    end
    return "s:" .. base
end

function I.LoadStore(key)
    local s = {}
    local v = sql.QueryValue("SELECT Data FROM advinv_stores WHERE StoreKey = " .. SQLStr(key))
    local data = v and util.JSONToTable(v)
    if istable(data) then
        I.StoreUnknown[key] = {}
        for cont, list in pairs(data) do
            I.StoreUnknown[key][cont] = {}
            s[cont] = I.UnpackItems(list, I.StoreUnknown[key][cont]) -- items of missing addons kept as saved
        end
    end
    return s
end
I.StoreUnknown = I.StoreUnknown or {}

local function withUnknown(packed, raw)
    for _, v in ipairs(raw or {}) do packed[#packed + 1] = v end
    return packed
end

local pendingKeys, pendingEnts = {}, {}

local function saveStores()
    for key in pairs(pendingKeys) do
        local s = I.Stores[key]
        if s then
            local data = {}
            local uk = I.StoreUnknown[key] or {}
            for cont, items in pairs(s) do data[cont] = withUnknown(I.PackItems(items), uk[cont]) end
            sql.Query("REPLACE INTO advinv_stores (StoreKey, Data) VALUES (" .. SQLStr(key) .. ", " .. SQLStr(util.TableToJSON(data)) .. ")")
        end
    end
    pendingKeys = {}
end

-- Saved 3 s after the first change (not postponed by later ones).
function I.StoreChanged(key)
    pendingKeys[key] = true
    if not timer.Exists("AdvInv_StoresSave") then timer.Create("AdvInv_StoresSave", 3, 1, saveStores) end
end

---------------------------------------------------------------- permanent storages

local function settingsOf(ent)
    return {
        personal = ent.AdvInvPersonal or nil, sync = ent.AdvInvSyncName, cap = ent:GetNWInt("AdvInvCap", 0),
        loot = ent.AdvInvLoot, every = ent.AdvInvLootEvery, locked = ent:GetNWBool("AdvInvLocked") or nil,
        code = ent.AdvInvCode, owner = ent:GetNWString("AdvInvOwner", ""), spawnEvery = ent.AdvInvSpawnEvery,
    }
end

local function applySettings(ent, d)
    ent.AdvInvPersonal = d.personal and true or nil
    ent:SetNWBool("AdvInvPersonal", ent.AdvInvPersonal or false)
    ent.AdvInvSyncName = isstring(d.sync) and d.sync ~= "" and d.sync or nil
    ent:SetNWString("AdvInvSync", ent.AdvInvSyncName or "")
    ent:SetNWInt("AdvInvCap", tonumber(d.cap) or 0)
    ent.AdvInvLoot = isstring(d.loot) and d.loot ~= "" and d.loot or nil
    ent:SetNWString("AdvInvLoot", ent.AdvInvLoot or "")
    ent.AdvInvLootEvery = tonumber(d.every)
    ent:SetNWBool("AdvInvLocked", d.locked and true or false)
    ent.AdvInvCode = isstring(d.code) and d.code ~= "" and d.code or nil
    ent:SetNWBool("AdvInvHasCode", ent.AdvInvCode ~= nil)
    if isstring(d.owner) and d.owner ~= "" then ent:SetNWString("AdvInvOwner", d.owner) end
    ent.AdvInvSpawnEvery = tonumber(d.spawnEvery)
end

function I.SaveStorage(ent)
    if not (IsValid(ent) and ent.AdvInvUID) then return end
    local data = settingsOf(ent)
    if not I.IsKeyed(ent) then
        data.items = withUnknown(I.PackItems(ent.AdvInvData and ent.AdvInvData.Storage or {}), ent.AdvInvUnknownItems)
    end
    sql.Query("REPLACE INTO advinv_storage (UID, Map, Class, Pos, Ang, Data) VALUES (" ..
        SQLStr(ent.AdvInvUID) .. ", " .. SQLStr(game.GetMap()) .. ", " .. SQLStr(ent:GetClass()) .. ", " ..
        SQLStr(tostring(ent:GetPos())) .. ", " .. SQLStr(tostring(ent:GetAngles())) .. ", " ..
        SQLStr(util.TableToJSON(data)) .. ")")
end

local function saveEnts()
    for ent in pairs(pendingEnts) do I.SaveStorage(ent) end
    pendingEnts = {}
end

function I.StorageChanged(ent)
    pendingEnts[ent] = true
    if not timer.Exists("AdvInv_StorageSave") then timer.Create("AdvInv_StorageSave", 3, 1, saveEnts) end
    -- removed before the save (cleanup, remover): saved while it still exists
    ent:CallOnRemove("AdvInv_StorageSave", function(e)
        if pendingEnts[e] then
            pendingEnts[e] = nil
            I.SaveStorage(e)
        end
    end)
end

local function freeze(ent)
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
end

function I.MakePermanent(ent)
    ent.AdvInvUID = ent.AdvInvUID or keyUID(ent) -- the same key: stores keep their contents
    ent:SetNWBool("AdvInvPermanent", true)
    freeze(ent)
    I.SaveStorage(ent)
end

function I.RemovePermanent(ent)
    if ent.AdvInvUID then sql.Query("DELETE FROM advinv_storage WHERE UID = " .. SQLStr(ent.AdvInvUID)) end
    ent.AdvInvKeyUID = ent.AdvInvUID or ent.AdvInvKeyUID -- the same key: stores keep their contents
    ent.AdvInvUID = nil
    ent:SetNWBool("AdvInvPermanent", false)
end

local function loadPermanent()
    local rows = sql.Query("SELECT * FROM advinv_storage WHERE Map = " .. SQLStr(game.GetMap())) or {}
    for _, r in ipairs(rows) do
        local found = false
        for _, e in ipairs(ents.FindByClass(r.Class)) do
            if e.AdvInvUID == r.UID then found = true break end
        end
        if not found then
            local ent = ents.Create(r.Class)
            if IsValid(ent) then
                ent:SetPos(Vector(r.Pos))
                ent:SetAngles(Angle(r.Ang))
                ent.AdvInvUID = r.UID
                ent:Spawn()
                ent:Activate()
                freeze(ent)
                local d = util.JSONToTable(r.Data or "") or {}
                applySettings(ent, d)
                if istable(d.items) then
                    ent.AdvInvUnknownItems = {}
                    ent.AdvInvData = { Storage = I.UnpackItems(d.items, ent.AdvInvUnknownItems) }
                end
                ent:SetNWBool("AdvInvPermanent", true)
            end
        end
    end
end
I.LoadPermanentStorages = loadPermanent

hook.Add("InitPostEntity", "AdvInv_PermanentStorages", function() timer.Simple(2, loadPermanent) end)
hook.Add("PostCleanupMap", "AdvInv_PermanentStorages", function() timer.Simple(0.5, loadPermanent) end)
-- Everything pending is written before a map cleanup and at shutdown (any permanent storage,
-- ENT.AdvInvStorage entities and loot points included).
local function flush()
    saveStores()
    saveEnts()
end
hook.Add("PreCleanupMap", "AdvInv_Storages", flush)
hook.Add("ShutDown", "AdvInv_Storages", function()
    flush()
    for _, e in ipairs(ents.GetAll()) do
        if e.AdvInvUID then I.SaveStorage(e) end
    end
end)

-- Players don't move or remove permanent storages (admins do).
local function protected(ply, ent)
    if IsValid(ent) and ent:GetNWBool("AdvInvPermanent") and not I.IsAdmin(ply) then return false end
end
hook.Add("PhysgunPickup", "AdvInv_PermanentStorages", protected)
hook.Add("CanTool", "AdvInv_PermanentStorages", function(ply, tr) return protected(ply, tr.Entity) end)
hook.Add("CanProperty", "AdvInv_PermanentStorages", function(ply, prop, ent)
    if string.StartWith(prop, "advinv_") then return end
    return protected(ply, ent)
end)

---------------------------------------------------------------- owner, lock, code

local function setOwner(ply, ent)
    if IsValid(ent) and I.IsStorage(ent) and IsValid(ply) and ply:IsPlayer() then
        ent:SetNWString("AdvInvOwner", ply:SteamID64() or "")
    end
end
hook.Add("PlayerSpawnedSENT", "AdvInv_StorageOwner", setOwner)
hook.Add("playerBoughtCustomEntity", "AdvInv_StorageOwner", function(ply, _, ent) setOwner(ply, ent) end)

function I.CanOpenLocked(ply, ent)
    return I.IsAdmin(ply) or I.IsStorageOwner(ply, ent) or (ply.AdvInvCodes and ply.AdvInvCodes[ent]) or false
end

-- Use key on a storage: open it, or ask for its code.
function I.StorageUse(ent, ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    if ent:GetNWBool("AdvInvLocked") and not I.CanOpenLocked(ply, ent) then
        if ent.AdvInvCode then
            net.Start("advinv_storage_code")
            net.WriteEntity(ent)
            net.Send(ply)
        else
            I.Tell(ply, I.L("storage_locked"))
        end
        return
    end
    if not I.CanAccess(ply, ent) then return end
    net.Start("advinv_open_storage")
    net.WriteEntity(ent)
    net.Send(ply)
end

net.Receive("advinv_storage_code", function(_, ply)
    local ent, code = net.ReadEntity(), net.ReadString()
    if not (IsValid(ent) and I.IsStorage(ent) and ent.AdvInvCode) then return end
    if (ply.AdvInvCodeWait or 0) > CurTime() then return end
    ply.AdvInvCodeWait = CurTime() + 1
    if not (ply:Alive() and I.InReach(ply, ent)) then return end
    local wait = (ent.AdvInvCodeLockUntil or 0) - CurTime()
    if wait > 0 then
        I.Tell(ply, I.L("storage_code_wait", math.ceil(wait)))
        return
    end
    if code ~= ent.AdvInvCode then
        -- every 3 wrong codes (whoever tries): a wait, doubled each time, and the owner is told
        ent.AdvInvCodeFails = (ent.AdvInvCodeFails or 0) + 1
        if ent.AdvInvCodeFails % 3 == 0 then
            local t = math.min(30 * 2 ^ (ent.AdvInvCodeFails / 3 - 1), 3600)
            ent.AdvInvCodeLockUntil = CurTime() + t
            local owner = player.GetBySteamID64(ent:GetNWString("AdvInvOwner", ""))
            if IsValid(owner) and owner ~= ply then I.Tell(owner, I.L("storage_code_alert", ent:GetNWString("AdvInvSync", "") ~= "" and ent:GetNWString("AdvInvSync") or ent.PrintName or ent:GetClass())) end
            hook.Run("AdvInv_StorageCodeFailed", ply, ent, ent.AdvInvCodeFails)
        end
        I.Tell(ply, I.L("storage_wrong_code"))
        return
    end
    ent.AdvInvCodeFails = 0
    ply.AdvInvCodes = ply.AdvInvCodes or {}
    ply.AdvInvCodes[ent] = true
    I.StorageUse(ent, ply)
end)

---------------------------------------------------------------- settings

local ADMIN_KEYS = { permanent = true, personal = true, sync = true, cap = true, loot = true, every = true, spawnEvery = true }

net.Receive("advinv_storage_set", function(_, ply)
    -- at most 8 settings a second (the settings window sends one per change)
    local now = CurTime()
    if (ply.AdvInvSetWindow or 0) < now then ply.AdvInvSetWindow, ply.AdvInvSetCount = now + 1, 0 end
    ply.AdvInvSetCount = (ply.AdvInvSetCount or 0) + 1
    if ply.AdvInvSetCount > 8 then return end
    local ent, key, value = net.ReadEntity(), net.ReadString(), net.ReadString()
    if not (IsValid(ent) and (I.IsStorage(ent) or ent:GetClass() == "advinv_loot_spawn")) then return end
    local admin = I.IsAdmin(ply)
    if ADMIN_KEYS[key] and not admin then return end
    if not ADMIN_KEYS[key] and not (admin or I.IsStorageOwner(ply, ent)) then return end
    local on = value == "1"
    if key == "permanent" then
        if on then I.MakePermanent(ent) else I.RemovePermanent(ent) end
        return
    elseif key == "personal" or key == "sync" then
        if ent:GetClass() == "advinv_bank" then return end -- a bank is always the player's own
        -- viewers leave (what they see changes)
        for v in pairs(ent.AdvInvViewers or {}) do ent.AdvInvViewers[v] = nil end
        if key == "personal" then
            ent.AdvInvPersonal = on or nil
            ent:SetNWBool("AdvInvPersonal", on)
        else
            local name = string.sub(string.gsub(value, "[^%w_%-]", ""), 1, 32)
            ent.AdvInvSyncName = name ~= "" and name or nil
            ent:SetNWString("AdvInvSync", name)
        end
    elseif key == "cap" then
        ent:SetNWInt("AdvInvCap", math.Clamp(math.floor(tonumber(value) or 0), 0, 100000))
    elseif key == "loot" then
        ent.AdvInvLoot = I.LootTables[value] and value or nil
        ent:SetNWString("AdvInvLoot", ent.AdvInvLoot or "")
        ent.AdvInvNextLoot = 0
    elseif key == "every" then
        ent.AdvInvLootEvery = math.Clamp(tonumber(value) or C.LootRefillEvery, 1, 1440)
    elseif key == "spawnEvery" then
        ent.AdvInvSpawnEvery = math.Clamp(tonumber(value) or C.LootSpawnEvery, 10, 86400)
    elseif key == "locked" then
        ent:SetNWBool("AdvInvLocked", on)
    elseif key == "code" then
        local code = string.sub(string.gsub(value, "%D", ""), 1, 8)
        if code ~= "" and #code < 4 then
            I.Tell(ply, I.L("storage_code_short"))
            return
        end
        ent.AdvInvCode = code ~= "" and code or nil
        ent.AdvInvCodeFails, ent.AdvInvCodeLockUntil = 0, nil
        ent:SetNWBool("AdvInvHasCode", ent.AdvInvCode ~= nil)
        for _, p in ipairs(player.GetAll()) do
            if p.AdvInvCodes then p.AdvInvCodes[ent] = nil end
        end
    else
        return
    end
    if ent.AdvInvUID then I.SaveStorage(ent) end
end)

---------------------------------------------------------------- loot

local function pick(list)
    local total = 0
    for _, e in ipairs(list) do total = total + (e.weight or 1) end
    local r = math.random() * total
    for _, e in ipairs(list) do
        r = r - (e.weight or 1)
        if r <= 0 then return e end
    end
    return list[#list]
end

local function lootItem(e)
    if e.item then
        local id = AdvInv.ClassID[e.item]
        return id and I.NewItem(id)
    elseif e.weapon then
        local it = I.ItemForWeaponClass(e.weapon, 0)
        return it and I.NewItem(it.id, it.c)
    elseif e.entity then
        return I.NewItem(I.GENERIC_ENTITY, e.entity)
    end
end

-- Random items of a loot table.
function I.RollLoot(name)
    local t = I.LootTables[name]
    if not (t and t.items and #t.items > 0) then return {} end
    local out = {}
    local rolls = t.rolls or { 1, 1 }
    for _ = 1, math.random(rolls[1] or 1, rolls[2] or rolls[1] or 1) do
        local e = pick(t.items)
        local count = e.count and math.random(e.count[1] or 1, e.count[2] or e.count[1] or 1) or 1
        for _ = 1, count do
            local it = lootItem(e)
            if it then out[#out + 1] = it end
        end
    end
    return out
end

-- Loot crates: an emptied crate is refilled after its delay.
timer.Create("AdvInv_LootCrates", 15, 0, function()
    for _, ent in ipairs(ents.FindByClass("advinv_crate")) do
        if ent.AdvInvLoot and not I.IsKeyed(ent) and CurTime() >= (ent.AdvInvNextLoot or 0) then
            local items = I.Get(ent, "Storage")
            if #items == 0 then
                for _, it in ipairs(I.RollLoot(ent.AdvInvLoot)) do table.insert(items, it) end
                I.MarkDirty(ent, "Storage")
                ent.AdvInvNextLoot = CurTime() + (ent.AdvInvLootEvery or C.LootRefillEvery) * 60
            end
        end
    end
end)

---------------------------------------------------------------- loot spawns (admin menu)

local function sendSpawns(ply)
    local list = ents.FindByClass("advinv_loot_spawn")
    net.Start("advinv_loot_spawns")
    net.WriteUInt(#list, 12)
    for _, e in ipairs(list) do
        net.WriteEntity(e)
        net.WriteVector(e:GetPos())
        net.WriteString(e.AdvInvLoot or "")
        net.WriteUInt(math.floor(e.AdvInvSpawnEvery or C.LootSpawnEvery), 20)
    end
    net.Send(ply)
end

net.Receive("advinv_loot_spawns", function(_, ply)
    if I.IsAdmin(ply) then sendSpawns(ply) end
end)

net.Receive("advinv_loot_spawn_act", function(_, ply)
    if not I.IsAdmin(ply) then return end
    local act = net.ReadString()
    if act == "add" then
        local tr = ply:GetEyeTrace()
        local e = ents.Create("advinv_loot_spawn")
        e:SetPos(tr.HitPos + tr.HitNormal * 4)
        e:Spawn()
        e.AdvInvLoot = net.ReadString()
        if not I.LootTables[e.AdvInvLoot] then e.AdvInvLoot = "supplies" end
        e.AdvInvSpawnEvery = math.Clamp(net.ReadUInt(20), 10, 86400)
        I.MakePermanent(e)
    else
        local e = net.ReadEntity()
        if not (IsValid(e) and e:GetClass() == "advinv_loot_spawn") then return end
        if act == "remove" then
            I.RemovePermanent(e)
            if IsValid(e.AdvInvSpawned) then e.AdvInvSpawned:Remove() end
            e:Remove()
        elseif act == "goto" then
            ply:SetPos(e:GetPos() + Vector(0, 0, 8))
        elseif act == "set" then
            e.AdvInvLoot = net.ReadString()
            if not I.LootTables[e.AdvInvLoot] then e.AdvInvLoot = "supplies" end
            e.AdvInvSpawnEvery = math.Clamp(net.ReadUInt(20), 10, 86400)
            if e.AdvInvUID then I.SaveStorage(e) end
        end
    end
    timer.Simple(0.1, function() if IsValid(ply) then sendSpawns(ply) end end)
end)
