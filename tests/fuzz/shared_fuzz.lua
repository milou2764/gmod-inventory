-- Shared containers fuzzer (listen game, DarkRP): the host and a bot act in the same tick on one crate and one bank; derived from the search fuzzer: (search allowed for the test) and
-- does random real actions on the bot's things (move to himself, drop, equip, unload, take an
-- equipped weapon), the bot dies now and then. After each action the item census (fuzz_sv.lua)
-- must be unchanged; job items never leave the bot (dropspawnedweapons off). Result in SEARCHFUZZ.
local done = ASYNC(240)
local I = AdvInv
local p = Entity(1)
local STEPS = SHAREDFUZZ_STEPS or 250
math.randomseed(SHAREDFUZZ_SEED or 1)
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
    I.Actor = ply
    local ok, r1 = pcall(I.ActHandlers[a], ply)
    I.Actor = nil
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


local crate, bank
timer.Simple(0.5, function() B = player.CreateNextBot("Sharer") end)
timer.Simple(2, function()
    p:SetPos(Vector(-750, -1575, -144)) B:SetPos(Vector(-750, -1530, -144))
    for _, e in ipairs(ents.FindByClass("advinv_crate")) do e:Remove() end
    for _, e in ipairs(ents.FindByClass("advinv_bank")) do e:Remove() end
    kit() -- (the bot: vest, pack, weapons, job items)
    I.SetDefaults(p)
    local packID
    for class, id in pairs(I.ClassID) do
        local t = scripted_ents.Get(class)
        if t and t.AdvInvCategory == "Rucksack" and (t.MaxLoad or 0) >= 60 and not t.AdvInvCompat and not t.AdvInvModelGearPack then packID = id break end
    end
    I.Equip(p, { id = packID, a = 0 }, { box("SMG1", 20), box("357", 6), I.ItemForWeaponClass("weapon_pistol", 5) })
    crate = ents.Create("advinv_crate") crate:SetPos(Vector(-705, -1550, -124)) crate:Spawn()
    bank = ents.Create("advinv_bank") bank:SetPos(Vector(-795, -1550, -144)) bank:SetAngles(Angle(0, 0, 0)) bank:Spawn()
    for _, ent in ipairs({ crate, bank }) do local ph = ent:GetPhysicsObject() if IsValid(ph) then ph:EnableMotion(false) end end
    table.insert(I.Get(crate, "Storage"), box("AR2", 30))
    table.insert(I.Get(crate, "Storage"), I.ItemForWeaponClass("weapon_crossbow", 1))
    table.insert(I.Get(crate, "Storage"), box("Buckshot", 8))
    I.MarkDirty(crate, "Storage")
    for _, who in ipairs({ p, B }) do local S = I.Get(bank, "Storage", who) for k = #S, 1, -1 do S[k] = nil end end
    timer.Simple(0.3, function()
        local base = census()
        local step = 0
        local log = {}
        local function mine(actor)
            local conts = { "Uniform", "Vest", "Rucksack" }
            local cont = conts[math.random(#conts)]
            local list = I.HasContainer(actor, cont) and I.Get(actor, cont) or {}
            if #list == 0 then return end
            local idx = math.random(#list)
            return cont, idx, I.ItemCheck(list[idx])
        end
        local function shared(actor)
            local h = math.random(2) == 1 and crate or bank
            I.Actor = actor
            local list = I.Get(h, "Storage")
            I.Actor = nil
            if #list == 0 then return h end
            local idx = math.random(#list)
            return h, idx, I.ItemCheck(list[idx])
        end
        local function one(actor)
            actor.AdvInvActCount, actor.AdvInvActWindow = 0, 0
            local r = math.random(100)
            if r <= 35 then
                local cont, idx, chk = mine(actor)
                if not cont then return "put -" end
                local h = math.random(2) == 1 and crate or bank
                if act(actor, I.ACT.MOVE, { actor, I.ContID[cont], idx, chk, h, I.ContID.Storage, math.random(1, 3) }) then seen("put") end
                return "put " .. actor:Nick() .. " " .. cont .. "#" .. idx .. " -> " .. h:GetClass()
            elseif r <= 70 then
                local h, idx, chk = shared(actor)
                if not idx then return "take -" end
                local to = I.HasContainer(actor, "Rucksack") and "Rucksack" or "Uniform"
                if act(actor, I.ACT.MOVE, { h, I.ContID.Storage, idx, chk, actor, I.ContID[to], math.random(1, 3) }) then seen("take") end
                return "take " .. actor:Nick() .. " " .. h:GetClass() .. "#" .. idx
            elseif r <= 80 then
                local h, idx, chk = shared(actor)
                if not idx then return "drop -" end
                if act(actor, I.ACT.DROP, { h, I.ContID.Storage, idx, chk, math.random(1, 2) }) then seen("drop") end
                return "drop " .. actor:Nick() .. " " .. h:GetClass() .. "#" .. idx
            elseif r <= 88 then
                local h, idx, chk = shared(actor)
                if not idx then return "equip -" end
                if act(actor, I.ACT.EQUIP, { h, I.ContID.Storage, idx, chk }) then seen("equip") end
                return "equip " .. actor:Nick() .. " " .. h:GetClass() .. "#" .. idx
            elseif r <= 94 then
                local h, idx, chk = shared(actor)
                if not idx then return "unload -" end
                if act(actor, I.ACT.UNLOAD, { false, h, I.ContID.Storage, idx, chk }) then seen("unload") end
                return "unload " .. actor:Nick() .. " " .. h:GetClass() .. "#" .. idx
            else
                for _, e in ipairs(ents.FindInSphere(actor:GetPos(), 300)) do
                    if not e:IsPlayer() and I.ItemFromEntity(e) and not IsValid(e:GetOwner()) then actor.AdvInvUseDelay = 0 I.Use(actor, e) seen("pickup") break end
                end
                return "pickup " .. actor:Nick()
            end
        end
        timer.Create("SharedFuzz", 0.1, 0, function()
            step = step + 1
            if step > STEPS or not IsValid(B) then
                timer.Remove("SharedFuzz")
                cfg.dropspawnedweapons = dsw
                out.steps = step - 1
                if IsValid(B) then B:Kick("done") end
                for _, e in ipairs({ crate, bank }) do if IsValid(e) then e:Remove() end end
                for _, e in ipairs(ents.GetAll()) do
                    if (I.IsBody(e) or (I.ItemFromEntity(e) and not IsValid(e:GetOwner()))) and not e:IsPlayer() then e:Remove() end
                end
                I.SetDefaults(p)
                SHAREDFUZZ = out
                return done(out)
            end
            -- both in the same tick (indexes taken before either acts: the race the item check guards)
            local a1, a2 = one(p), one(B)
            log[#log + 1] = a1 .. " & " .. a2
            timer.Simple(0.05, function()
                local d = diff(base, census())
                if #d > 0 then
                    out.fails[#out.fails + 1] = string.format("step %d: %s ; before: %s", step, table.concat(d, " ; "), table.concat(log, " | ", math.max(1, #log - 3)))
                    base = census()
                end
            end)
        end)
    end)
end)
