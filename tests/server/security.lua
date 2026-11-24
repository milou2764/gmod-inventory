-- Security fixes (DarkRP): ammo pickups, gm_giveswep window, spawns without death, empty bodies,
-- line of sight, DarkRP drop rules, arrest, limited entities, container item cap, crate re-store,
-- crafting with split boxes, search time limit, /dropmoney.
local done = ASYNC(60)
local I = AdvInv
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
local out = {}
local BASE = Vector(-2800, -300, -140)
local function step(list, i)
    i = i or 1
    if i > #list then return done(out) end
    local ok, err = pcall(list[i][2])
    if not ok then out["error_" .. list[i][1]] = tostring(err) end
    timer.Simple(list[i][3] or 0.5, function() step(list, i + 1) end)
end
local function count(ply, pred)
    local n, list = 0, {}
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        for _, it in ipairs(I.Get(ply, cont)) do
            if pred(it) then n = n + 1 list[#list + 1] = it.r end
        end
    end
    return n, list
end
local function fill(ply, keepFree) -- pockets full of crowbars but keepFree points
    for _ = 1, 200 do
        local it = { id = I.GENERIC_WEAPON, c = "weapon_crowbar", r = 0 }
        if I.Free(ply, "Uniform") - I.ItemMass(it.id, it.c) < keepFree then break end
        table.insert(I.Get(ply, "Uniform"), it)
    end
    I.MarkDirty(ply, "Uniform")
end
player.CreateNextBot("S1")
player.CreateNextBot("S2")
timer.Simple(1.5, function()
    local a, b = player.GetBots()[1], player.GetBots()[2]
    a:SetPos(BASE) b:SetPos(BASE + Vector(0, 300, 0))
    a:SetEyeAngles(Angle(0, 0, 0))
    I.SetDefaults(a) I.SetDefaults(b)
    local boxID, boxC = I.AmmoBoxFor("Pistol")
    local pistolBox = I.Info(boxID, boxC).boxRounds
    local function isPistol(it) return it.id == boxID and it.c == boxC end
    local ammo, crate, wall
    step({
        { "ammoSetup", function()
            out.pistolBox = pistolBox
            table.insert(I.Get(a, "Uniform"), { id = boxID, c = boxC, r = pistolBox - 5 })
            fill(a, 0)
            ammo = ents.Create("spawned_ammo")
            ammo:SetModel("models/items/boxsrounds.mdl")
            ammo:SetPos(BASE + Vector(40, 0, 10))
            ammo:Spawn()
            ammo.ammoType, ammo.amountGiven = "Pistol", 60
        end },
        { "ammoPartialUse", function()
            a.AdvInvUseDelay = 0
            I.Use(a, ammo)
        end, 0.3 },
        { "ammoPartial", function()
            local rest
            for _, e in ipairs(ents.FindInSphere(BASE + Vector(40, 0, 10), 80)) do
                if e ~= ammo and e:GetNWInt("AdvInvRounds") > 0 then rest = e end
            end
            local _, rounds = count(a, isPistol)
            out.ammoPartial = { sourceGone = not IsValid(ammo), restOnGround = IsValid(rest) and rest:GetNWInt("AdvInvRounds") or "none", boxes = rounds }
            if IsValid(rest) then rest:Remove() end
            I.SetDefaults(a)
            ammo = ents.Create("spawned_ammo")
            ammo:SetModel("models/items/boxsrounds.mdl")
            ammo:SetPos(BASE + Vector(40, 0, 10))
            ammo:Spawn()
            ammo.ammoType, ammo.amountGiven = "Pistol", 100 -- merged piles
        end },
        { "ammoMergedUse", function()
            a.AdvInvUseDelay = 0
            I.Use(a, ammo)
        end, 0.3 },
        { "ammoMerged", function()
            local _, rounds = count(a, isPistol)
            out.ammoMerged = { sourceGone = not IsValid(ammo), boxes = rounds } -- none bigger than pistolBox
            I.SetDefaults(a)
        end },
        { "giveSWEP", function()
            hook.GetTable().PlayerGiveSWEP.AdvInv_GiveSWEP(a, "weapon_pistol", weapons.Get("weapon_pistol"))
            out.flagSameTick = a.AdvInvGiveSWEP ~= nil
        end, 0.3 },
        { "giveSWEPLater", function()
            out.flagLater = a.AdvInvGiveSWEP ~= nil
            a:Give("weapon_pistol") -- a loadout a moment later: stays a weapon
        end, 0.3 },
        { "giveSWEPAfter", function()
            out.loadoutWeaponKept = a:HasWeapon("weapon_pistol")
            a:StripWeapon("weapon_pistol")
            -- spawn without death (DarkRP's arrest teleport, admin respawn): inventory kept
            table.insert(I.Get(a, "Uniform"), { id = I.GENERIC_AMMO, c = "SMG1", r = 10 })
            I.MarkDirty(a, "Uniform")
            a:Spawn()
            a:SetPos(BASE)
        end, 0.8 },
        { "spawnNoDeath", function()
            out.keptAfterSpawn = count(a, function(it) return it.c == "SMG1" end)
            GetConVar("advinv_death_drop"):SetInt(3)
            a:Kill()
        end, 0.8 },
        { "deathMode3", function()
            out.bodyAfterDeath = 0
            for body in pairs(I.Bodies) do if IsValid(body) then out.bodyAfterDeath = out.bodyAfterDeath + 1 end end
            a:Spawn() a:SetPos(BASE)
        end, 0.8 },
        { "emptyDeath", function()
            out.resetAfterDeath = count(a, function(it) return it.c == "SMG1" end) -- 0: on the body
            out.bodiesBefore = table.Count(I.Bodies)
            a:Kill() -- nothing carried: no body of ours
        end, 0.8 },
        { "emptyDeathAfter", function()
            out.bodiesAfterEmptyDeath = table.Count(I.Bodies)
            a:Spawn()
            a:SetPos(BASE) a:SetEyeAngles(Angle(0, 0, 0))
            crate = ents.Create("advinv_crate")
            crate:SetPos(BASE + Vector(90, 0, 10))
            crate:Spawn()
        end, 0.5 },
        { "sight", function()
            out.crateOpen = I.CanAccess(a, crate)
            wall = ents.Create("prop_physics")
            wall:SetModel("models/hunter/plates/plate2x2.mdl")
            wall:SetPos(BASE + Vector(45, 0, 50))
            wall:SetAngles(Angle(90, 0, 0))
            wall:Spawn()
            wall:GetPhysicsObject():EnableMotion(false)
        end, 0.3 },
        { "sightWall", function()
            out.crateBehindWall = I.CanAccess(a, crate)
            wall:Remove()
            -- drop rules: a police job's weapon (dropspawnedweapons off)
            out.dropRule = { citizen = I.MayLeave(a, I.GENERIC_WEAPON, "weapon_glock2") }
            if TEAM_POLICE then
                a:changeTeam(TEAM_POLICE, true, true)
                out.dropRule.police = I.MayLeave(a, I.GENERIC_WEAPON, "weapon_glock2")
                a:changeTeam(TEAM_CITIZEN, true, true)
            end
        end, 0.5 },
        { "arrest", function()
            local g = ents.Create("weapon_smg1") g:SetPos(BASE + Vector(40, 0, 10)) g:Spawn()
            if a.arrest then a:arrest(10) end
            out.arrested = a.isArrested and a:isArrested() or false
            out.pickupWhileArrested = { I.CanPickup(a, g) }
            if a.unArrest then a:unArrest() end
            timer.Simple(0.5, function() -- DarkRP puts him back at a spawn point
                a:SetPos(BASE)
                timer.Simple(0.2, function() if IsValid(g) then out.pickupAfter = I.CanPickup(a, g) g:Remove() end end)
            end)
        end, 1.2 },
        { "limited", function()
            local e = ents.Create("item_healthkit")
            e:SetPos(BASE + Vector(40, 0, 10)) e:Spawn()
            out.normalKit = I.ItemFromEntity(e) ~= nil
            e.DarkRPItem = { max = 2, cmd = "test" }
            out.limitedKit = I.ItemFromEntity(e) ~= nil
            e:Remove()
        end },
        { "cap", function()
            crate:SetNWInt("AdvInvCap", 100000)
            local list = I.Get(crate, "Storage")
            for _ = 1, 255 do list[#list + 1] = { id = I.GENERIC_AMMO, c = "Pistol", r = 1 } end
            out.fitAt255 = I.CanFit(crate, "Storage", I.GENERIC_AMMO, "Pistol")
            I.Set(crate, "Storage", {})
            I.MarkDirty(crate, "Storage")
            -- dropped next to a crate: not stored back at once
            local it = I.SpawnItem({ id = I.GENERIC_AMMO, c = "Pistol", r = 3 }, crate:GetPos() + Vector(0, 0, 40))
            out.restoreFresh = I.StoreEntityIn(crate, it)
            I.GroundItems[it] = CurTime() - 2
            out.restoreLater = I.StoreEntityIn(crate, it)
        end },
        { "craft", function()
            local spec = { ammo = "Pistol" }
            out.craftFull = I.ItemMatches({ id = boxID, c = boxC, r = pistolBox }, spec)
            out.craftSplit = I.ItemMatches({ id = boxID, c = boxC, r = 1 }, spec)
            -- a finished search doesn't last for ever
            GetConVar("advinv_search_mode"):SetInt(2)
            a:SetPos(BASE) b:SetPos(BASE + Vector(0, 60, 0))
            a.AdvInvSearchView, a.AdvInvSearchSince = b, CurTime()
            out.searchNow = I.IsSearching(a, b)
            a.AdvInvSearchSince = CurTime() - 1000
            out.searchOld = I.IsSearching(a, b)
            a.AdvInvSearchView = nil
            local cmd = DarkRP and DarkRP.getChatCommand and DarkRP.getChatCommand("dropmoney")
            out.dropMoneyCommand = cmd and isfunction(cmd.callback) or false
            GetConVar("advinv_death_drop"):SetInt(3)
        end },
    })
end)
