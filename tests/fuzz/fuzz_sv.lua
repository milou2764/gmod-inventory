-- Inventory fuzzer, server half: setup, census (everything that exists, by kind) and pickups.
-- BUGFZ_STEP = "setup" | "census" | "pickup" | "compare"
local I = AdvInv
local p = Entity(1)
BUGFZ = BUGFZ or {}

local function census()
    local t = {}
    local function add(k, n) if n ~= 0 then t[k] = (t[k] or 0) + n end end
    local CONSUMABLE = { item_healthkit = true, item_healthvial = true, item_battery = true }
    local function addItem(it, mult, onPlayer)
        mult = mult or 1
        if not (it and it.id and it.id > 1) then return end
        if it.j then
            -- (a job's item: removed at death by design; off its player it is an escape)
            if not onPlayer then add("JOB-ESCAPED " .. tostring(AdvInv.IDClass[it.id] or it.id), mult) end
            return
        end
        if it.id == I.GENERIC_ENTITY and CONSUMABLE[it.c] then return end -- (used up by USE: legit)
        local info = I.Info(it.id, it.c)
        local key = tostring(AdvInv.IDClass[it.id] or it.id) .. (it.c and ("/" .. it.c) or "")
        local ammo
        if info.isBox then ammo = info.ammo
        else
            add("item " .. key, mult)
            if info.isWeapon then ammo = I.WeaponAmmo(it.id, it.c) end
        end
        if ammo and (it.r or 0) > 0 then add("rounds " .. string.lower(ammo), it.r * mult) end
    end
    local holders = {}
    for _, e in ipairs(ents.GetAll()) do
        if e:IsPlayer() or I.IsBody(e) or I.IsStorage(e) then holders[#holders + 1] = e end
    end
    local seenStore = {}
    for _, h in ipairs(holders) do
        if I.IsKeyed and I.IsKeyed(h) then
            -- a personal store: each player's own, counted once (all banks open the same one)
            for _, pl in ipairs(player.GetAll()) do
                local key = I.StoreKey(h, pl)
                if key and not seenStore[key] then
                    seenStore[key] = true
                    for _, it in ipairs(I.Get(h, "Storage", pl)) do addItem(it) end
                end
            end
        else
            for _, cont in ipairs(I.ContainersOf(h)) do
                for _, it in ipairs(I.Get(h, cont)) do addItem(it, 1, h:IsPlayer()) end
            end
        end
        if h:IsPlayer() then
            for cat in pairs(AdvInv.GearCat) do
                local id = h:GetNW2Int(cat)
                if id > 1 then addItem({ id = id }) end
            end
            for _, cat in ipairs(AdvInv.WeaponCat) do
                local id, c = I.SlotRef(h, cat)
                if id > 1 then
                    local info = I.Info(id, c)
                    local wep = info.weaponClass and h:GetWeapon(info.weaponClass)
                    local r = IsValid(wep) and math.max(wep:Clip1(), 0) or h:GetNWInt(cat .. "Rounds")
                    addItem({ id = id, c = c, r = r, j = h.AdvInvJobSlot and h.AdvInvJobSlot[cat] or nil }, 1, true)
                end
            end
        else
            for _, it in pairs(h.AdvInvSlots or {}) do addItem(it) end
        end
    end
    for _, e in ipairs(ents.GetAll()) do
        if not (e:IsPlayer() or I.IsBody(e) or I.IsStorage(e)) and not IsValid(e:GetOwner()) then
            local it = I.ItemFromEntity(e)
            if it then
                addItem(it, I.GroundCount(e))
                for _, c in ipairs(e.AdvInvContents or {}) do addItem(c) end
            end
        end
    end
    return t
end
BUGFZ.census = census

local function diff(a, b)
    local out = {}
    for k, v in pairs(a) do if (b[k] or 0) ~= v then out[#out + 1] = k .. " " .. v .. "->" .. (b[k] or 0) end end
    for k, v in pairs(b) do if a[k] == nil then out[#out + 1] = k .. " 0->" .. v end end
    table.sort(out)
    return out
end
BUGFZ.diff = diff

local step = BUGFZ_STEP
if step == "setup" then
    if not p:Alive() then p:Spawn() end
    for _, e in ipairs(ents.GetAll()) do
        if (I.IsBody(e) or I.IsStorage(e) or (I.ItemFromEntity(e) and not IsValid(e:GetOwner()))) and not e:IsPlayer() then e:Remove() end
    end
    p:SetPos(Vector(-750, -1575, -144))
    p:SetEyeAngles(Angle(20, 0, 0))
    p:StripWeapons()
    p:Give("keys")
    I.SetDefaults(p)
    local C = I.ClassID
    local function gear(class, contents)
        local t = scripted_ents.Get(class)
        return I.Equip(p, { id = C[class], a = t and t.Armor or 0 }, contents or {})
    end
    local function box(ammo, r) local id, c = I.AmmoBoxFor(ammo) return { id = id, c = c, r = r } end
    -- default content only: HL2 weapons and the addon's own gear
    local vest, pack
    for class, id in pairs(C) do
        local t = scripted_ents.Get(class)
        if t and t.AdvInvAvailable ~= false and not t.AdvInvCompat and not t.AdvInvModelGearPack then
            if t.AdvInvCategory == "Vest" and (t.MaxLoad or 0) >= 40 and not vest then vest = class end
            if t.AdvInvCategory == "Rucksack" and (t.MaxLoad or 0) >= 60 and not pack then pack = class end
        end
    end
    local out = { tostring(vest), tostring(pack) }
    out[#out + 1] = tostring(vest and gear(vest, { box("SMG1", 45), box("Pistol", 18) }))
    out[#out + 1] = tostring(pack and gear(pack, { box("SMG1", 20), box("Buckshot", 12), { id = I.GENERIC_ENTITY, c = "item_healthkit" } }))
    local extra
    if BUGFZ_BASES then
        -- weapons of every supported base, with boxes of their ammunition
        local function w(class, r, x) local it = I.ItemForWeaponClass(class, r) if it then it.x = x end return it end
        out[#out + 1] = tostring(I.Equip(p, w("arccw_m4a1", 30)))
        out[#out + 1] = tostring(I.Equip(p, w("weapon_sand_deagle", 7)))
        extra = { w("cw_ak74", 20, util.TableToJSON({ "md_kobra" })), w("tfa_ins2_wpn_coltm16a1", 15), w("weapon_sand_ak74", 25) }
        for _, class in ipairs({ "arccw_m4a1", "weapon_sand_deagle", "cw_ak74", "tfa_ins2_wpn_coltm16a1", "weapon_sand_ak74" }) do
            local a = I.WeaponAmmo(I.ItemForWeaponClass(class, 0).id, class)
            if a then extra[#extra + 1] = box(a, 30) end
        end
    else
        out[#out + 1] = tostring(I.Equip(p, I.ItemForWeaponClass("weapon_smg1", 30)))
        out[#out + 1] = tostring(I.Equip(p, I.ItemForWeaponClass("weapon_pistol", 10)))
        extra = { box("357", 6), { id = I.GENERIC_ENTITY, c = "item_battery" },
            I.ItemForWeaponClass("weapon_shotgun", 4), I.ItemForWeaponClass("weapon_frag", 1), I.ItemForWeaponClass("weapon_frag", 1) }
    end
    if BUGFZ_JOB then
        -- job items (as advinv_darkrp_loadout_to_inventory gives them): a weapon in its slot, a
        -- revolver and two grenades in the pockets; with dropspawnedweapons off they never leave him
        -- (the equipped SMG is the job's weapon: its slot is a job slot, as an Equip of a job item makes it)
        p.AdvInvJobSlot = p.AdvInvJobSlot or {}
        p.AdvInvJobSlot.PrimaryWep = I.SlotID(p, "PrimaryWep") > 1 or nil
        out[#out + 1] = "jobslot " .. tostring(p.AdvInvJobSlot.PrimaryWep)
        local j357 = I.ItemForWeaponClass("weapon_357", 6)
        if j357 then j357.j = true extra[#extra + 1] = j357 end
        local gid, gc = I.AmmoBoxFor("Grenade")
        extra[#extra + 1] = { id = gid, c = gc, r = 1, j = true }
        extra[#extra + 1] = { id = gid, c = gc, r = 1, j = true }
        extra[#extra + 1] = { id = gid, c = gc, r = 1 } -- (and a looted one: stacks with them)
    end
    for _, it in ipairs(extra) do
        if it then table.insert(I.Get(p, "Uniform"), it) end
    end
    I.MarkDirty(p, "Uniform")
    local crate = ents.Create("advinv_crate")
    crate:SetPos(p:GetPos() + Vector(45, 0, 20))
    crate:Spawn()
    table.insert(I.Get(crate, "Storage"), box("AR2", 30))
    table.insert(I.Get(crate, "Storage"), I.ItemForWeaponClass("weapon_crossbow", 1))
    I.MarkDirty(crate, "Storage")
    if BUGFZ_BANK then
        local bank = ents.Create("advinv_bank")
        bank:SetPos(p:GetPos() + Vector(40, 60, 0))
        bank:SetAngles(Angle(0, -90, 0))
        bank:Spawn()
        local S = I.Get(bank, "Storage", p)
        for k = #S, 1, -1 do S[k] = nil end -- (a clean store for the test player)
        table.insert(S, box("Pistol", 12))
        table.insert(S, { id = I.GENERIC_ENTITY, c = "item_healthvial" })
        I.MarkDirty(bank, "Storage")
    end
    timer.Simple(0.5, function() BUGFZ.base = census() end)
    return "setup " .. table.concat(out, " ")
elseif step == "pickup" then
    -- what lies around (dropped by the fuzzer) is taken back with Use, as a player would
    local n = 0
    for _, e in ipairs(ents.FindInSphere(p:GetPos(), 400)) do
        if n >= (BUGFZ_PICK or 2) then break end
        if not e:IsPlayer() and not I.IsStorage(e) and not I.IsBody(e) and not IsValid(e:GetOwner()) and I.ItemFromEntity(e) and math.random() < 0.6 then
            if hook.Run("PlayerUse", p, e) ~= false and e.Use then e:Use(p, p, USE_ON, 0) end
            n = n + 1
        end
    end
    return "picked " .. n
elseif step == "compare" then
    local now = census()
    local d = BUGFZ.base and diff(BUGFZ.base, now) or { "no base" }
    return #d == 0 and "OK" or table.concat(d, " ; ")
elseif step == "die" then
    -- everything he has must be found again on his body or on the ground
    BUGFZ.beforeDeath = census()
    local w = p:GetActiveWeapon()
    p:Kill()
    return "killed (held " .. (IsValid(w) and w:GetClass() or "nothing") .. ")"
elseif step == "die_check" then
    local d = BUGFZ.beforeDeath and diff(BUGFZ.beforeDeath, census()) or { "no census" }
    return #d == 0 and "OK" or table.concat(d, " ; ")
elseif step == "respawn" then
    p:Spawn()
    timer.Simple(0.5, function()
        p:SetPos(Vector(-750, -1575, -144)) p:SetEyeAngles(Angle(20, 0, 0))
        timer.Simple(0.5, function() BUGFZ.base = census() end)
    end)
    return "respawned"
elseif step == "rebase" then
    BUGFZ.base = census()
    return "rebased"
end
return "?"
