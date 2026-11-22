--[[
    Administration, server side (rules in sh_admin.lua). Every request is checked: the player must
    be an admin (I.IsAdmin), and the holder must be one they may touch.

    An admin "views" a player: the player's containers are sent to the admin too, and the admin
    may move items between that player and themselves, delete items, take or delete equipped
    items, clear everything, give items. Each action is logged in the server console and through
    the hook AdvInv_AdminAction(admin, action, target, text).
--]]
local I = AdvInv
local A = I.ADMIN
local handlers = I.ActHandlers

util.AddNetworkString("advinv_admin_settings")
util.AddNetworkString("advinv_admin_set")

local function log(admin, action, target, text)
    local who = IsValid(target) and (target:IsPlayer() and target:Nick() or tostring(target)) or "?"
    MsgN(("[Advanced Inventory System] admin %s (%s) %s %s: %s"):format(admin:Nick(), admin:SteamID(), action, who, text or ""))
    hook.Run("AdvInv_AdminAction", admin, action, target, text)
end

local function itemText(item)
    if not item then return "-" end
    local info = I.Info(item.id, item.c)
    return info.name .. (item.c and (" [" .. item.c .. "]") or "")
end

-- Stops viewing (admin closed the panel, or left).
local function unview(admin)
    local target = admin.AdvInvAdminView
    if IsValid(target) and target.AdvInvViewers then target.AdvInvViewers[admin] = nil end
    admin.AdvInvAdminView = nil
end

-- A full item for a class or ID: boxes full, weapons with a full magazine, gear with full armor.
local function newItem(id, c)
    local info = I.Info(id, c)
    if info == nil or not info.class then return end
    local item = { id = id, c = I.IsGeneric(id) and c or nil, r = 0, a = 0 }
    if info.isBox then item.r = info.boxRounds or 0 end
    if info.isWeapon and (info.clipSize or 0) > 0 then item.r = info.clipSize end
    if info.armor then item.a = info.armor end
    return item
end
I.NewItem = newItem

local sub = {}

sub[A.VIEW] = function(admin)
    local target = net.ReadEntity()
    if not (IsValid(target) and target:IsPlayer()) or target == admin then return end
    unview(admin)
    admin.AdvInvAdminView = target
    target.AdvInvViewers = target.AdvInvViewers or {}
    target.AdvInvViewers[admin] = true
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do I.SendContainer(target, cont, admin) end
    log(admin, "views", target)
    return true
end

sub[A.UNVIEW] = function(admin)
    unview(admin)
    return true
end

sub[A.DELETE] = function(admin)
    local holder, cont, index = net.ReadEntity(), I.ReadCont(), net.ReadUInt(8)
    local count = math.max(net.ReadUInt(8), 1)
    if not (cont and I.CanAccess(admin, holder)) then return end
    local items = I.Get(holder, cont)
    local item = items[index]
    if not item then return end
    local key, text = I.StackKey(item), itemText(item)
    local n = 0
    while n < count and item do
        table.remove(items, index)
        n = n + 1
        index = nil
        for k = #items, 1, -1 do
            if I.StackKey(items[k]) == key then index = k break end
        end
        item = index and items[index]
    end
    I.MarkDirty(holder, cont)
    log(admin, "deleted " .. n .. " x " .. text .. " from", holder, cont)
    return true
end

sub[A.CLEAR] = function(admin)
    local target = net.ReadEntity()
    if not (IsValid(target) and target:IsPlayer()) then return end
    for _, cat in ipairs(AdvInv.WeaponCat) do
        if I.SlotID(target, cat) > 1 then I.TakeOff(target, cat) end
    end
    for cat in pairs(AdvInv.GearCat) do
        if I.SlotID(target, cat) > 1 then I.TakeOff(target, cat) end
    end
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do I.Set(target, cont, {}) end
    log(admin, "cleared the inventory of", target)
    return true
end

sub[A.GIVE] = function(admin)
    local target, id, c = net.ReadEntity(), net.ReadUInt(I.NET_ID_BITS), net.ReadString()
    local count = math.Clamp(net.ReadUInt(8), 1, 100)
    if not (IsValid(target) and target:IsPlayer() and AdvInv.IDClass[id] and id > 1) then return end
    local given = 0
    for _ = 1, count do
        local item = newItem(id, c)
        if not item then return false, I.L("admin_unknown_item") end
        if not I.Store(target, item) then
            if given == 0 then
                local ok = I.Equip(target, item)
                if ok then given = given + 1 end
            end
            break
        end
        given = given + 1
    end
    log(admin, "gave " .. given .. " x " .. itemText(newItem(id, c)) .. " to", target)
    if given < count then return false, I.L("admin_given", given, count) end
    return true
end

sub[A.SLOT_DELETE] = function(admin)
    local target, cat = net.ReadEntity(), AdvInv.IDCategory[net.ReadUInt(4)]
    if not (IsValid(target) and target:IsPlayer() and cat and I.CanAccess(admin, target)) then return end
    local item = I.TakeOff(target, cat)
    log(admin, "deleted the equipped " .. itemText(item) .. " of", target)
    return true
end

sub[A.SLOT_TAKE] = function(admin)
    local target, cat = net.ReadEntity(), AdvInv.IDCategory[net.ReadUInt(4)]
    if not (IsValid(target) and target:IsPlayer() and target ~= admin and cat and I.CanAccess(admin, target)) then return end
    if (cat == "Vest" or cat == "Rucksack") and #I.Get(target, cat) > 0 then
        return false, I.L("msg_empty_it_first")
    end
    local item = I.TakeOff(target, cat)
    if not item then return end
    if not I.Store(admin, item) then I.SpawnItem(item, I.DropPos(admin)) end
    log(admin, "took the equipped " .. itemText(item) .. " of", target)
    return true
end

handlers[I.ACT.ADMIN] = function(ply)
    if not I.IsAdmin(ply) then return false end
    local fn = sub[net.ReadUInt(4)]
    if fn then return fn(ply) end
end

hook.Add("PlayerDisconnected", "AdvInv_AdminView", function(ply)
    unview(ply)
    for _, p in ipairs(player.GetAll()) do
        if p.AdvInvAdminView == ply then unview(p) end
    end
end)

---------------------------------------------------------------- settings

local function sendSettings(admin)
    net.Start("advinv_admin_settings")
    net.WriteUInt(#I.AdminSettings, 8)
    for _, s in ipairs(I.AdminSettings) do
        local cv = GetConVar(s[1])
        net.WriteString(s[1])
        net.WriteString(cv and cv:GetString() or "")
    end
    net.Send(admin)
end

net.Receive("advinv_admin_settings", function(_, ply)
    if I.IsAdmin(ply) then sendSettings(ply) end
end)

net.Receive("advinv_admin_set", function(_, ply)
    local name, value = net.ReadString(), net.ReadString()
    if not I.IsAdmin(ply) then return end
    local s = I.AdminSetting(name)
    if not s or not GetConVar(name) then return end
    if s[2] == "bool" then
        value = (value == "1" or value == "true") and "1" or "0"
    elseif s[2] == "int" or s[2] == "float" then
        local v = tonumber(value)
        if not v then return end
        v = math.Clamp(v, s[3] or -math.huge, s[4] or math.huge)
        value = tostring(s[2] == "int" and math.floor(v) or v)
    elseif s[2] == "choice" then
        if not table.HasValue(s[3], value) then return end
    end
    GetConVar(name):SetString(value)
    log(ply, "set " .. name .. " = " .. value .. " on", game.GetWorld())
    sendSettings(ply)
end)
