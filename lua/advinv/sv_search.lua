--[[
    Searching another player, server side (rules in sh_search.lua).
        ACT.SEARCH  1 target   start a search
                    2          cancel / stop
                    3 target, slot   take an equipped item (advinv_search_take 1)
    While a search runs: NW float "AdvInvSearchEnd" and NW entity "AdvInvSearchTarget" on the searcher,
    NW entity "AdvInvSearchedBy" on the target (the clients draw the progress).
--]]
local I = AdvInv
local C = I.Config
local handlers = I.ActHandlers

util.AddNetworkString("advinv_search_done")

local SUB = { START = 1, STOP = 2, TAKE_SLOT = 3 }
I.SEARCH = SUB

local function clear(searcher)
    if not IsValid(searcher) then return end
    local target = searcher.AdvInvSearchView or searcher:GetNWEntity("AdvInvSearchTarget")
    if IsValid(target) then
        if target.AdvInvViewers and target.AdvInvViewers[searcher] then I.EndView(target, searcher) end
        if target:GetNWEntity("AdvInvSearchedBy") == searcher then target:SetNWEntity("AdvInvSearchedBy", NULL) end
    end
    searcher.AdvInvSearchView = nil
    searcher:SetNWFloat("AdvInvSearchEnd", 0)
    searcher:SetNWEntity("AdvInvSearchTarget", NULL)
    timer.Remove("AdvInv_Search_" .. searcher:EntIndex())
end
I.StopSearch = clear

local function close(a, b)
    return IsValid(a) and IsValid(b) and a:Alive() and b:Alive()
        and a:GetPos():DistToSqr(b:GetPos()) <= (C.SearchRange + 60) ^ 2 and I.InSight(a, b)
end

C.SearchViewTime = C.SearchViewTime or 120 -- seconds a finished search lets the searcher look and take

-- The searcher may see / take from target now: close, in sight, still allowed (job...), not too long.
function I.IsSearching(ply, target)
    return ply.AdvInvSearchView == target and close(ply, target)
        and CurTime() - (ply.AdvInvSearchSince or 0) <= C.SearchViewTime
        and I.SearchAllowed(ply, target) == true
end

