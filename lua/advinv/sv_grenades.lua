--[[
    Grenades (sh_grenades.lua): a player's grenade items = his grenades (reserve + loaded in the
    grenade weapons). What other code does to the grenades is read as a change since the last look:
      - fewer (reserve down, or a magazine down on a weapon still held): thrown -> items taken away;
      - more: given by other code (an ammo crate, the spawn menu, a job) -> items added (into the
        containers, else on the ground). During a loadout (respawn, job change) the grenades given
        only top up to what the loadout gives: changing job again and again gives nothing more;
      - a grenade weapon taken away (stripped, confiscated) is not a throw: its grenades stay items.
    Read 5 times a second, and before every reserve sync (I.SyncAmmo) and ammo strip, so an
    inventory change right after a throw can't keep the thrown grenade. The sync then sets the
    reserve from the items (minus the loaded ones) and takes the grenade weapons away when no item
    is left.
--]]
local I = AdvInv

local function sameAmmo(a, b) return string.lower(a) == string.lower(b) end

-- Grenade weapons with a magazine (CW 2.0) of that ammunition held by ply.
local function loadedWeapons(ply, ammo)
    local list = {}
    for class, a in pairs(I.Grenades) do
        if sameAmmo(a, ammo) then
            local w = ply:GetWeapon(class)
            if IsValid(w) and w:GetMaxClip1() > 0 then list[#list + 1] = w end
        end
    end
    return list
end

-- Grenades loaded in the player's grenade weapons of that ammunition.
function I.GrenadesLoaded(ply, ammo)
    local n = 0
    for _, w in ipairs(loadedWeapons(ply, ammo)) do n = n + math.max(w:Clip1(), 0) end
    return n
end

-- Takes n loaded grenades out of the weapons (the items they were are gone).
function I.UnloadGrenades(ply, ammo, n)
    for _, w in ipairs(loadedWeapons(ply, ammo)) do
        if n <= 0 then return end
        local take = math.min(math.max(w:Clip1(), 0), n)
        if take > 0 then
            w:SetClip1(w:Clip1() - take)
            n = n - take
        end
    end
end

-- Grenade ammunition types that exist: lowercase -> name.
local types = {}
function I.GrenadeTypes()
    table.Empty(types)
    for _, a in pairs(I.Grenades) do
        if game.GetAmmoID(a) ~= -1 then types[string.lower(a)] = a end
    end
    return types
end

local function itemCount(ply, ammo)
    local n = 0
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        for _, it in ipairs(I.Get(ply, cont)) do
            if it.id == I.GENERIC_AMMO and it.c and sameAmmo(it.c, ammo) then n = n + (it.r or 0) end
        end
    end
    return n
end

local function takeItems(ply, ammo, n)
    -- the job's grenades first, then the others (a looted grenade isn't used up while a job one,
    -- taken back at death, stays)
    for pass = 1, 2 do
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        local items = I.Get(ply, cont)
        for k = #items, 1, -1 do
            if n <= 0 then return end
            local it = items[k]
            if it.id == I.GENERIC_AMMO and it.c and sameAmmo(it.c, ammo) and (pass == 2 or it.j) then
                local take = math.min(it.r or 0, n)
                it.r = (it.r or 0) - take
                n = n - take
                if it.r <= 0 then table.remove(items, k) end
                I.MarkDirty(ply, cont)
            end
        end
    end
    end
end

-- A grenade another addon drops from a dying player's hands without taking its ammunition (CW 2.0's
-- quick grenade, a cooked ArcCW grenade): one item less, from the player or else from the body just
-- made of him (death hooks run in no fixed order: the body may already have his things).
function I.GrenadeDroppedAtDeath(ply, ammo)
    if not (IsValid(ply) and isstring(ammo) and ammo ~= "") then return end
    -- the job's items already taken at this death: the primed one was a job's grenade (taken first,
    -- as when thrown), already gone; the looted ones stay (on him or on the body)
    local gone = ply.AdvInvJobAmmoGone
    local key = string.lower(ammo)
    if gone and gone.t == CurTime() and (gone[key] or 0) > 0 then
        gone[key] = gone[key] - 1
        return
    end
    if itemCount(ply, ammo) > 0 then return takeItems(ply, ammo, 1) end
    local body = ply.AdvInvLastBody
    if IsValid(body) and body.AdvInvBorn == CurTime() then takeItems(body, ammo, 1) end
end

-- Records the grenades as they are now (after the inventory set them, or a strip).
function I.GrenadeBaseline(ply)
    local st = {}
    for key, ammo in pairs(I.GrenadeTypes()) do
        local clips = {}
        for _, w in ipairs(loadedWeapons(ply, ammo)) do clips[w] = math.max(w:Clip1(), 0) end
        st[key] = { reserve = ply:GetAmmoCount(ammo), clips = clips }
    end
    ply.AdvInvGrenades = st
