-- DarkRP jail: arrest (weapons and ammo stripped by DarkRP), the respawn in jail (teletojail),
-- what an arrested player may do, unarrest (weapons back).
local done = ASYNC(30)
local I = AdvInv
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
local out = {}
local function step(list, i)
    i = i or 1
    if i > #list then return done(out) end
    local ok, err = pcall(list[i][2])
    if not ok then out["error_" .. list[i][1]] = tostring(err) end
    timer.Simple(list[i][3] or 0.6, function() step(list, i + 1) end)
end
local function state(b)
    local items = {}
    for _, it in ipairs(I.Get(b, "Uniform")) do items[#items + 1] = (I.IDClass[it.id] or "?") .. (it.c and ("[" .. it.c .. "]") or "") .. "(" .. (it.r or 0) .. ")" end
    local w = b:GetWeapon("weapon_ar2")
    return {
        arrested = b:isArrested() or false, alive = b:Alive(),
        helmet = I.IDClass[b:GetNW2Int("Helmet")] or "none", helmetArmor = b:GetNWInt("HelmetArmor"),
        primarySlot = I.IDClass[b:GetNWInt("PrimaryWep")] or "none", slotRounds = b:GetNWInt("PrimaryWepRounds"),
        ar2InHands = IsValid(w), ar2Clip = IsValid(w) and w:Clip1() or "-", reserve = b:GetAmmoCount("AR2"),
        pockets = table.concat(items, " "), weapons = #b:GetWeapons(),
    }
end
player.CreateNextBot("Prisoner")
player.CreateNextBot("Cop")
timer.Simple(1.5, function()
    local b, cop = player.GetBots()[1], player.GetBots()[2]
    local BASE = Vector(-2800, -300, -140)
    b:SetPos(BASE) cop:SetPos(BASE + Vector(0, 60, 0))
    cop:changeTeam(TEAM_POLICE, true, true)
    I.SetDefaults(b)
    I.Equip(b, { id = I.ClassID.advinv_barney_helmet, a = 90 })
    I.Equip(b, { id = I.ClassID.advinv_hl2_ar2, r = 17 })
    I.Store(b, { id = I.ClassID.advinv_ammo_ar2, r = 30 })
    I.Store(b, { id = I.GENERIC_ENTITY, c = "item_healthkit" })
    local kit
    step({
        { "before", function() out.before = state(b) end },
        { "arrest", function() b:arrest(60, cop) end },
        { "arrested", function()
            out.arrested = state(b)
            kit = ents.Create("item_healthvial") kit:SetPos(BASE + Vector(40, 0, 10)) kit:Spawn()
        end, 0.3 },
        { "rules", function()
            out.pickupInJail = { I.CanPickup(b, kit) }
            -- an inventory action (the dispatcher refuses it): use the health kit
            local before = #I.Get(b, "Uniform")
            local H = I.ActHandlers
            local real = { net.ReadUInt, net.ReadEntity }
            local q, k = { I.ACT.USE, b, I.ContID.Uniform, 2, I.ItemCheck(I.Get(b, "Uniform")[2] or {}) }, 0
            local function nxt() k = k + 1 return q[k] end
            net.ReadUInt, net.ReadEntity = nxt, nxt
            pcall(net.Receivers["advinv_act"], 0, b)
            net.ReadUInt, net.ReadEntity = real[1], real[2]
            out.useInJail = #I.Get(b, "Uniform") == before and "refused" or "used"
            out.searchByCop = { I.CanSearch(cop, b) }
            -- teletojail: DarkRP respawns him in jail
            b:Spawn()
            b:SetPos(BASE)
        end, 0.8 },
        { "respawnedInJail", function() out.respawnedInJail = state(b) end },
        { "unarrest", function() b:unArrest(cop) end, 0.8 },
        { "free", function()
            out.free = state(b)
            if IsValid(kit) then kit:Remove() end
        end },
    })
end)
