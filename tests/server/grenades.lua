-- Grenades as items (sh_grenades.lua, sv_grenades.lua). Needs CW 2.0 for the CW grenades.
local done = ASYNC(60)
local I = AdvInv
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
for _, e in ipairs(ents.FindByClass("cw_frag_grenade")) do if not IsValid(e:GetOwner()) then e:Remove() end end
local out = {}
local FRAG = "Frag Grenades"
local function items(ply, ammo)
    local n = 0
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        for _, it in ipairs(I.Get(ply, cont)) do
            if it.id == I.GENERIC_AMMO and it.c == ammo then n = n + it.r end
        end
    end
    return n
end
local function state(ply, ammo, class)
    local w = ply:GetWeapon(class)
    return { items = items(ply, ammo), reserve = ply:GetAmmoCount(ammo), clip = IsValid(w) and w:Clip1() or "-", weapon = IsValid(w) }
end
local function removeOne(ply, ammo) -- what DROP / MOVE do to the source container
    local list = I.Get(ply, "Uniform")
    for k = #list, 1, -1 do
        if list[k].c == ammo then
            local it = table.remove(list, k)
            I.MarkDirty(ply, "Uniform")
            return it
        end
    end
end
local function step(list, i)
    i = i or 1
    if i > #list then return done(out) end
    local ok, err = pcall(list[i][2])
    if not ok then out["error_" .. list[i][1]] = tostring(err) end
    timer.Simple(list[i][3] or 0.6, function() step(list, i + 1) end)
end
player.CreateNextBot("G")
timer.Simple(1.5, function()
    local b = player.GetBots()[1]
    b:SetPos(Vector(-2800, -300, -140))
    I.SetDefaults(b)
    local g
    step({
        { "def", function()
            local d = I.DefTable(I.GENERIC_AMMO, FRAG)
            out.def = d and { name = d.PrintName, cap = d.Capacity, mass = d.Mass, model = d.Model, grenade = d.Grenade }
            out.itemForWeapon = I.ItemForWeaponClass("cw_frag_grenade", 1)
            out.use = I.UseOf({ id = I.GENERIC_AMMO, c = FRAG, r = 1 })
            g = ents.Create("cw_frag_grenade") g:SetPos(b:GetPos() + Vector(30, 0, 20)) g:Spawn()
        end, 0.4 },
        { "pickup", function()
            b.AdvInvUseDelay = 0
            I.Use(b, g)
        end },
        { "afterPickup", function()
            out.afterPickup = { primary = b:GetNWInt("PrimaryWep"), secondary = b:GetNWInt("SecondaryWep"), s = state(b, FRAG, "cw_frag_grenade") }
            -- the spawn menu: the gamemode's Give, then the grenades it gave become items
            out.giveSWEPFlag = (hook.GetTable().PlayerGiveSWEP.AdvInv_GiveSWEP(b, "cw_frag_grenade", weapons.Get("cw_frag_grenade")) ~= nil) or b.AdvInvGiveSWEP ~= nil
            b:Give("cw_frag_grenade")
        end, 0.8 },
        { "afterGive", function()
            out.afterGive = state(b, FRAG, "cw_frag_grenade") -- 1 + what Give gave
            I.GiveRounds(b, FRAG, 3)
        end, 0.6 },
        { "jobChange", function()
            out.beforeJob = state(b, FRAG, "cw_frag_grenade")
            -- DarkRP's job change: strip weapons and ammo, then the loadout gives the job's grenade
            b:StripWeapons()
            b:RemoveAllAmmo()
            hook.Run("PlayerLoadout", b)
            b:Give("cw_frag_grenade")
        end, 1.5 },
        { "afterJob", function()
            out.afterJob = state(b, FRAG, "cw_frag_grenade") -- same items: a loadout only tops up
        end },
        { "throwThenDrop", function()
            out.beforeThrow = state(b, FRAG, "cw_frag_grenade")
            local w = b:GetWeapon("cw_frag_grenade")
            b:SelectWeapon("cw_frag_grenade")
            w:TakePrimaryAmmo(1) -- a throw...
            out.droppedSameTick = removeOne(b, FRAG) ~= nil -- ...and an item dropped in the same tick
        end, 0.8 },
        { "afterThrowDrop", function()
            out.afterThrowDrop = state(b, FRAG, "cw_frag_grenade") -- 2 fewer
            b:RemoveAmmo(1, FRAG) -- CW 2.0's quick grenade
        end, 0.6 },
        { "afterQuick", function()
            out.afterQuick = state(b, FRAG, "cw_frag_grenade")
            b:StripWeapon("cw_frag_grenade")
        end, 0.6 },
        { "afterStrip", function()
            out.afterStrip = state(b, FRAG, "cw_frag_grenade") -- stripped: not thrown
            local list = I.Get(b, "Uniform")
            local k
            for i, it in ipairs(list) do if it.c == FRAG then k = i end end
            out.useResult = k and { I.UseItem(b, list[k]) } or "no item"
        end, 0.6 },
        { "afterUse", function()
            out.afterUse = state(b, FRAG, "cw_frag_grenade")
            local list = I.Get(b, "Uniform")
            for k = #list, 1, -1 do if list[k].c == FRAG then table.remove(list, k) end end
            I.MarkDirty(b, "Uniform")
        end, 0.8 },
        { "afterDropAll", function()
            out.afterDropAll = state(b, FRAG, "cw_frag_grenade")
            b:Give("weapon_frag") -- HL2 grenade given by code
        end, 0.8 },
        { "hl2", function()
            out.hl2 = state(b, "Grenade", "weapon_frag")
            out.hl2Name = I.Info(I.GENERIC_AMMO, "Grenade").name
            -- respawn keeping the items (death drop below 3)
            b.AdvInvKeepNextSpawn = true
            b:KillSilent()
        end, 0.5 },
        { "respawn", function() b:Spawn() end, 1.5 },
        { "afterRespawn", function()
            out.afterRespawn = state(b, "Grenade", "weapon_frag") -- still 1 item, reserve 1
            b:Kill()
        end, 0.8 },
        { "death", function()
            local body
            for _, e in ipairs(ents.FindByClass("prop_ragdoll")) do if I.IsBody(e) then body = e end end
            local onBody = 0
            if IsValid(body) then for _, it in ipairs(I.Get(body, "Uniform")) do if it.c == "Grenade" then onBody = onBody + it.r end end end
            local dropped = 0
            for _, e in ipairs(ents.FindByClass("weapon_frag")) do if not IsValid(e:GetOwner()) then dropped = dropped + 1 end end
            out.death = { onBody = onBody, droppedWeapons = dropped }
        end },
    })
end)
