-- Inventory fuzzer, client half: random actions sent as the inventory window sends them.
-- BUGFZ_CL.burst(n, seed) -> description of the actions sent
local I = AdvInv
BUGFZ_CL = BUGFZ_CL or {}

local function holders()
    local list = { LocalPlayer() }
    for _, e in ipairs(ents.GetAll()) do
        if IsValid(e) and (e:GetClass() == "advinv_crate" or e:GetClass() == "advinv_bank" or (I.IsBody and I.IsBody(e))) then list[#list + 1] = e end
    end
    return list
end

local CONTS = { "Uniform", "Vest", "Rucksack", "Storage" }
local function pick(t) return t[math.random(#t)] end
local function writeCont(c) net.WriteUInt(I.ContID[c], 3) end
local function name(e) return e == LocalPlayer() and "me" or (IsValid(e) and e:GetClass() or "?") end

local function index(h, c)
    local n = #I.Get(h, c)
    local r = math.random()
    if r < 0.85 and n > 0 then return math.random(n) end
    if r < 0.93 then return n + 1 end
    return pick({ 0, 255, n + 2 })
end

local function chk(h, c, idx)
    local it = I.Get(h, c)[idx]
    if it and math.random() < 0.9 then return I.ItemCheck(it) end
    return math.random(0, 2147483647)
end

local function cats()
    local t = {}
    for id, cat in pairs(AdvInv.IDCategory) do t[#t + 1] = { id = id, cat = cat } end
    return t
end

function BUGFZ_CL.burst(n, seed)
    math.randomseed(seed)
    local log = {}
    for opened in pairs(BUGFZ_CL.opened or {}) do if not IsValid(opened) then BUGFZ_CL.opened[opened] = nil end end
    BUGFZ_CL.opened = BUGFZ_CL.opened or {}
    for _, h in ipairs(holders()) do
        if h ~= LocalPlayer() and not BUGFZ_CL.opened[h] then
            I.Act(I.ACT.OPEN, function() net.WriteEntity(h) end)
            BUGFZ_CL.opened[h] = true
        end
    end
    for _ = 1, n do
        local hs = holders()
        local a = math.random(100)
        if a <= 15 then -- USE (an item of mine: take a weapon or grenade in hand, swap, consume)
            local c = pick(CONTS)
            local idx = index(LocalPlayer(), c)
            I.Act(I.ACT.USE, function() net.WriteEntity(LocalPlayer()) writeCont(c) net.WriteUInt(idx, 8) net.WriteUInt(chk(LocalPlayer(), c, idx), 32) end)
            log[#log + 1] = string.format("USE me.%s#%d", c, idx)
        elseif a <= 30 then -- MOVE
            local from, fc, to, tc = pick(hs), pick(CONTS), pick(hs), pick(CONTS)
            local idx, cnt = index(from, fc), math.random() < 0.8 and math.random(3) or pick({ 0, 255 })
            I.Act(I.ACT.MOVE, function()
                net.WriteEntity(from) writeCont(fc) net.WriteUInt(idx, 8) net.WriteUInt(chk(from, fc, idx), 32)
                net.WriteEntity(to) writeCont(tc) net.WriteUInt(cnt, 8)
            end)
            log[#log + 1] = string.format("MOVE %s.%s#%d -> %s.%s x%d", name(from), fc, idx, name(to), tc, cnt)
        elseif a <= 42 then -- DROP
            local h, c = pick(hs), pick(CONTS)
            local idx, cnt = index(h, c), math.random(3)
            I.Act(I.ACT.DROP, function() net.WriteEntity(h) writeCont(c) net.WriteUInt(idx, 8) net.WriteUInt(chk(h, c, idx), 32) net.WriteUInt(cnt, 8) end)
            log[#log + 1] = string.format("DROP %s.%s#%d x%d", name(h), c, idx, cnt)
        elseif a <= 57 then -- EQUIP
            local h, c = pick(hs), pick(CONTS)
            local idx = index(h, c)
            I.Act(I.ACT.EQUIP, function() net.WriteEntity(h) writeCont(c) net.WriteUInt(idx, 8) net.WriteUInt(chk(h, c, idx), 32) end)
            log[#log + 1] = string.format("EQUIP %s.%s#%d", name(h), c, idx)
        elseif a <= 72 then -- UNEQUIP
            local cc = pick(cats())
            local drop = math.random() < 0.3
            local to, tc = pick(hs), pick(CONTS)
            I.Act(I.ACT.UNEQUIP, function()
                net.WriteUInt(cc.id, 4) net.WriteBool(drop)
                if not drop then net.WriteEntity(to) writeCont(tc) end
            end)
            log[#log + 1] = string.format("UNEQUIP %s %s", cc.cat, drop and "drop" or (name(to) .. "." .. tc))
        elseif a <= 82 then -- SPLIT
            local h, c = pick(hs), pick(CONTS)
            local idx = index(h, c)
            local it = I.Get(h, c)[idx]
            local r = it and (it.r or 0) > 1 and math.random(it.r - 1) or pick({ 0, 1, 65535 })
            I.Act(I.ACT.SPLIT, function() net.WriteEntity(h) writeCont(c) net.WriteUInt(idx, 8) net.WriteUInt(chk(h, c, idx), 32) net.WriteUInt(r, I.NET_ROUNDS_BITS) end)
            log[#log + 1] = string.format("SPLIT %s.%s#%d r%d", name(h), c, idx, r)
        elseif a <= 92 then -- UNLOAD
            if math.random() < 0.5 then
                local cc = pick(cats())
                I.Act(I.ACT.UNLOAD, function() net.WriteBool(true) net.WriteUInt(cc.id, 4) end)
                log[#log + 1] = "UNLOAD slot " .. cc.cat
            else
                local h, c = pick(hs), pick(CONTS)
                local idx = index(h, c)
                I.Act(I.ACT.UNLOAD, function() net.WriteBool(false) net.WriteEntity(h) writeCont(c) net.WriteUInt(idx, 8) net.WriteUInt(chk(h, c, idx), 32) end)
                log[#log + 1] = string.format("UNLOAD %s.%s#%d", name(h), c, idx)
            end
        elseif a <= 96 then -- LOOT a body's slot
            local bodies = {}
            for _, h in ipairs(hs) do if h ~= LocalPlayer() and I.IsBody(h) then bodies[#bodies + 1] = h end end
            if #bodies > 0 then
                local b, cc = pick(bodies), pick(cats())
                I.Act(I.ACT.LOOT, function() net.WriteEntity(b) net.WriteUInt(cc.id, 4) end)
                log[#log + 1] = "LOOT body " .. cc.cat
            end
        else -- CARRY
            local cc = pick(cats())
            local m = math.random(0, 7)
            I.Act(I.ACT.CARRY, function() net.WriteUInt(cc.id, 4) net.WriteUInt(m, I.CARRY_NET_BITS) end)
            log[#log + 1] = "CARRY " .. cc.cat .. " " .. m
        end
    end
    return table.concat(log, " | ")
end
