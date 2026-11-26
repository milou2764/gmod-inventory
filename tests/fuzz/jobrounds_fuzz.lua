-- Job rounds fuzzer (test server, bot, DarkRP with dropspawnedweapons off): a bound job SMG and a
-- personal pistol firing SMG1 (a test SWEP) share one reserve. Random weapon switches, reserve
-- drops (as reloads), unloading the personal weapon, splits, drops of ordinary boxes. Invariants:
-- job rounds and ordinary rounds never grow; everything removed is counted; with the personal
-- weapon in hand, job rounds never move. Result in JOBFUZZ.
local I = AdvInv
local SEED, STEPS = JOBFUZZ_SEED or 1, JOBFUZZ_STEPS or 200
math.randomseed(SEED)
JOBFUZZ = { running = true, fails = {}, seen = {} }
local R = JOBFUZZ
local function seen(k) R.seen[k] = (R.seen[k] or 0) + 1 end
local cfg = GAMEMODE.Config
local dsw = cfg.dropspawnedweapons
cfg.dropspawnedweapons = false

local SW = weapons.Get("weapon_base") and {} or nil
SW.Base = "weapon_base"
SW.PrintName = "Test pistol SMG1"
SW.HoldType = "pistol"
SW.Slot = 1
SW.ViewModel = "models/weapons/c_pistol.mdl"
SW.WorldModel = "models/weapons/w_pistol.mdl"
SW.Primary = { ClipSize = 18, DefaultClip = 0, Automatic = false, Ammo = "SMG1" }
SW.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
weapons.Register(SW, "zz_test_pistol_smg1")

for _, b in ipairs(player.GetBots()) do b:Kick("x") end
local B
local bid, bc = I.AmmoBoxFor("SMG1")
local function count()
    local J, O = 0, 0
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        for _, it in ipairs(I.HasContainer(B, cont) and I.Get(B, cont) or {}) do
            if it.id == bid then if it.j then J = J + (it.r or 0) else O = O + (it.r or 0) end end
            if I.Info(it.id, it.c).weaponClass == "zz_test_pistol_smg1" then O = O + (it.r or 0) end
        end
    end
    local js, ps = B:GetWeapon("weapon_smg1"), B:GetWeapon("zz_test_pistol_smg1")
    if IsValid(js) then J = J + math.max(js:Clip1(), 0) end
    if IsValid(ps) then O = O + math.max(ps:Clip1(), 0) end
    return J, O
