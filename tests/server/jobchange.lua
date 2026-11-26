-- DarkRP job change with an inventory, in DarkRP's three ways (config): norespawn (default: strip
-- weapons and ammo, new loadout), keepPickedUp (only the old job's weapons go), and norespawn off
-- (instantjob: respawn at once; else killed silently, respawned later). Then
-- advinv_darkrp_loadout_to_inventory 1: does a job weapon stay after leaving the job?
local done = ASYNC(60)
local I = AdvInv
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
local out = {}
local cfg = GAMEMODE.Config
local saved = { norespawn = cfg.norespawn, keepPickedUp = cfg.keepPickedUp, instantjob = cfg.instantjob }
local function step(list, i)
    i = i or 1
    if i > #list then
        for k, v in pairs(saved) do cfg[k] = v end
        RunConsoleCommand("advinv_darkrp_loadout_to_inventory", "0")
        return done(out)
    end
    local ok, err = pcall(list[i][2])
    if not ok then out["error_" .. list[i][1]] = tostring(err) end
    timer.Simple(list[i][3] or 1, function() step(list, i + 1) end)
end
local function setup(b)
    I.SetDefaults(b)
    I.Equip(b, { id = I.ClassID.advinv_barney_helmet, a = 90 })
    I.Equip(b, { id = I.ClassID.advinv_hl2_ar2, r = 17 })
    I.Store(b, { id = I.ClassID.advinv_ammo_ar2, r = 30 })
    I.Store(b, { id = I.GENERIC_AMMO, c = "Grenade", r = 1 })
    I.Store(b, { id = I.GENERIC_AMMO, c = "Grenade", r = 1 })
end
local function state(b)
    local items = {}
    for _, it in ipairs(I.Get(b, "Uniform")) do items[#items + 1] = (I.IDClass[it.id] or "?") .. (it.c and ("[" .. it.c .. "]") or "") .. "(" .. (it.r or 0) .. ")" end
    local w = b:GetWeapon("weapon_ar2")
    local weps = {}
    for _, x in ipairs(b:GetWeapons()) do weps[#weps + 1] = x:GetClass() end
    table.sort(weps)
    return {
        job = team.GetName(b:Team()), alive = b:Alive(),
        helmet = I.IDClass[b:GetNW2Int("Helmet")] or "none", helmetArmor = b:GetNWInt("HelmetArmor"),
        primary = I.IDClass[b:GetNWInt("PrimaryWep")] or "none", secondary = I.IDClass[b:GetNWInt("SecondaryWep")] or b:GetNWString("SecondaryWepClass"),
        ar2InHands = IsValid(w), ar2Clip = IsValid(w) and w:Clip1() or "-", ar2Reserve = b:GetAmmoCount("AR2"),
        pockets = table.concat(items, " "), weapons = table.concat(weps, " "),
    }
end
player.CreateNextBot("J")
timer.Simple(1.5, function()
    local b = player.GetBots()[1]
    b:SetPos(Vector(-2800, -300, -140))
    b:changeTeam(TEAM_CITIZEN, true, true)
    setup(b)
    step({
        { "start", function() out.before = state(b) end, 0.5 },
        -- 1. default: norespawn
        { "default", function()
            cfg.norespawn, cfg.keepPickedUp = true, false
            b:changeTeam(TEAM_POLICE, true, true)
        end },
        { "defaultAfter", function()
            out.default = state(b)
            b:changeTeam(TEAM_CITIZEN, true, true)
        end },
        { "back", function() out.backToCitizen = state(b) end, 0.3 },
        -- 2. keepPickedUp
        { "keep", function()
            cfg.keepPickedUp = true
            b:changeTeam(TEAM_POLICE, true, true)
        end },
        { "keepAfter", function()
            out.keepPickedUp = state(b)
            cfg.keepPickedUp = false
            b:changeTeam(TEAM_CITIZEN, true, true)
        end },
        -- 3. norespawn off, instantjob: respawned at once
        { "instant", function()
            cfg.norespawn, cfg.instantjob = false, true
            b:changeTeam(TEAM_POLICE, true, true)
        end },
        { "instantAfter", function()
            b:SetPos(Vector(-2800, -300, -140))
            out.instantjob = state(b)
            cfg.norespawn, cfg.instantjob = true, false
            b:changeTeam(TEAM_CITIZEN, true, true)
        end },
        -- 4. norespawn off: killed silently, respawned later
        { "silent", function()
            cfg.norespawn, cfg.instantjob = false, false
            b:changeTeam(TEAM_POLICE, true, true)
            out.silentDead = state(b).alive == false
        end, 0.5 },
        { "silentSpawn", function() b:Spawn() b:SetPos(Vector(-2800, -300, -140)) end },
        { "silentAfter", function()
            out.killedSilently = state(b)
            cfg.norespawn = true
            b:changeTeam(TEAM_CITIZEN, true, true)
        end },
        -- 5. job weapons into the inventory: police glock -> slot; then back to citizen
        { "loadoutInvOn", function()
            RunConsoleCommand("advinv_darkrp_loadout_to_inventory", "1") -- applied on the next frame
            I.TakeOff(b, "PrimaryWep")
        end, 0.3 },
        { "loadoutInv", function()
            out.loadoutInvOn = GetConVar("advinv_darkrp_loadout_to_inventory"):GetBool()
            b:changeTeam(TEAM_POLICE, true, true)
        end, 1.2 },
        { "loadoutInvPolice", function()
            out.loadoutPolice = state(b) -- the glock in the sidearm slot; sc_billets not converted
            out.policeMayDropGlock = I.MayLeave(b, I.SlotRef(b, "SecondaryWep"))
            local saved = I.Serialize(b)
            if isstring(saved) then saved = util.JSONToTable(saved) end
            out.glockSaved = saved.s.SecondaryWep ~= nil -- never saved
            -- into the pockets: still the job's
            local item = I.TakeOff(b, "SecondaryWep")
            out.markedInPockets = item and item.j == true
            if item then I.Store(b, item) end
            b:changeTeam(TEAM_CITIZEN, true, true)
        end, 1.2 },
        { "loadoutInvCitizen", function()
            out.loadoutBackToCitizen = state(b) -- no glock anywhere
            b:changeTeam(TEAM_POLICE, true, true)
        end, 1.2 },
        { "policeAgain", function()
            out.policeAgain = state(b) -- the glock again, from the loadout
            GetConVar("advinv_death_drop"):SetInt(3)
            out.__bodiesBefore = table.Copy(I.Bodies)
            b:Kill()
        end, 0.8 },
        { "death", function()
            -- (the body of this death: an earlier death of the test may have left one)
            local body
            for e in pairs(I.Bodies) do if IsValid(e) and not out.__bodiesBefore[e] then body = e end end
            out.__bodiesBefore = nil
            local onBody = {}
            if IsValid(body) then
                for cat, it in pairs(body.AdvInvSlots or {}) do onBody[#onBody + 1] = cat .. "=" .. (it.c or I.IDClass[it.id]) end
                for _, it in ipairs(I.Get(body, "Uniform")) do onBody[#onBody + 1] = it.c or I.IDClass[it.id] end
            end
            table.sort(onBody)
            out.bodyAfterPoliceDeath = table.concat(onBody, " ")
            local dropped = {}
            for _, e in ipairs(ents.FindInSphere(b:GetPos(), 200)) do if e:IsWeapon() and not IsValid(e:GetOwner()) then dropped[#dropped + 1] = e:GetClass() end end
            out.droppedAtDeath = table.concat(dropped, " ")
        end },
    })
end)
