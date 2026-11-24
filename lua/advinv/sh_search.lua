--[[
    Searching another player (server: sv_search.lua, client: cl_search.lua).

    Context menu (C) on a player within reach > "Search": after advinv_search_time seconds, both
    players staying close and alive, the searcher sees the target's inventory: illegal items are
    marked in red, and (advinv_search_take 1) the searcher may take items and equipped weapons.
    The target is told; moving away ends the search.

        advinv_search_mode 1    0: nobody (admins excepted), 1: allowed jobs only, 2: anyone
        advinv_search_time 5    seconds the search takes
        advinv_search_take 1    the searcher may take (confiscate) items
    Allowed jobs (mode 1): DarkRP's police jobs (isCP), and the team names in
    AdvInv.Config.SearchTeams. If there are none (no DarkRP, empty list), anyone may search.

    Illegal items: ENT.Illegal = true on an registered item, or AdvInv.IllegalItems[class] = true
    (any class: generic weapons and entities too).
    Hook (shared): CanSearchInventory(searcher, target) -> false to forbid, true to allow.
--]]
local I = AdvInv
local C = I.Config
local FLAGS = { FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED }

C.SearchTeams = C.SearchTeams or {}       -- team names allowed to search (mode 1)
C.SearchRange = C.SearchRange or 100      -- units between the two players

I.SearchMode = CreateConVar("advinv_search_mode", "1", FLAGS, "Who may search players: 0 nobody, 1 allowed jobs, 2 anyone", 0, 2)
I.SearchTime = CreateConVar("advinv_search_time", "5", FLAGS, "Seconds a search takes", 0, 60)
I.SearchTake = CreateConVar("advinv_search_take", "1", FLAGS, "A searcher may take (confiscate) items", 0, 1)

I.AddAdminSetting("advinv_search_mode", "int", 0, 2)
I.AddAdminSetting("advinv_search_time", "int", 0, 60)
I.AddAdminSetting("advinv_search_take", "bool")

I.IllegalItems = I.IllegalItems or {}

function I.IsIllegal(item)
    if not item then return false end
    if item.c and I.IllegalItems[item.c] then return true end
    local t = not I.IsGeneric(item.id) and I.EntTable(item.id)
    return t and (t.Illegal or I.IllegalItems[t.ClassName]) and true or false
end

local function allowedJob(ply)
    local any = false
    if ply.isCP then
        any = true
        if ply:isCP() then return true end
    end
    if #C.SearchTeams > 0 then
        any = true
        local name = team.GetName(ply:Team())
        for _, t in ipairs(C.SearchTeams) do
            if t == name or t == ply:Team() then return true end
        end
    end
    return not any -- no job list at all: anyone
end

-- May searcher search target? -> true, or false and a reason.
function I.CanSearch(searcher, target)
    if not (IsValid(searcher) and IsValid(target) and target:IsPlayer() and target ~= searcher) then return false end
    if not (searcher:Alive() and target:Alive()) then return false end
    if searcher:GetPos():DistToSqr(target:GetPos()) > (C.SearchRange + 30) ^ 2 then return false, I.L("search_too_far") end
    if not I.InSight(searcher, target) then return false, I.L("search_too_far") end
    return I.SearchAllowed(searcher, target)
end

-- The rules alone (no distance): checked again during the whole search.
function I.SearchAllowed(searcher, target)
    local h = hook.Run("CanSearchInventory", searcher, target)
    if h ~= nil then return h and true or false, h == false and I.L("search_denied") or nil end
    if I.IsAdmin(searcher) then return true end
    local mode = I.SearchMode:GetInt()
    if mode == 2 then return true end
    if mode == 1 and allowedJob(searcher) then return true end
    return false, I.L("search_denied")
end