end
local function act(a, values)
    local i = 0
    local function nxt() i = i + 1 return values[i] end
    local saved = { net.ReadEntity, net.ReadUInt, net.ReadBool, net.ReadString }
    net.ReadEntity, net.ReadUInt, net.ReadBool, net.ReadString = nxt, nxt, nxt, nxt
    I.Actor = B B.AdvInvActCount, B.AdvInvActWindow = 0, 0
    local ok, e = pcall(I.ActHandlers[a], B)
    I.Actor = nil
    net.ReadEntity, net.ReadUInt, net.ReadBool, net.ReadString = saved[1], saved[2], saved[3], saved[4]
    if not ok then R.fails[#R.fails + 1] = "action error: " .. tostring(e) end
    return ok and e
end

timer.Simple(0.5, function() B = player.CreateNextBot("JobRounds") end)
timer.Simple(2, function()
    I.SetDefaults(B)
    local smg = I.ItemForWeaponClass("weapon_smg1", 30) smg.j = true
    I.Equip(B, smg)
    I.Equip(B, { id = I.GENERIC_WEAPON, c = "zz_test_pistol_smg1", r = 10, a = 0 })
    local u = I.Get(B, "Uniform")
    for _ = 1, 3 do u[#u + 1] = { id = bid, c = bc, r = 20, a = 0, j = true } end
    for _ = 1, 3 do u[#u + 1] = { id = bid, c = bc, r = 25, a = 0 } end
    I.MarkDirty(B, "Uniform")
    local J0, O0, consumedJ, consumedO, dropped = nil, nil, 0, 0, 0
    local step = 0
    timer.Simple(0.5, function()
        J0, O0 = count()
        R.start = { J = J0, O = O0 }
        local lastJ, lastO = J0, O0
        timer.Create("JobRoundsFuzz", 0.15, 0, function()
            step = step + 1
            if step > STEPS or not IsValid(B) then
                timer.Remove("JobRoundsFuzz")
                R.final = { J = select(1, count()), O = select(2, count()), consumedJ = consumedJ, consumedO = consumedO, dropped = dropped }
                cfg.dropspawnedweapons = dsw
                for _, e in ipairs(ents.FindInSphere(B:GetPos(), 400)) do if not e:IsPlayer() and I.ItemFromEntity(e) and not IsValid(e:GetOwner()) then e:Remove() end end
                B:Kick("done")
                R.ok = #R.fails == 0
                R.running = false
                return
            end
            if not B:Alive() then B:Spawn() end
            local active = B:GetActiveWeapon()
            local jobInHand = IsValid(active) and active:GetClass() == "weapon_smg1"
            local r = math.random(100)
            local what
            local J1, O1 = count()
            if r <= 25 then
                local to = math.random(2) == 1 and "weapon_smg1" or "zz_test_pistol_smg1"
                if B:HasWeapon(to) then B:SelectWeapon(to) end
                what = "switch " .. to seen("switch")
            elseif r <= 60 then
                -- a reload's draw on the reserve, from whatever is in hand
                local before = B:GetAmmoCount("SMG1")
                local n = math.random(1, 15)
                B:RemoveAmmo(n, "SMG1")
                local took = before - B:GetAmmoCount("SMG1")
                if jobInHand then consumedJ = consumedJ + took else consumedO = consumedO + took end
                what = "draw " .. took .. (jobInHand and " (job in hand)" or " (personal in hand)") seen("draw")
            elseif r <= 70 then
                local pcat = I.SlotOfWeaponClass(B, "zz_test_pistol_smg1")
                if pcat then act(I.ACT.UNLOAD, { true, I.CategoryID[pcat] }) end
                what = "unload personal" seen("unload")
            elseif r <= 82 then
                local list = I.Get(B, "Uniform")
                local idx = math.random(math.max(#list, 1))
                local it = list[idx]
                if it and it.id == bid and (it.r or 0) > 1 then
                    act(I.ACT.SPLIT, { B, I.ContID.Uniform, idx, I.ItemCheck(it), math.random(1, it.r - 1) })
                    what = "split " .. (it.j and "job" or "ordinary") seen("split")
                end
            elseif r <= 90 then
                local list = I.Get(B, "Uniform")
                for idx, it in ipairs(list) do
                    if it.id == bid and not it.j then
                        local n = it.r or 0
                        local _, oB = count() act(I.ACT.DROP, { B, I.ContID.Uniform, idx, I.ItemCheck(it), 1 }) local _, oA = count() dropped = dropped + (oB - oA)
                        what = "drop ordinary " .. n seen("drop")
                        break
                    end
                end
            else
                local list = I.Get(B, "Uniform")
                for idx, it in ipairs(list) do
                    if it.j then
                        local jB, oB = count() local res = act(I.ACT.DROP, { B, I.ContID.Uniform, idx, I.ItemCheck(it), 1 }) local jA, oA = count() dropped = dropped + (oB - oA)
                        if jA ~= jB then R.fails[#R.fails + 1] = "step " .. step .. ": a job box left (" .. jB .. "->" .. jA .. ")" end
                        what = "try drop job -> " .. tostring(res) seen("job drop tried")
                        break
                    end
                end
            end
            -- (the reserve follows a tick later)
            timer.Simple(0.05, function()
                if not IsValid(B) then return end
                local J2, O2 = count()
                if J2 > lastJ then R.fails[#R.fails + 1] = "step " .. step .. " " .. tostring(what) .. ": job rounds grew " .. lastJ .. "->" .. J2 end
                if O2 > lastO then R.fails[#R.fails + 1] = "step " .. step .. " " .. tostring(what) .. ": ordinary rounds grew " .. lastO .. "->" .. O2 end
                if J2 + O2 + consumedJ + consumedO + dropped ~= J0 + O0 then
                    R.fails[#R.fails + 1] = string.format("step %d %s: rounds %d+%d+used %d+%d+dropped %d ~= %d", step, tostring(what), J2, O2, consumedJ, consumedO, dropped, J0 + O0)
                    J0, O0 = J2, O2 -- (report once, then count from here)
                    consumedJ, consumedO, dropped = 0, 0, 0
                end
                if what and what:find("personal in hand") and J2 ~= J1 then R.fails[#R.fails + 1] = "step " .. step .. ": job rounds moved with the personal weapon in hand " .. J1 .. "->" .. J2 end
                lastJ, lastO = J2, O2
            end)
        end)
    end)
end)
return "job rounds fuzz started, seed " .. SEED
