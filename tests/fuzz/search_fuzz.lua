-- Search fuzzer (listen game, DarkRP): the host searches a bot (search allowed for the test) and
-- does random real actions on the bot's things (move to himself, drop, equip, unload, take an
-- equipped weapon), the bot dies now and then. After each action the item census (fuzz_sv.lua)
-- must be unchanged; job items never leave the bot (dropspawnedweapons off). Result in SEARCHFUZZ.
local done = ASYNC(240)
local I = AdvInv
local p = Entity(1)
local STEPS = SEARCHFUZZ_STEPS or 250
math.randomseed(SEARCHFUZZ_SEED or 1)
local census, diff = BUGFZ.census, BUGFZ.diff
local cfg = GAMEMODE.Config
local dsw = cfg.dropspawnedweapons
cfg.dropspawnedweapons = false
for _, b in ipairs(player.GetBots()) do b:Kick("x") end
for _, e in ipairs(ents.GetAll()) do
    if (I.IsBody(e) or (I.ItemFromEntity(e) and not IsValid(e:GetOwner()))) and not e:IsPlayer() then e:Remove() end
end
local out = { fails = {}, seen = {} }
local function seen(k) out.seen[k] = (out.seen[k] or 0) + 1 end
local function act(ply, a, values)
    local i = 0
    local function nxt() i = i + 1 return values[i] end
    local saved = { net.ReadEntity, net.ReadUInt, net.ReadBool, net.ReadString }
    net.ReadEntity, net.ReadUInt, net.ReadBool, net.ReadString = nxt, nxt, nxt, nxt
    local ok, r1 = pcall(I.ActHandlers[a], ply)
    net.ReadEntity, net.ReadUInt, net.ReadBool, net.ReadString = saved[1], saved[2], saved[3], saved[4]
    if not ok then out.fails[#out.fails + 1] = "ERROR " .. tostring(r1) end
    return ok and r1
end
local function box(ammo, r) local id, c = I.AmmoBoxFor(ammo) return { id = id, c = c, r = r } end
local B
local function kit()
    I.SetDefaults(B)
    local C = I.ClassID
    local vest, pack
    for class in pairs(C) do
        local t = scripted_ents.Get(class)
        if t and t.AdvInvAvailable ~= false and not t.AdvInvCompat and not t.AdvInvModelGearPack then
            if t.AdvInvCategory == "Vest" and (t.MaxLoad or 0) >= 40 and not vest then vest = class end
            if t.AdvInvCategory == "Rucksack" and (t.MaxLoad or 0) >= 60 and not pack then pack = class end
        end
    end
    I.Equip(B, { id = C[vest], a = 50 }, { box("SMG1", 45), box("Pistol", 18), I.ItemForWeaponClass("weapon_357", 6) })
    local gid, gc = I.AmmoBoxFor("Grenade")
    I.Equip(B, { id = C[pack], a = 0 }, { box("Buckshot", 12), I.ItemForWeaponClass("weapon_shotgun", 4),
        { id = gid, c = gc, r = 1, j = true }, { id = gid, c = gc, r = 1 }, { id = I.GENERIC_ENTITY, c = "item_healthkit" } })
    I.Equip(B, I.ItemForWeaponClass("weapon_smg1", 30))
    I.Equip(B, I.ItemForWeaponClass("weapon_pistol", 10))
    B.AdvInvJobSlot = B.AdvInvJobSlot or {}
    B.AdvInvJobSlot.SecondaryWep = true -- (the pistol is the job's)
    local u = I.Get(B, "Uniform")
    u[#u + 1] = box("AR2", 30)
    local jr = I.ItemForWeaponClass("weapon_crossbow", 2) jr.j = true u[#u + 1] = jr
    I.MarkDirty(B, "Uniform")
end

timer.Simple(0.5, function() B = player.CreateNextBot("Searched") end)
timer.Simple(2, function()
    p:SetPos(Vector(-750, -1575, -144)) B:SetPos(Vector(-750, -1530, -144))
    I.SetDefaults(p)
    -- room for the host: a backpack
    for class, id in pairs(I.ClassID) do
        local t = scripted_ents.Get(class)
        if t and t.AdvInvCategory == "Rucksack" and (t.MaxLoad or 0) >= 60 and not t.AdvInvCompat and not t.AdvInvModelGearPack then I.Equip(p, { id = id, a = 0 }, {}) break end
    end
    kit()
    local realSearching = I.IsSearching
    I.IsSearching = function(a, t) if a == p and t == B then return true end return realSearching(a, t) end
    local base = census()
    local step = 0
    local CONTS = { "Uniform", "Vest", "Rucksack" }
    local WCATS = { "PrimaryWep", "SecondaryWep", "RocketLauncher" }
    local log = {}
    timer.Create("SearchFuzz", 0.1, 0, function()
        step = step + 1
        if step > STEPS or not IsValid(B) then
            timer.Remove("SearchFuzz")
            I.IsSearching = realSearching
            cfg.dropspawnedweapons = dsw
            out.steps = step - 1
            if IsValid(B) then B:Kick("done") end
            for _, e in ipairs(ents.GetAll()) do
                if (I.IsBody(e) or (I.ItemFromEntity(e) and not IsValid(e:GetOwner()))) and not e:IsPlayer() then e:Remove() end
            end
            I.SetDefaults(p)
            SEARCHFUZZ = out
            return done(out)
        end
        p.AdvInvActCount, p.AdvInvActWindow = 0, 0
        local r = math.random(100)
        local what
        local function pickItem()
            local cont = CONTS[math.random(#CONTS)]
            local list = I.HasContainer(B, cont) and I.Get(B, cont) or {}
            if #list == 0 then return end
            local idx = math.random(#list)
            return cont, idx, I.ItemCheck(list[idx])
        end
        if not B:Alive() then
            B:Spawn()
            timer.Simple(0, function() if IsValid(B) then kit() base = census() end end)
            what = "respawn+kit"
        elseif r <= 30 then
            local cont, idx, chk = pickItem()
            if cont then
                local toCont = I.HasContainer(p, "Rucksack") and "Rucksack" or "Uniform"
                what = "MOVE " .. cont .. "#" .. idx
                if act(p, I.ACT.MOVE, { B, I.ContID[cont], idx, chk, p, I.ContID[toCont], math.random(1, 3) }) then seen("move") end
            end
        elseif r <= 45 then
            local cont, idx, chk = pickItem()
            if cont then what = "DROP " .. cont .. "#" .. idx if act(p, I.ACT.DROP, { B, I.ContID[cont], idx, chk, math.random(1, 3) }) then seen("drop") end end
        elseif r <= 58 then
            local cont, idx, chk = pickItem()
            if cont then what = "EQUIP " .. cont .. "#" .. idx if act(p, I.ACT.EQUIP, { B, I.ContID[cont], idx, chk }) then seen("equip") end end
        elseif r <= 70 then
            local cont, idx, chk = pickItem()
            if cont then what = "UNLOAD " .. cont .. "#" .. idx if act(p, I.ACT.UNLOAD, { false, B, I.ContID[cont], idx, chk }) then seen("unload") end end
        elseif r <= 82 then
            local cat = WCATS[math.random(#WCATS)]
            what = "TAKE_SLOT " .. cat
            if act(p, I.ACT.SEARCH, { I.SEARCH.TAKE_SLOT, B, I.CategoryID[cat] }) then seen("takeSlot") end
        elseif r <= 92 then
            -- the host empties his own pockets/pack back onto the ground (things he took leave him too)
            local cont = I.HasContainer(p, "Rucksack") and "Rucksack" or "Uniform"
            local list = I.Get(p, cont)
            if #list > 0 then
                local idx = math.random(#list)
                what = "host DROP " .. cont .. "#" .. idx
                act(p, I.ACT.DROP, { p, I.ContID[cont], idx, I.ItemCheck(list[idx]), 1 })
            end
        elseif r <= 96 then
            what = "host picks up"
            for _, e in ipairs(ents.FindInSphere(p:GetPos(), 300)) do
                if not e:IsPlayer() and I.ItemFromEntity(e) and not IsValid(e:GetOwner()) then p.AdvInvUseDelay = 0 I.Use(p, e) break end
            end
        else
            what = "bot dies"
            B:Kill()
            seen("death")
        end
        log[#log + 1] = what or "-"
        -- (a death moves his things to his body: the census counts bodies too; the job's items go, uncounted)
        timer.Simple(0.05, function()
            local d = diff(base, census())
            if #d > 0 then
                out.fails[#out.fails + 1] = string.format("step %d (%s): %s ; before: %s", step, what or "-", table.concat(d, " ; "),
                    table.concat(log, ", ", math.max(1, #log - 6)))
                base = census()
            end
        end)
    end)
end)
