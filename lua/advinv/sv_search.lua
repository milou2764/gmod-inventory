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
        if target.AdvInvViewers then target.AdvInvViewers[searcher] = nil end
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
        local item = I.TakeOff(target, cat)
        if not item then return end
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
