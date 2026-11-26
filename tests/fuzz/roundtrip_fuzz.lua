-- Save/load round trip (server, DarkRP, one bot): random saved inventories (gear with contents,
-- weapons with rounds and carry modes, boxes, grenades, generic items, items of a missing addon)
-- are loaded, saved, loaded again. Nothing may be created or lost on the way (each saved entry is
-- counted, wherever it lands), and a second round trip must give back exactly the same record.
-- Then random real actions on the loaded inventory, and the same check on what they left.
-- Records use the keys rtfuzz_<n> and are deleted at the end. Result in RTFUZZ.
local I = AdvInv
local SEED, ROUNDS = RTFUZZ_SEED or 1, RTFUZZ_ROUNDS or 60
math.randomseed(SEED)
RTFUZZ = { running = true, fails = {}, seen = {}, moved = {} }
local R = RTFUZZ
local function seen(k) R.seen[k] = (R.seen[k] or 0) + 1 end

-- items available, by category (no compat or model-bound gear: a bot can't wear those)
local byCat, boxes, weaponsInPockets = {}, {}, {}
for class, id in pairs(I.ClassID) do
    local t = scripted_ents.Get(class)
    local info = I.Info(id)
    if t and not t.AdvInvCompat and not t.AdvInvModelGearPack and not t.AdvInvModelGear and t.AdvInvAvailable ~= false and not I.IsGeneric(id) then
        if info.isBox and info.ammo and game.GetAmmoID(info.ammo) ~= -1 then boxes[#boxes + 1] = class
        elseif info.cat then
            byCat[info.cat] = byCat[info.cat] or {}
            table.insert(byCat[info.cat], class)
            if info.isWeapon and weapons.Get(info.weaponClass) or (info.isWeapon and string.StartWith(info.weaponClass or "", "weapon_")) then
                weaponsInPockets[#weaponsInPockets + 1] = class
            end
        end
    end
end
local function pick(l) return l and #l > 0 and l[math.random(#l)] or nil end
-- RTFUZZ_PACKS: gear of the installed playermodel packs too (AIS extensions), the bot wearing one of
-- their playermodels (shown by its bodygroups there, a fitted copy on the others)
local packByCat, packModels = {}, {}
if RTFUZZ_PACKS then
    for class, id in pairs(I.ClassID) do
        local t = scripted_ents.Get(class)
        if t and t.AdvInvModelGearPack and t.AdvInvAvailable then
            packByCat[t.AdvInvCategory] = packByCat[t.AdvInvCategory] or {}
            table.insert(packByCat[t.AdvInvCategory], class)
        end
    end
    for model in pairs(I.ModelGear or {}) do
        if util.IsValidModel(model) then packModels[#packModels + 1] = model end
    end
    table.sort(packModels)
end
-- what a real save holds: rounds only in a magazine (the RPG has none), armor only on armored gear
local function rounds(class)
    local info = I.Info(I.ClassID[class])
    return (info.clipSize or 0) > 0 and math.random(0, info.clipSize) or 0
end
local function armor(class)
    local info = I.Info(I.ClassID[class])
    return info.armor and math.random(0, info.armor) or 0
end
local GENERIC_ENTS = { "item_healthkit", "item_healthvial", "item_battery" }

local function entry(class, r, a, m, c, x)
    if x then return { class, r or 0, a or 0, m or 0, c or "", x } end
    if c then return { class, r or 0, a or 0, m or 0, c } end
    return { class, r or 0, a or 0, m }
end
local function anyItem()
    local r = math.random(100)
    if r <= 30 then
        local class = pick(boxes)
        local info = I.Info(I.ClassID[class])
        return entry(class, math.random(1, math.max(info.boxRounds or 1, 1)), 0)
    elseif r <= 40 then
        return entry(I.IDClass[I.GENERIC_AMMO] or I.GENERIC_AMMO, 1, 0, nil, "Grenade")
    elseif r <= 55 then
        return entry(I.IDClass[I.GENERIC_ENTITY] or I.GENERIC_ENTITY, 0, 0, nil, pick(GENERIC_ENTS))
    elseif r <= 75 then
        local class = pick(weaponsInPockets)
        return entry(class, rounds(class), 0)
    elseif r <= 85 then
        return entry("advinv_zz_missing_" .. math.random(3), math.random(0, 30), 0) -- an addon removed since
    elseif r <= 90 then
        return entry(I.IDClass[I.GENERIC_WEAPON] or I.GENERIC_WEAPON, 3, 0, nil, "weapon_zz_missing") -- a SWEP removed since
    else
        local class = pick(byCat.Helmet) or pick(boxes)
        return entry(class, 0, armor(class))
    end
end

local function randomRecord()
    local d = { v = 4, s = {}, c = {} }
    local function packItem() for _ = 1, 3 do local l = pick(table.ClearKeys(table.Copy(packByCat))) if l then return pick(l) end end end
    for _, cat in ipairs({ "Uniform", "Vest", "Rucksack", "Helmet", "Gasmask", "NVGs", "Radio" }) do
        if I.GearCat[cat] and math.random(100) <= 60 then
            if math.random(100) <= 12 then
                d.s[cat] = entry("advinv_zz_missing_gear_" .. cat, 0, math.random(0, 50))
            else
                local class = (packByCat[cat] and math.random(100) <= 60) and pick(packByCat[cat]) or pick(byCat[cat])
                if class then d.s[cat] = entry(class, 0, armor(class)) end
            end
        end
    end
    for _, cat in ipairs(I.WeaponCat) do
        if math.random(100) <= 60 then
            local class = pick(byCat[cat])
            if class then
                d.s[cat] = entry(class, rounds(class), 0, math.random(100) <= 50 and math.random(#I.CARRY_MODES) or nil)
            end
        end
    end
    for _, cont in ipairs({ "Uniform", "Vest", "Rucksack" }) do
        if cont == "Uniform" or d.s[cont] then
            d.c[cont] = {}
            for k = 1, math.random(0, cont == "Uniform" and 7 or 4) do
                local pc = RTFUZZ_PACKS and math.random(100) <= 15 and packItem()
                d.c[cont][k] = pc and entry(pc, 0, armor(pc)) or anyItem()
            end
        end
    end
    return d
end

-- an entry as text: what it is, without where it is (carry mode apart: it may be corrected)
local function key(v)
    if not istable(v) then return "?" end
    local class = isnumber(v[1]) and (I.IDClass[v[1]] or v[1]) or v[1]
    return string.format("%s r%s a%s c%s x%s", tostring(class), tostring(tonumber(v[2]) or 0), tostring(tonumber(v[3]) or 0),
        tostring(v[5] or ""), tostring(v[6] or ""))
end
local function census(d)
    local t, loc = {}, {}
    local function add(where, v)
        local k = key(v)
        t[k] = (t[k] or 0) + 1
        loc[where .. " " .. k] = (loc[where .. " " .. k] or 0) + 1
    end
    for cat, v in pairs(d.s or {}) do add("slot " .. cat, v) end
    for cont, list in pairs(d.c or {}) do for _, v in ipairs(list) do add(cont, v) end end
    return t, loc
end
local function diff(a, b)
    local out = {}
    for k, n in pairs(a) do if (b[k] or 0) ~= n then out[#out + 1] = k .. " " .. n .. "->" .. (b[k] or 0) end end
    for k, n in pairs(b) do if a[k] == nil then out[#out + 1] = k .. " 0->" .. n end end
    table.sort(out)
    return out
end
local function write(owner, d)
    sql.Query("REPLACE INTO " .. I.TABLE .. " (OwnerID, Data) VALUES (" .. SQLStr(owner) .. ", " .. SQLStr(util.TableToJSON(d)) .. ")")
end
local function roundTrip(B, owner, d, label, n)
    write(owner, d)
    I.Load(B, owner)
    local out = util.JSONToTable(I.Serialize(B))
    local a, b = census(d), census(out)
    local dd = diff(a, b)
    if #dd > 0 then
        R.fails[#R.fails + 1] = "round " .. n .. " " .. label .. ": " .. table.concat(dd, " ; ") .. " | saved: " .. util.TableToJSON(d)
    end
    return out
end

for _, b in ipairs(player.GetBots()) do b:Kick("x") end
local B
local modeBefore = GetConVar("advinv_death_drop"):GetInt()
timer.Simple(0.5, function() B = player.CreateNextBot("RoundTrip") end)
timer.Simple(2, function()
    local ok, err = pcall(function()
        for n = 1, ROUNDS do
            if not B:Alive() then B:Spawn() end
            if #packModels > 0 then B:SetModel(pick(packModels)) seen("pack model") end
            local owner = "rtfuzz_" .. n
            local d0 = randomRecord()
            local d1 = roundTrip(B, owner, d0, "first load", n)
            seen("rounds")
            -- the second round trip: exactly the same record, place included
            local d2 = roundTrip(B, owner, d1, "second load", n)
            local _, l1 = census(d1)
            local _, l2 = census(d2)
            local dl = diff(l1, l2)
            if #dl > 0 then R.fails[#R.fails + 1] = "round " .. n .. " places changed on a second load: " .. table.concat(dl, " ; ") end
            -- where the first load put things (expected when gear can't be worn: into the pockets)
            local _, l0 = census(d0)
            local dm = diff(l0, l1)
            if #dm > 0 then seen("moved by the first load") R.moved[#R.moved + 1] = n .. ": " .. table.concat(dm, " ; ") end
            -- random real actions, then the same check on what they left
            for _ = 1, math.random(3, 10) do
                B.AdvInvActCount, B.AdvInvActWindow = 0, 0
                local conts = {}
                for _, c in ipairs(I.PLAYER_CONTAINERS) do if I.HasContainer(B, c) then conts[#conts + 1] = c end end
                local from = pick(conts)
                local list = I.Get(B, from)
                local r = math.random(100)
                local function act(a, values)
                    local i = 0
                    local function nxt() i = i + 1 return values[i] end
                    local saved = { net.ReadEntity, net.ReadUInt, net.ReadBool, net.ReadString }
                    net.ReadEntity, net.ReadUInt, net.ReadBool, net.ReadString = nxt, nxt, nxt, nxt
                    I.Actor = B
                    local okA, e = pcall(I.ActHandlers[a], B)
                    I.Actor = nil
                    net.ReadEntity, net.ReadUInt, net.ReadBool, net.ReadString = saved[1], saved[2], saved[3], saved[4]
                    if not okA then R.fails[#R.fails + 1] = "round " .. n .. " action error: " .. tostring(e) end
                end
                if r <= 45 and #list > 0 then
                    local idx = math.random(#list)
                    act(I.ACT.MOVE, { B, I.ContID[from], idx, I.ItemCheck(list[idx]), B, I.ContID[pick(conts)], math.random(1, 2) })
                    seen("move")
                elseif r <= 70 and #list > 0 then
                    local idx = math.random(#list)
                    act(I.ACT.EQUIP, { B, I.ContID[from], idx, I.ItemCheck(list[idx]) })
                    seen("equip")
                else
                    local cats = { "PrimaryWep", "SecondaryWep", "Vest", "Rucksack", "Helmet", "Gasmask" }
                    act(I.ACT.UNEQUIP, { I.CategoryID[pick(cats)], false, B, I.ContID.Uniform })
                    seen("unequip")
                end
            end
            -- (anything an action put on the ground is not in the record: picked up again first)
            for _, e in ipairs(ents.FindInSphere(B:GetPos(), 200)) do
                if not e:IsPlayer() and I.ItemFromEntity(e) and not IsValid(e:GetOwner()) then
                    seen("on the ground after actions") e:Remove()
                end
            end
            local d3 = util.JSONToTable(I.Serialize(B))
            local d4 = roundTrip(B, owner, d3, "load after actions", n)
            local _, l3 = census(d3)
            local _, l4 = census(d4)
            local dl2 = diff(l3, l4)
            if #dl2 > 0 then R.fails[#R.fails + 1] = "round " .. n .. " places changed after actions: " .. table.concat(dl2, " ; ") end
            -- a death: what is saved after it + the body + what fell = what he had
            local mode = math.random(1, 3)
            GetConVar("advinv_death_drop"):SetInt(mode)
            for _, e in ipairs(ents.FindInSphere(B:GetPos(), 300)) do
                if not e:IsPlayer() and I.ItemFromEntity(e) and not IsValid(e:GetOwner()) then e:Remove() end
            end
            local pre = util.JSONToTable(I.Serialize(B))
            B.AdvInvLastBody = nil
            B:Kill()
            seen("death mode " .. mode)
            local after = util.JSONToTable(I.Serialize(B))
            local function addTo(d, cont, it) d.c[cont] = d.c[cont] or {} table.insert(d.c[cont], I.PackItems({ it })[1]) end
            local body = B.AdvInvLastBody
            if IsValid(body) then
                seen("body")
                for cat, it in pairs(body.AdvInvSlots or {}) do addTo(after, "body slot " .. cat, it) end
                for _, cont in ipairs(I.PLAYER_CONTAINERS) do
                    for _, it in ipairs(I.Get(body, cont)) do addTo(after, "body " .. cont, it) end
                end
                body:Remove()
            end
            for _, e in ipairs(ents.FindInSphere(B:GetPos(), 300)) do
                local it = not e:IsPlayer() and not IsValid(e:GetOwner()) and I.ItemFromEntity(e)
                if it then addTo(after, "ground", it) seen("fell") e:Remove() end
            end
            local dd = diff(census(pre), census(after))
            if #dd > 0 then R.fails[#R.fails + 1] = "round " .. n .. " death (mode " .. mode .. "): " .. table.concat(dd, " ; ") .. " | before: " .. util.TableToJSON(pre) end
            B:Spawn()
        end
    end)
    if not ok then R.fails[#R.fails + 1] = "ERROR " .. tostring(err) end
    GetConVar("advinv_death_drop"):SetInt(modeBefore)
    sql.Query("DELETE FROM " .. I.TABLE .. " WHERE OwnerID LIKE 'rtfuzz_%'")
    if IsValid(B) then I.Clear(B) B:Kick("done") end
    R.ok = #R.fails == 0
    R.running = false
end)
return "round-trip fuzz started, seed " .. SEED
