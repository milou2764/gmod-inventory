local done = ASYNC(20)
local I = AdvInv
local idOf = {}
for id, c in pairs(AdvInv.IDClass) do idOf[c] = id end
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
for b in pairs(I.Bodies or {}) do if IsValid(b) then b:Remove() end end
local out = {}
local function summary(items)
    local t = {}
    for _, it in ipairs(items) do t[#t + 1] = (AdvInv.IDClass[it.id] or "?") .. "(" .. (it.r or 0) .. ")" end
    table.sort(t)
    return table.concat(t, " ")
end
local function call(fn, ply, q)
    local real = { net.ReadUInt, net.ReadEntity, net.ReadString, net.ReadBool }
    local k = 0
    local function nxt() k = k + 1 return q[k] end
    net.ReadUInt, net.ReadEntity, net.ReadString, net.ReadBool = nxt, nxt, nxt, nxt
    I.Actor = ply
    local ok, a, b = pcall(fn, ply)
    I.Actor = nil
    net.ReadUInt, net.ReadEntity, net.ReadString, net.ReadBool = real[1], real[2], real[3], real[4]
    if not ok then return "ERROR " .. tostring(a) end
    return { a, b }
end
player.CreateNextBot("Victim") player.CreateNextBot("Looter")
timer.Simple(1, function()
    local v, l = player.GetBots()[1], player.GetBots()[2]
    for _, p in ipairs({ v, l }) do I.SetDefaults(p) end
    v:SetPos(Vector(-2800, -1800, -140)) l:SetPos(Vector(-2740, -1800, -140))
    RunConsoleCommand("advinv_death_drop", "3")
    I.Equip(v, { id = idOf.advinv_hl2_ar2, r = 25 })
    I.Equip(v, { id = idOf.advinv_hl2_pistol, r = 12 })
    I.Equip(v, { id = idOf.advinv_barney_helmet, a = 90 })
    I.Equip(v, { id = idOf.advinv_suitcase }, { { id = idOf.advinv_ammo_ar2, r = 30 } })
    I.Store(v, { id = idOf.advinv_ammo_pistol, r = 18 })
    v:SelectWeapon("weapon_ar2")
    timer.Simple(0.3, function()
        out.held = IsValid(v:GetActiveWeapon()) and v:GetActiveWeapon():GetClass()
        for _, e in ipairs(ents.FindByClass("advinv_hl2_ar2")) do e:Remove() end
        v:Kill()
        timer.Simple(0.3, function()
            local body
            for b in pairs(I.Bodies) do body = b end
            out.body = IsValid(body) and body:GetClass() or "none"
            out.defaultRagdoll = IsValid(v:GetRagdollEntity())
            if not IsValid(body) then done(out) return end
            out.onBody = {
                name = body:GetNWString("AdvInvBodyName"), helmet = body:GetNW2Int("Helmet") == idOf.advinv_barney_helmet,
                helmetArmor = body:GetNWInt("HelmetArmor"), sack = body:GetNW2Int("Rucksack") == idOf.advinv_suitcase,
                primary = body:GetNWInt("PrimaryWep"), secondary = body:GetNWInt("SecondaryWep") == idOf.advinv_hl2_pistol,
                pockets = summary(I.Get(body, "Uniform")), sackItems = summary(I.Get(body, "Rucksack")),
                physics = body:GetPhysicsObjectCount(),
            }
            out.droppedAR2 = #ents.FindByClass("advinv_hl2_ar2")
            out.victimEmpty = { helmet = v:GetNW2Int("Helmet"), primary = v:GetNWInt("PrimaryWep"), pockets = #I.Get(v, "Uniform") }
            -- looting
            l:SetPos(body:GetPos() + Vector(30, 0, 0))
            out.access = I.CanAccess(l, body)
            out.takeHelmet = call(I.ActHandlers[I.ACT.LOOT], l, { body, AdvInv.CategoryID.Helmet })
            out.afterHelmet = { looter = l:GetNW2Int("Helmet") == idOf.advinv_barney_helmet, looterArmor = l:GetNWInt("HelmetArmor"), body = body:GetNW2Int("Helmet") }
            out.takeSack = call(I.ActHandlers[I.ACT.LOOT], l, { body, AdvInv.CategoryID.Rucksack })
            out.afterSack = { looterSack = summary(I.Get(l, "Rucksack")), body = body:GetNW2Int("Rucksack"), bodySack = #I.Get(body, "Rucksack") }
            out.takePistol = call(I.ActHandlers[I.ACT.LOOT], l, { body, AdvInv.CategoryID.SecondaryWep })
            out.afterPistol = { looter = l:GetNWInt("SecondaryWep") == idOf.advinv_hl2_pistol, body = body:GetNWInt("SecondaryWep") }
            out.movePockets = call(I.ActHandlers[I.ACT.MOVE], l, { body, I.ContID.Uniform, 1, l, I.ContID.Uniform, 1 })
            out.afterMove = { looter = summary(I.Get(l, "Uniform")), body = #I.Get(body, "Uniform") }
            out.uniformWithPockets = "n/a"
            l:SetPos(body:GetPos() + Vector(600, 0, 0))
            out.farAccess = I.CanAccess(l, body)
            done(out)
        end)
    end)
end)
