-- Job isolation: advinv_job_isolation, advinv_isolated_jobs, AdvInvIsolated in a job.
local done = ASYNC(40)
local I = AdvInv
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
local out = {}
local all, list = GetConVar("advinv_job_isolation"), GetConVar("advinv_isolated_jobs")
local function restore()
    all:SetBool(false) list:SetString("")
    for _, j in pairs(RPExtraTeams) do j.AdvInvIsolated = nil end
end
local function step(steps, i)
    i = i or 1
    if i > #steps then restore() return done(out) end
    local ok, err = pcall(steps[i][2])
    if not ok then out["error_" .. steps[i][1]] = tostring(err) end
    timer.Simple(steps[i][3] or 0.8, function() step(steps, i + 1) end)
end
local function fill(b)
    I.SetDefaults(b)
    I.Equip(b, { id = I.ClassID.advinv_barney_helmet, a = 90 })
    I.Equip(b, { id = I.ClassID.advinv_hl2_ar2, r = 17 })
    I.Store(b, { id = I.ClassID.advinv_ammo_ar2, r = 30 })
    I.Store(b, { id = I.GENERIC_AMMO, c = "Grenade", r = 1 })
end
local function state(b)
    local n = 0
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do n = n + #I.Get(b, cont) end
    return string.format("%s: helmet=%s primary=%s ar2InHands=%s items=%d reserve=%d",
        team.GetName(b:Team()), I.IDClass[b:GetNW2Int("Helmet")] or "none", I.IDClass[b:GetNWInt("PrimaryWep")] or "none",
        tostring(b:HasWeapon("weapon_ar2")), n, b:GetAmmoCount("AR2"))
end
local function cmd(t) return RPExtraTeams[t].command end
player.CreateNextBot("Iso")
timer.Simple(1.5, function()
    local b = player.GetBots()[1]
    b:SetPos(Vector(-2800, -300, -140))
    restore()
    b:changeTeam(TEAM_CITIZEN, true, true)
    step({
        { "off", function() fill(b) b:changeTeam(TEAM_POLICE, true, true) end },
        { "offAfter", function()
            out["1 off, citizen->police (kept)"] = state(b)
            b:changeTeam(TEAM_CITIZEN, true, true)
            list:SetString("Medic, " .. cmd(TEAM_POLICE)) -- listed: police (by command) and medic (by name)
        end },
        { "listed", function() fill(b) b:changeTeam(TEAM_POLICE, true, true) end },
        { "listedAfter", function()
            out["2 listed, citizen->police (forgotten)"] = state(b)
            fill(b)
            b:changeTeam(TEAM_CITIZEN, true, true)
        end },
        { "leaving", function()
            out["3 listed, police->citizen (forgotten)"] = state(b)
            fill(b)
            b:changeTeam(TEAM_GUN, true, true)
        end },
        { "notListed", function()
            out["4 listed, citizen->gun dealer (kept)"] = state(b)
            b:changeTeam(TEAM_MEDIC, true, true)
        end },
        { "byName", function()
            out["5 listed by name, gun dealer->medic (forgotten)"] = state(b)
            list:SetString("")
            all:SetBool(true)
            b:changeTeam(TEAM_CITIZEN, true, true)
        end },
        { "all", function()
            fill(b)
            b:changeTeam(TEAM_GUN, true, true)
        end },
        { "allAfter", function()
            out["6 every job, citizen->gun dealer (forgotten)"] = state(b)
            RPExtraTeams[TEAM_GUN].AdvInvIsolated = false
            RPExtraTeams[TEAM_MEDIC].AdvInvIsolated = false
            fill(b)
            b:changeTeam(TEAM_MEDIC, true, true)
        end },
        { "optOut", function()
            out["7 every job, both opted out, gun dealer->medic (kept)"] = state(b)
            local hookKept
            hook.Add("AdvInv_JobIsolation", "test", function() return false end)
            b:changeTeam(TEAM_CITIZEN, true, true)
            hook.Remove("AdvInv_JobIsolation", "test")
        end },
        { "hook", function() out["8 every job, hook says keep, medic->citizen (kept)"] = state(b) end },
    })
end)
