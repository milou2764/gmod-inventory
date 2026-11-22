local done = ASYNC(20)
local I = AdvInv
local idOf = {}
for id, c in pairs(AdvInv.IDClass) do idOf[c] = id end
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
local out = {}
local function summary(items)
    local t = {}
    for _, it in ipairs(items) do t[#t + 1] = (AdvInv.IDClass[it.id] or "?") .. (it.c and ("[" .. it.c .. "]") or "") .. "(" .. (it.r or 0) .. ")" end
    table.sort(t)
    return table.concat(t, " ")
end
player.CreateNextBot("Buyer")
timer.Simple(1, function()
    local p = player.GetBots()[1]
    I.SetDefaults(p)
    p:SetPos(Vector(-2800, -1800, -140))
    local pos = p:GetPos() + Vector(40, 0, 20)
    -- DarkRP weapon lying around, 3 of them
    local sw = ents.Create("spawned_weapon")
    sw:SetWeaponClass("weapon_ar2") sw:SetModel("models/weapons/w_irifle.mdl") sw:SetPos(pos) sw:Spawn()
    sw:Setamount(3)
    out.swItem = summary({ I.ItemFromEntity(sw) })
    p.AdvInvUseDelay = 0
    I.Use(p, sw)
    out.afterUse = { primary = p:GetNWInt("PrimaryWep") == idOf.advinv_hl2_ar2, left = IsValid(sw) and sw:Getamount() or 0 }
    -- DarkRP ammo
    local sa = ents.Create("spawned_ammo")
    sa:SetModel("models/items/boxmrounds.mdl") sa:SetPos(pos + Vector(0, 30, 0)) sa:Spawn()
    sa.ammoType, sa.amountGiven = "smg1", 45
    out.ammoItem = summary({ I.ItemFromEntity(sa) })
    -- /drop on the inventory AR2: allowed, slot freed
    local wep = p:GetWeapon("weapon_ar2")
    out.canDrop = hook.Run("canDropWeapon", p, wep)
    out.afterDrop = { primary = p:GetNWInt("PrimaryWep") }
    -- a bought entity goes into the inventory
    local box = ents.Create("advinv_ammo_pistol") box:SetPos(pos + Vector(0, -30, 0)) box:Spawn()
    hook.Run("playerBoughtCustomEntity", p, {}, box, 0)
    -- money
    p:setDarkRPVar("money", 500)
    local real = net.ReadUInt
    net.ReadUInt = function() return 120 end
    pcall(net.Receivers["advinv_drop_money"], 0, p)
    net.ReadUInt = real
    -- job weapons
    RunConsoleCommand("advinv_darkrp_loadout_to_inventory", "1")
    timer.Simple(0.2, function()
        p:Give("weapon_shotgun")
        hook.Run("PlayerLoadout", p)
        timer.Simple(0.5, function()
            out.bought = { uniform = summary(I.Get(p, "Uniform")), boxGone = not IsValid(box) }
            out.money = { wallet = p:getDarkRPVar("money"), bags = #ents.FindByClass("spawned_money") }
            out.loadout = { primary = AdvInv.IDClass[p:GetNWInt("PrimaryWep")] }
            -- dying with an inventory weapon: DarkRP must not drop a copy
            p:Kill()
            out.deathDrop = hook.Run("canDropWeapon", p, p:GetWeapon("weapon_shotgun"))
            RunConsoleCommand("advinv_darkrp_loadout_to_inventory", "0")
            for _, e in ipairs(ents.FindByClass("spawned_money")) do e:Remove() end
            if IsValid(sw) then sw:Remove() end
            if IsValid(sa) then sa:Remove() end
            done(out)
        end)
    end)
end)
