local done = ASYNC(20)
GetConVar("advinv_craft"):SetBool(true) -- crafting is off by default
local I = AdvInv
local idOf = {}
for id, c in pairs(AdvInv.IDClass) do idOf[c] = id end
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
for _, e in ipairs(ents.FindByClass("advinv_workbench")) do e:Remove() end
local out = {}
local function summary(items)
    local t = {}
    for _, it in ipairs(items) do t[#t + 1] = (AdvInv.IDClass[it.id] or "?") .. (it.c and ("[" .. it.c .. "]") or "") end
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
local function hit(p, group, dmg, blocked) -- blocked: another addon refuses the damage
    local d = DamageInfo()
    d:SetDamage(dmg)
    d:SetDamageType(DMG_BULLET)
    hook.Run("ScalePlayerDamage", p, group, d)
    hook.Run("PostEntityTakeDamage", p, d, not blocked)
    return d:GetDamage()
end
player.CreateNextBot("Smith")
timer.Simple(1, function()
    local p = player.GetBots()[1]
    I.SetDefaults(p)
    p:SetPos(Vector(-2800, -1800, -140))
    -- armour: helmet protects the head, not the stomach
    I.Equip(p, { id = idOf.advinv_barney_helmet, a = 100 })
    out.armor = { head = hit(p, HITGROUP_HEAD, 20), helmetLeft = p:GetNWInt("HelmetArmor"), stomach = hit(p, HITGROUP_STOMACH, 20) }
    hit(p, HITGROUP_HEAD, 20, true)
    out.armorAfterBlockedHit = p:GetNWInt("HelmetArmor") -- unchanged (80)
    local item = I.TakeOff(p, "Helmet")
    out.armorKept = item and item.a
    -- crafting
    I.Set(p, "Uniform", { { id = I.GENERIC_ENTITY, c = "item_healthvial" }, { id = I.GENERIC_ENTITY, c = "item_healthvial" } })
    local kit
    for k, r in ipairs(I.Recipes) do if r.id == "healthkit" then kit = k end end
    out.craft = call(I.ActHandlers[I.ACT.CRAFT], p, { kit })
    local r357
    for k, r in ipairs(I.Recipes) do if r.id == "357" then r357 = k end end
    timer.Simple(1.3, function()
        out.afterCraft = summary(I.Get(p, "Uniform"))
        for _ = 1, 3 do I.Store(p, { id = idOf.advinv_ammo_pistol, r = 20 }) end
        out.noBench = call(I.ActHandlers[I.ACT.CRAFT], p, { r357 })
        local bench = ents.Create("advinv_workbench") bench:SetPos(p:GetPos() + Vector(60, 0, 0)) bench:Spawn()
        out.withBench = call(I.ActHandlers[I.ACT.CRAFT], p, { r357 })
        timer.Simple(3.4, function()
            out.afterBench = summary(I.Get(p, "Uniform"))
            out.chat = hook.Run("PlayerSay", p, "!inv")
            bench:Remove()
            done(out)
        end)
    end)
end)
