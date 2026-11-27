--[[
    Advanced Crafting System (sh_acs.lua): a player's resources are the bags of resources in his
    containers (pockets, vest, backpack). Its table AdvancedCraftingSystem.Resources[SteamID] is
    replaced by a stand-in that reads and changes them, so its workbench, resource boxes, scrapper,
    kills that give resources and admin commands work as before, on what he carries:
      - gained resources fill his started bags, then new bags, then the ground (he is told);
      - spent ones come out of the least full bags first;
      - the bags weigh, go into crates and trunks, can be searched, and stay on the body when he
        dies (its own drop at death, a box or the killer's share, finds nothing: no double drop).
    Kept between visits:
      - with a character system (AdvInv_OwnerID), the bags are saved with the inventory; a balance
        the crafting system saved before is given once, as bags, when the inventory is loaded;
      - without one (the inventory resets at the first spawn), what he carries is written into the
        crafting system's own save (when it saves, every minute, when he leaves) and given back as
        bags at his first spawn.
    Its other tables (recipes, settings, taken recipes) are left to it.
--]]
local I = AdvInv

local stored = {} -- the crafting system's saved balances: SteamID -> resources
local proxy

local function ACS() return istable(AdvancedCraftingSystem) and AdvancedCraftingSystem or nil end

local function bagID() return I.ClassID and I.ClassID[I.ACS_CLASS] end

-- Resources in ply's bags.
function I.ACSCount(ply)
    local id = bagID()
    if not id then return 0 end
    local n = 0
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        for _, it in ipairs(I.Get(ply, cont)) do
            if it.id == id then n = n + (it.r or 0) end
        end
    end
    return n
end

-- Takes n resources out of ply's bags, the least full first (empty bags go).
local function take(ply, n)
    local id = bagID()
    if not id or n <= 0 then return end
    local bags = {}
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        for _, it in ipairs(I.Get(ply, cont)) do
            if it.id == id then bags[#bags + 1] = { cont, it } end
        end
    end
    table.sort(bags, function(a, b) return (a[2].r or 0) < (b[2].r or 0) end)
    local dirty = {}
    for _, b in ipairs(bags) do
        if n <= 0 then break end
        local t = math.min(n, b[2].r or 0)
        b[2].r = (b[2].r or 0) - t
        n = n - t
        dirty[b[1]] = true
    end
    for cont in pairs(dirty) do
        local list = I.Get(ply, cont)
        for k = #list, 1, -1 do
            if list[k].id == id and (list[k].r or 0) <= 0 then table.remove(list, k) end
        end
        I.MarkDirty(ply, cont)
    end
end

-- Gives n resources as bags (started bags first, then new ones, then the ground).
local function give(ply, n)
    if n <= 0 then return end
    local before = I.ACSCount(ply)
    I.GiveRounds(ply, I.ACS_AMMO, n)
    local left = n - (I.ACSCount(ply) - before)
    if left > 0 then I.Tell(ply, I.L("acs_no_room", left)) end
end

local function setCount(ply, v)
    v = math.max(0, math.floor(tonumber(v) or 0))
    local c = I.ACSCount(ply)
    if v > c then give(ply, v - c) elseif v < c then take(ply, c - v) end
    if I.SyncAmmo then I.SyncAmmo(ply) end
end

local function playerOf(sid)
    if game.SinglePlayer() then return Entity(1) end -- (as the crafting system does)
    local ply = player.GetBySteamID(sid)
    return IsValid(ply) and ply or nil
end

-- the inventory is his (given his saved balance) and he is alive: his bags are his resources
local function ready(ply) return ply.AdvInvACSReady and ply:Alive() end
local function savedByInventory(ply) return I.GetOwnerID(ply) ~= nil end

proxy = setmetatable({}, {
    __index = function(_, sid)
        local ply = isstring(sid) and playerOf(sid)
        if ply then return ready(ply) and I.ACSCount(ply) or 0 end
        return stored[sid]
    end,
    __newindex = function(_, sid, v)
        local ply = isstring(sid) and playerOf(sid)
        if ply then
            if not isnumber(v) then return end
            if ready(ply) then
                setCount(ply, v)
            elseif v > 0 then
                -- dead, or before his first spawn (he reads 0): owed, given as bags at his next
                -- spawn (an admin's gift, a kill's share given just after he died)
                ply.AdvInvACSOwed = (ply.AdvInvACSOwed or 0) + math.floor(v)
            end
            return
        end
        stored[sid] = v
    end,
})

-- Online players' bags into the balances the crafting system saves (without a character system).
-- -> true if one changed
local function refreshStored()
    local changed = false
    for _, ply in ipairs(player.GetHumans()) do
        if ply.AdvInvACSReady and not savedByInventory(ply) then
            local sid = ply:SteamID()
            local n = I.ACSCount(ply) + (ply.AdvInvACSOwed or 0)
            if stored[sid] ~= n then stored[sid] = n changed = true end
        end
    end
    return changed
end

local function install()
    local acs = ACS()
    if not (acs and I.ACSActive) or acs.AdvInvResources == proxy then return end
    if istable(acs.Resources) and acs.Resources ~= proxy then stored = acs.Resources end
    acs.Resources = proxy
    acs.AdvInvResources = proxy
    -- its save writes the balances, not the stand-in; its load reads them back behind it
    local save, load = acs.Save, acs.Load
    if isfunction(save) then
        acs.Save = function(self, ...)
            refreshStored()
            self.Resources = stored
            local ok, err = pcall(save, self, ...)
            self.Resources = proxy
            if not ok then ErrorNoHalt("[AdvInv] Advanced Crafting System save: " .. tostring(err) .. "\n") end
        end
    end
    if isfunction(load) then
        acs.Load = function(self, ...)
            local ok, err = pcall(load, self, ...)
            if istable(self.Resources) and self.Resources ~= proxy then stored = self.Resources end
            self.Resources = proxy
            if not ok then ErrorNoHalt("[AdvInv] Advanced Crafting System load: " .. tostring(err) .. "\n") end
        end
    end
    -- a character's inventory loaded: a balance saved before is given once, as bags
    local loadInv = I.Load
    I.Load = function(ply, owner, ...)
        local r = loadInv(ply, owner, ...)
        if IsValid(ply) and owner ~= nil then
            local sid = ply:SteamID()
            local n = tonumber(stored[sid]) or 0
            ply.AdvInvACSReady = true
            if n > 0 then
                stored[sid] = 0
                give(ply, n)
                if acs.Save then acs:Save() end
            end
        end
        return r
    end
    I.Log.d("ACS", "Advanced Crafting System: its resources are bags in the inventory")
end
hook.Add("InitPostEntity", "AdvInv_ACS", install)
if ACS() and I.ACSActive then install() end -- (a reload)

-- First spawn: (no character system) his saved balance as bags, after the inventory's reset; any
-- spawn: what he was owed while dead.
hook.Add("PlayerSpawn", "AdvInv_ACS", function(ply)
    if not I.ACSActive or ply.AdvInvACSPending then return end
    local first = not ply.AdvInvACSReady
    if not first and not ply.AdvInvACSOwed then return end
    ply.AdvInvACSPending = true
    timer.Simple(0.5, function()
        if not IsValid(ply) then return end
        ply.AdvInvACSPending = nil
        if not ply:Alive() then return end -- (the next spawn)
        local n = 0
        if first then
            ply.AdvInvACSReady = true
            -- (with a character system: given when his inventory is loaded)
            if not savedByInventory(ply) then n = tonumber(stored[ply:SteamID()]) or 0 end
        end
        n = n + (ply.AdvInvACSOwed or 0)
        ply.AdvInvACSOwed = nil
        if n > 0 then give(ply, n) end
    end)
end)

hook.Add("PlayerDisconnected", "AdvInv_ACS", function(ply)
    if not I.ACSActive then return end
    local sid, owed = ply:SteamID(), ply.AdvInvACSOwed or 0
    if ply.AdvInvACSReady and not savedByInventory(ply) then
        stored[sid] = I.ACSCount(ply) + owed
    elseif owed > 0 then
        stored[sid] = (tonumber(stored[sid]) or 0) + owed -- (given at his next first spawn, or load)
    else
        return
    end
    local acs = ACS()
    if acs and acs.Save then acs:Save() end
end)

timer.Create("AdvInv_ACS", 60, 0, function()
    local acs = ACS()
    if I.ACSActive and acs and acs.Save and refreshStored() then acs:Save() end
end)
