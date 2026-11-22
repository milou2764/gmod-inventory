-- CW 2.0 weapons with the Advanced Inventory System (bots).
local done = ASYNC(60)
local I = AdvInv
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
for _, e in ipairs(ents.FindByClass("cw_*")) do if not IsValid(e:GetOwner()) then e:Remove() end end
local out = { errors = {} }
local function summary(items)
    local t = {}
    for _, it in ipairs(items or {}) do t[#t + 1] = (it.c or I.IDClass[it.id] or "?") .. "(" .. (it.r or 0) .. ")" .. (it.x and ("{" .. it.x .. "}") or "") end
    table.sort(t)
    return table.concat(t, " ")
end
local function spawnAt(class, pos)
    local e = ents.Create(class)
    e:SetPos(pos) e:Spawn() e:Activate()
    return e
end
local function activeAtts(w)
    local t = {}
    if IsValid(w) and w.ActiveAttachments then for k, v in pairs(w.ActiveAttachments) do if v then t[#t + 1] = k end end end
    table.sort(t)
    return table.concat(t, ",")
end
local function step(list, i)
    i = i or 1
    if i > #list then return done(out) end
    local ok, err = pcall(list[i][2])
    if not ok then out.errors[#out.errors + 1] = list[i][1] .. ": " .. tostring(err) end
    timer.Simple(list[i][3] or 0.6, function() step(list, i + 1) end)
end

out.cw2 = CustomizableWeaponry ~= nil
-- what the inventory makes of each CW 2.0 weapon
out.defs = {}
for _, class in ipairs({ "cw_ar15", "cw_ak74", "cw_akm_official", "cw_famasg2_official", "cw_g3a3", "cw_l115", "cw_mp5", "cw_svd_official",
        "cw_deagle", "cw_mr96", "cw_frag_grenade", "cw_flash_grenade", "cw_smoke_grenade" }) do
    local d = I.DefTable(I.GENERIC_WEAPON, class)
    local conf = I.CarryConfig(I.GENERIC_WEAPON, class)
    out.defs[class] = d and (d.AdvInvCategory .. " mass " .. d.Mass .. " clip " .. tostring(d.ClipSize) .. " ammo " .. tostring(d.Ammo)
        .. " carry " .. (conf and conf.default or "-")) or "none"
end

player.CreateNextBot("CW")
player.CreateNextBot("Looter")
local b, l, ar, kitAmmoBefore
timer.Simple(1.5, function()
    b, l = player.GetBots()[1], player.GetBots()[2]
    b:SetPos(Vector(-2800, -1300, -140)) l:SetPos(Vector(-2700, -1300, -140))
    I.SetDefaults(b) I.SetDefaults(l)
    step({
        { "pickup", function()
            ar = spawnAt("cw_ar15", b:GetPos() + Vector(40, 0, 30))
            timer.Simple(0.3, function()
                if IsValid(ar) then ar:SetClip1(17) end
                out.pickupItem = I.ItemFromEntity(ar)
                I.Use(b, ar)
            end)
        end, 1 },
        { "equipped", function()
            local w = b:GetWeapon("cw_ar15")
            out.equipped = { slot = b:GetNWString("PrimaryWepClass"), has = IsValid(w), clip = IsValid(w) and w:Clip1(), carry = I.CarryMode(b, "PrimaryWep") }
        end },
        { "attach", function()
            local w = b:GetWeapon("cw_ar15")
            -- the first attachment of each of the first two categories, owned by the player
            local names = {}
            for cat, data in pairs(w.Attachments) do
                if #names < 2 and data.atts and data.atts[1] then names[#names + 1] = data.atts[1] end
            end
            CustomizableWeaponry.giveAttachments(b, names, true)
            for _, n in ipairs(names) do w:attachSpecificAttachment(n) end
            out.attachTried = table.concat(names, ",")
        end },
        { "attached", function()
            out.attachedOnGun = activeAtts(b:GetWeapon("cw_ar15"))
            out.extra = I.WeaponExtra(b:GetWeapon("cw_ar15"))
        end },
        { "takeoff", function()
            local item = I.TakeOff(b, "PrimaryWep")
            out.takenOff = summary({ item })
            b.cwItem = item
        end },
        { "reequip", function()
            out.reequip = { I.Equip(b, b.cwItem) }
        end, 1.2 },
        { "reattached", function()
            local w = b:GetWeapon("cw_ar15")
            out.reattached = { atts = activeAtts(w), clip = IsValid(w) and w:Clip1() }
        end },
        { "cw_dropweapon", function()
            b:SelectWeapon("cw_ar15")
            local w = b:GetWeapon("cw_ar15")
            w.disableDropping = false
            CustomizableWeaponry:dropWeapon(b, w)
        end, 1 },
        { "afterDrop", function()
            local dropped = {}
            for _, e in ipairs(ents.FindInSphere(b:GetPos(), 200)) do
                if e:GetClass() == "cw_dropped_weapon" or (e:IsWeapon() and not IsValid(e:GetOwner())) then
                    dropped[#dropped + 1] = e:GetClass() .. (e.AdvInvExtra and "[x]" or "") .. (e.GetWepClass and ("<" .. e:GetWepClass() .. ">") or "")
                end
            end
            out.afterDrop = { slot = b:GetNWString("PrimaryWepClass"), has = IsValid(b:GetWeapon("cw_ar15")), world = table.concat(dropped, " ") }
        end },
        { "looterPicks", function()
            for _, e in ipairs(ents.FindInSphere(b:GetPos(), 200)) do
                if (e:GetClass() == "cw_dropped_weapon" or (e:IsWeapon() and e:GetClass() == "cw_ar15" and not IsValid(e:GetOwner()))) then
                    l:SetPos(e:GetPos() + Vector(0, -40, 0))
                    l:SetEyeAngles((e:GetPos() - l:GetShootPos()):Angle())
                    if hook.Run("PlayerUse", l, e) ~= false then e:Use(l, l) end
                    break
                end
            end
        end, 1.2 },
        { "looterHas", function()
            local w = l:GetWeapon("cw_ar15")
            out.looter = { slot = l:GetNWString("PrimaryWepClass"), has = IsValid(w), atts = activeAtts(w), clip = IsValid(w) and w:Clip1(),
                uniform = summary(I.Get(l, "Uniform")), owns = l.CWAttachments and (l.CWAttachments.md_saker and "md_saker " or "") .. (l.CWAttachments.bg_foldsight and "bg_foldsight" or "") }
        end },
        { "cwOwnDrop", function()
            -- a CW 2.0 weapon outside the inventory (given by code), with an attachment, dropped CW 2.0's way
            local w = b:Give("cw_mp5")
            timer.Simple(0.3, function()
                local name
                for _, data in pairs(w.Attachments) do if not name and data.atts and data.atts[1] then name = data.atts[1] end end
                CustomizableWeaponry.giveAttachments(b, { name }, true)
                w:attachSpecificAttachment(name)
                w:SetClip1(9)
                out.mp5Att = name
                b:SelectWeapon("cw_mp5")
                timer.Simple(0.3, function()
                    w.disableDropping = false
                    CustomizableWeaponry:dropWeapon(b, w)
                end)
            end)
        end, 1.5 },
        { "cwOwnPickup", function()
            local d = ents.FindByClass("cw_dropped_weapon")[1]
            out.cwDropped = IsValid(d) and d:GetWepClass() or "none"
            if IsValid(d) then
                b:SetPos(d:GetPos() + Vector(0, -40, 0))
                b:SetEyeAngles((d:GetPos() - b:GetShootPos()):Angle())
                b.AdvInvUseDelay = 0
                if hook.Run("PlayerUse", b, d) ~= false then d:Use(b, b) end
            end
        end, 1.2 },
        { "cwOwnPicked", function()
            local w = b:GetWeapon("cw_mp5")
            out.cwOwnPicked = { slot = b:GetNWString("PrimaryWepClass"), has = IsValid(w), atts = activeAtts(w), clip = IsValid(w) and w:Clip1(),
                leftInWorld = #ents.FindByClass("cw_dropped_weapon") }
        end },
        { "ammoKit", function()
            -- the bot holds a CW 2.0 rifle and uses an ammo kit
            I.SetDefaults(b)
            I.Equip(b, { id = I.GENERIC_WEAPON, c = "cw_ak74", r = 30 })
            b:SelectWeapon("cw_ak74")
            I.Set(b, "Uniform", {})
            I.SyncAmmo(b)
            local kit = spawnAt("cw_ammo_kit_regular", b:GetPos() + Vector(30, 0, 10))
            timer.Simple(0.3, function()
                local w = b:GetActiveWeapon()
                kitAmmoBefore = b:GetAmmoCount(w.Primary.Ammo)
                out.kitActive = w:GetClass() .. " " .. tostring(w.Primary.Ammo)
                if hook.Run("PlayerUse", b, kit) ~= false then kit:Use(b, b) end
                out.kitRightAfter = b:GetAmmoCount(w.Primary.Ammo)
            end)
        end, 1.5 },
        { "ammoAfterSync", function()
            I.SyncAmmo(b)
            local w = b:GetActiveWeapon()
            out.ammoKit = { before = kitAmmoBefore, reserve = b:GetAmmoCount(w.Primary.Ammo), boxes = summary(I.Get(b, "Uniform")) }
            local box = spawnAt("cw_ammo_545x39", b:GetPos() + Vector(-30, 0, 10))
            timer.Simple(0.3, function()
                b.AmmoGiveDelay = 0
                if hook.Run("PlayerUse", b, box) ~= false then box:Use(b, b) end
            end)
        end, 1.2 },
        { "ammoCaliber", function()
            I.SyncAmmo(b)
            out.ammoCaliber = { reserve = b:GetAmmoCount("5.45x39MM"), boxes = summary(I.Get(b, "Uniform")) }
        end },
        { "grenade", function()
            local g = spawnAt("cw_frag_grenade", b:GetPos() + Vector(40, 40, 30))
            timer.Simple(0.3, function() out.grenadeItem = I.ItemFromEntity(g) end)
        end },
        { "death", function()
            -- a deagle with an attachment in the sidearm slot, the AK74 in hand
            I.Equip(b, { id = I.GENERIC_WEAPON, c = "cw_deagle", r = 5 })
            local d = b:GetWeapon("cw_deagle")
            local name
            for _, data in pairs(d.Attachments) do if not name and data.atts and data.atts[1] then name = data.atts[1] end end
            CustomizableWeaponry.giveAttachments(b, { name }, true)
            d:attachSpecificAttachment(name)
            out.deagleAtt = name .. " -> " .. activeAtts(d)
            b:SelectWeapon("cw_ak74")
            timer.Simple(0.3, function() b:Kill() end)
        end, 1.3 },
        { "body", function()
            local body
            for _, e in ipairs(ents.FindByClass("prop_ragdoll")) do if I.IsBody(e) and e:GetNWString("AdvInvBodyName") == b:Nick() then body = e end end
            local sec = IsValid(body) and body.AdvInvSlots and body.AdvInvSlots.SecondaryWep
            out.body = IsValid(body) and { primary = body:GetNWString("PrimaryWepClass"), secondary = body:GetNWString("SecondaryWepClass"),
                secondaryItem = sec and summary({ sec }) or "none", uniform = summary(I.Get(body, "Uniform")) } or "no body"
            local held = {}
            for _, e in ipairs(ents.FindInSphere(b:GetPos(), 150)) do if e:IsWeapon() and not IsValid(e:GetOwner()) then held[#held + 1] = e:GetClass() end end
            out.droppedAtDeath = table.concat(held, " ")
            out.body_ent = body
        end },
        { "lootDeagle", function()
            local body = out.body_ent
            out.body_ent = nil
            if not IsValid(body) then return end
            l:SetPos(body:GetPos() + Vector(0, -40, 10))
            I.Actor = l
            out.lootDeagle = { I.ActHandlers[I.ACT.LOOT] and (function()
                local saved = { net.ReadEntity, net.ReadUInt }
                net.ReadEntity = function() return body end
                net.ReadUInt = function() return I.CategoryID.SecondaryWep end
                local ok, r = pcall(I.ActHandlers[I.ACT.LOOT], l)
                net.ReadEntity, net.ReadUInt = saved[1], saved[2]
                return ok and tostring(r) or ("error " .. tostring(r))
            end)() }
            I.Actor = nil
        end, 1 },
        { "looterDeagle", function()
            local w = l:GetWeapon("cw_deagle")
            out.looterDeagle = { slot = l:GetNWString("SecondaryWepClass"), has = IsValid(w), atts = activeAtts(w), clip = IsValid(w) and w:Clip1() }
        end },
    })
end)