local function finish(searcher, target)
    searcher.AdvInvSearchView = target
    searcher.AdvInvSearchSince = CurTime()
    searcher:SetNWFloat("AdvInvSearchEnd", 0)
    target.AdvInvViewers = target.AdvInvViewers or {}
    target.AdvInvViewers[searcher] = true
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do I.SendContainer(target, cont, searcher) end
    -- illegal items found
    local found = {}
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        for _, it in ipairs(I.Get(target, cont)) do
            if I.IsIllegal(it) then found[#found + 1] = I.Info(it.id, it.c).name end
        end
    end
    for _, cat in ipairs(AdvInv.WeaponCat) do
        local id, c = I.SlotRef(target, cat)
        if id > 1 and I.IsIllegal({ id = id, c = c }) then found[#found + 1] = I.Info(id, c).name end
    end
    net.Start("advinv_search_done")
    net.WriteEntity(target)
    net.WriteString(#found > 0 and I.L("search_found", table.concat(found, ", ")) or I.L("search_nothing"))
    net.Send(searcher)
    hook.Run("AdvInv_Searched", searcher, target, found)
end

-- What a searcher may take from target: not what DarkRP's own weapon checker leaves (the target's job
-- weapons and the default ones with weaponCheckerHideDefault, noStripWeapons), else the job would
-- give them again at the next loadout. -> true, or false and a reason
function I.SearchMayTake(target, id, c)
    local info = I.Info(id, c)
    -- (a grenade item: its grenade weapon's rule)
    local grenadeClass = info.isBox and I.GrenadeOfAmmo and I.GrenadeOfAmmo(info.ammo)
    if not info.isWeapon and not grenadeClass then return true end
    local class = grenadeClass or (id == I.GENERIC_WEAPON and c) or info.weaponClass
    local cfg = DarkRP and GAMEMODE and GAMEMODE.Config
    if not (cfg and isstring(class)) then return true end
    -- DarkRP's weapon checker rule (GetStrippableWeapons), with the class as written and lowercased
    local lc = string.lower(class)
    local function listed(list)
        if not istable(list) then return false end
        for _, v in pairs(list) do
            if isstring(v) and string.lower(v) == lc then return true end
        end
        return false
    end
    local function keyed(map) return istable(map) and (map[class] or map[lc]) and true or false end
    local job = target.getJobTable and target:getJobTable()
    local legal = keyed(cfg.noStripWeapons) or (cfg.weaponCheckerHideNoLicense and keyed(GAMEMODE.NoLicense))
    if not legal and cfg.weaponCheckerHideDefault then
        legal = listed(cfg.DefaultWeapons) or (job and listed(job.weapons))
        if not legal and listed(cfg.AdminWeapons) then
            local access = target:IsAdmin()
            if CAMI and CAMI.PlayerHasAccess then
                CAMI.PlayerHasAccess(target, "DarkRP_GetAdminWeapons", function(ok) access = ok end)
            end
            legal = access and true or false
        end
    end
    if legal then return false, I.L("search_cannot_take", info.name or class) end
    return true
end

handlers[I.ACT.SEARCH] = function(ply)
    local sub = net.ReadUInt(2)
    if sub == SUB.STOP then
        clear(ply)
        return true
    end
    local target = net.ReadEntity()
    if sub == SUB.START then
        if (ply.AdvInvSearchWait or 0) > CurTime() then return end
        ply.AdvInvSearchWait = CurTime() + 2
        local ok, why = I.CanSearch(ply, target)
        if not ok then return false, why end
        clear(ply)
        local t = I.SearchTime:GetFloat()
        ply:SetNWEntity("AdvInvSearchTarget", target)
        ply:SetNWFloat("AdvInvSearchEnd", CurTime() + t)
        target:SetNWEntity("AdvInvSearchedBy", ply)
        I.Tell(target, I.L("search_you", ply:Nick()))
        local name = "AdvInv_Search_" .. ply:EntIndex()
        local start = CurTime()
        timer.Create(name, 0.25, 0, function()
            if not close(ply, target) then
                if IsValid(ply) then I.Tell(ply, I.L("search_cancelled")) end
                clear(ply)
                return
            end
            if CurTime() - start >= t then
                timer.Remove(name)
                if IsValid(target) and target:GetNWEntity("AdvInvSearchedBy") == ply then target:SetNWEntity("AdvInvSearchedBy", NULL) end
                finish(ply, target)
            end
        end)
        return true
    end
    if sub == SUB.TAKE_SLOT then
        local cat = AdvInv.IDCategory[net.ReadUInt(4)]
        if not (cat and table.HasValue(AdvInv.WeaponCat, cat)) then return end -- equipped weapons only
        if not (I.SearchTake:GetBool() and I.IsSearching(ply, target)) then return false end
        local may, mayWhy = I.SearchMayTake(target, I.SlotRef(target, cat))
        if not may then return false, mayWhy end
        -- (a job's weapon in its slot: refused like a job's item in his containers)
        if target.AdvInvJobSlot and target.AdvInvJobSlot[cat] then
            return false, I.L("search_cannot_take", I.SlotInfo(target, cat).name or "?")
        end
        local item = I.TakeOff(target, cat)
        if not item then return end
        item.j = nil -- (a job's weapon leaving its player is an ordinary one: else lost at the taker's death)
        if not I.Store(ply, item) then I.SpawnItem(item, I.DropPos(ply)) end
        hook.Run("AdvInv_Confiscated", ply, target, item)
        return true
    end
end

-- Viewers leave when they move away; searches end with them.
timer.Create("AdvInv_SearchViewers", 1, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        local target = ply.AdvInvSearchView
        if target and not I.IsSearching(ply, target) then clear(ply) end
    end
end)

hook.Add("OnPlayerChangedTeam", "AdvInv_Search", function(ply) clear(ply) end)

hook.Add("PlayerDisconnected", "AdvInv_Search", function(ply)
    clear(ply)
    for _, p in ipairs(player.GetAll()) do
        if p.AdvInvSearchView == ply or p:GetNWEntity("AdvInvSearchTarget") == ply then clear(p) end
    end
end)
hook.Add("PlayerDeath", "AdvInv_Search", function(ply)
    clear(ply)
    for _, p in ipairs(player.GetAll()) do
        if p.AdvInvSearchView == ply or p:GetNWEntity("AdvInvSearchTarget") == ply then clear(p) end
    end
end)