end

-- Most grenade items one change may add (a bulk GiveAmmo of another addon: the rest is lost).
local MAX_ADD = 20

-- The player's DarkRP job gives grenades of this ammunition (its weapon list).
local function jobGrenade(ply, ammo)
    local job = ply.getJobTable and ply:getJobTable()
    if not (job and istable(job.weapons)) then return false end
    for _, class in ipairs(job.weapons) do
        local a = I.GrenadeAmmo(string.lower(tostring(class)))
        if a and sameAmmo(a, ammo) then return true end
    end
    return false
end

-- Grenades of a job's loadout: items of the job (I.RemoveJobItems takes them at death and at a job
-- change, the save leaves them out, I.MayLeave keeps them on him like the job's weapons), else
-- each loadout made new ordinary grenades to put in a crate (a farm).
local function giveJobGrenades(ply, ammo, n)
    local boxID, boxC = I.AmmoBoxFor(ammo)
    if not boxID then return end
    for _ = 1, n do I.Store(ply, { id = boxID, c = boxC, r = 1, a = 0, j = true }) end
end

-- Reads what happened to ply's grenades since the last look, and changes the items to match.
-- force: also for a player already dead (his death: the throws are counted before the body takes
-- his items).
function I.ReconcileGrenades(ply, force)
    if not (IsValid(ply) and (force or ply:Alive())) then return end
    local st = ply.AdvInvGrenades
    if not st then return I.GrenadeBaseline(ply) end
    for key, ammo in pairs(I.GrenadeTypes()) do
        local s = st[key] or { reserve = 0, clips = {} }
        st[key] = s
        local reserve = ply:GetAmmoCount(ammo)
        local delta = reserve - s.reserve
        local clips = {}
        for _, w in ipairs(loadedWeapons(ply, ammo)) do
            local c = math.max(w:Clip1(), 0)
            clips[w] = c
            delta = delta + c - (s.clips[w] or 0) -- a new weapon: its loaded grenades were given
        end
        s.reserve, s.clips = reserve, clips
        if delta < 0 then
            takeItems(ply, ammo, -delta)
        elseif delta > 0 then
            local add, fromJob = delta, false
            if (ply.AdvInvLoadoutUntil or 0) > CurTime() then
                add = math.max(delta - itemCount(ply, ammo), 0) -- a loadout tops up
                fromJob = jobGrenade(ply, ammo)
            end
            add = math.min(add, MAX_ADD)
            if add > 0 then
                if fromJob then giveJobGrenades(ply, ammo, add) else I.GiveRounds(ply, ammo, add) end
            end
            if add < delta then I.MarkDirty(ply, "Uniform") end -- the rest goes (reserve = items)
        end
    end
end

-- After the sync set the reserve: weapons of a type with no item left go.
function I.GrenadesSynced(ply, emptyTypes)
    for key in pairs(emptyTypes) do
        for class, a in pairs(I.Grenades) do
            if string.lower(a) == key and ply:HasWeapon(class) then ply:StripWeapon(class) end
        end
    end
    I.GrenadeBaseline(ply)
end

timer.Create("AdvInv_Grenades", 0.2, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        if ply.AdvInvGrenades then I.ReconcileGrenades(ply) end
    end
end)

-- Spawned: what he has now is the start (the loadout that follows tops up).
hook.Add("PlayerSpawn", "AdvInv_Grenades", function(ply)
    ply.AdvInvLoadoutUntil = CurTime() + 1
    timer.Simple(0, function() if IsValid(ply) then I.MarkDirty(ply, "Uniform") end end)
    I.GrenadeBaseline(ply)
end)

hook.Add("PlayerLoadout", "AdvInv_Grenades", function(ply)
    ply.AdvInvLoadoutUntil = CurTime() + 1
end)

-- Dead: the grenade in the hands is not dropped (the items are on the body).
hook.Add("DoPlayerDeath", "AdvInv_Grenades", function(ply)
    I.ReconcileGrenades(ply, true)
    ply.AdvInvGrenades = nil
    for class in pairs(I.Grenades) do
        if ply:HasWeapon(class) then ply:StripWeapon(class) end
    end
end)

-- DarkRP's /drop: grenades are dropped from the inventory (an item), not as a weapon.
hook.Add("canDropWeapon", "AdvInv_Grenades", function(_, wep)
    if IsValid(wep) and I.GrenadeAmmo(wep:GetClass()) then return false end
end)
