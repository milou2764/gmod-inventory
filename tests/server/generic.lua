local done = ASYNC(30)
local I = AdvInv
local idOf = {}
for id, c in pairs(AdvInv.IDClass) do idOf[c] = id end
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
for _, e in ipairs(ents.FindByClass("advinv_loot_bag")) do e:Remove() end
local out = {}
local function summary(items)
    local t = {}
    for _, it in ipairs(items) do t[#t + 1] = (AdvInv.IDClass[it.id] or "?") .. (it.c and ("[" .. it.c .. "]") or "") .. "(" .. (it.r or 0) .. ")" end
    table.sort(t)
    return table.concat(t, " ")
end
local function spawnAt(class, pos)
    local e = ents.Create(class)
    e:SetPos(pos) e:Spawn() e:Activate()
    return e
end
player.CreateNextBot("Picker")
timer.Simple(1, function()
    local b = player.GetBots()[1]
    b:SetPos(Vector(-2800, -1800, -140))
    I.SetDefaults(b)
    local base = b:GetPos() + Vector(40, 0, 20)
    local crowbar = spawnAt("weapon_crowbar", base)
    local ar2 = spawnAt("weapon_ar2", base + Vector(0, 20, 0))
    local ak = spawnAt("weapon_ak472", base + Vector(0, 40, 0))
    local kit = spawnAt("item_healthkit", base + Vector(0, -20, 0))
    local ammo = spawnAt("item_ammo_ar2", base + Vector(0, -40, 0))
    local phys = spawnAt("weapon_physgun", base + Vector(0, 60, 0))
    timer.Simple(0.5, function()
        if IsValid(ar2) then ar2:SetClip1(17) end
        -- (the physgun isn't an item: the bot may already have walked over it and taken it)
        local function canPick(hookName, e) return IsValid(e) and hook.Run(hookName, b, e) or (not IsValid(e) and "taken") end
        out.walkOver = { crowbar = canPick("PlayerCanPickupWeapon", crowbar), physgun = canPick("PlayerCanPickupWeapon", phys),
            kit = canPick("PlayerCanPickupItem", kit) }
        out.items = { crowbar = I.ItemFromEntity(crowbar), ar2 = I.ItemFromEntity(ar2), ak = I.ItemFromEntity(ak),
            kit = I.ItemFromEntity(kit), ammo = I.ItemFromEntity(ammo), physgun = I.ItemFromEntity(phys) or "none" }
        -- Use each (I.Use has a 0.4 s delay between uses)
        local order = { crowbar, ar2, ak, kit, ammo }
        local k = 0
        local function nextUse()
            k = k + 1
            if k > #order then
                timer.Simple(0.2, function()
                    out.slots = {
                        primary = { b:GetNWInt("PrimaryWep"), b:GetNWString("PrimaryWepClass"), b:GetNWInt("PrimaryWepRounds"), I.CarryMode(b, "PrimaryWep") },
                        secondary = { b:GetNWInt("SecondaryWep"), b:GetNWString("SecondaryWepClass") },
                        hasCrowbar = IsValid(b:GetWeapon("weapon_crowbar")), hasAr2 = IsValid(b:GetWeapon("weapon_ar2")),
                        uniform = summary(I.Get(b, "Uniform")), load = I.Used(b, "Uniform"),
                        worldLeft = (IsValid(crowbar) and 1 or 0) + (IsValid(ar2) and 1 or 0) + (IsValid(ak) and 1 or 0) + (IsValid(kit) and 1 or 0) + (IsValid(ammo) and 1 or 0),
                        advinvEntityTable = b:AdvInvEntityTable("SecondaryWep") and b:AdvInvEntityTable("SecondaryWep").WeaponClass,
                    }
                    -- save / load round trip
                    local OWNER = "test_generic_owner"
                    local before = { summary(I.Get(b, "Uniform")), b:GetNWInt("PrimaryWep"), b:GetNWString("SecondaryWepClass"), I.CarryMode(b, "PrimaryWep") }
                    out.saved = I.Save(b, OWNER)
                    out.record = I.Record(OWNER) ~= nil
                    I.Clear(b)
                    out.cleared = { summary(I.Get(b, "Uniform")), b:GetNWInt("PrimaryWep"), IsValid(b:GetWeapon("weapon_crowbar")) }
                    I.Load(b, OWNER)
                    local after = { summary(I.Get(b, "Uniform")), b:GetNWInt("PrimaryWep"), b:GetNWString("SecondaryWepClass"), I.CarryMode(b, "PrimaryWep") }
                    out.roundTrip = { before = before, after = after, same = util.TableToJSON(before) == util.TableToJSON(after),
                        crowbarBack = IsValid(b:GetWeapon("weapon_crowbar")), ar2Back = IsValid(b:GetWeapon("weapon_ar2")) }
                    I.Load(b, "nobody_here") -- no record: empty inventory
                    out.loadUnknown = { b:GetNWInt("PrimaryWep"), summary(I.Get(b, "Uniform")) }
                    I.Load(b, OWNER) -- back for the rest of the test
                    out.deleted = I.DeleteRecord(OWNER) and I.Record(OWNER) == nil
                    -- take the crowbar off and drop it: a real weapon in the world again
                    local item = I.TakeOff(b, "SecondaryWep")
                    local ent = item and I.SpawnItem(item, b:GetPos() + Vector(0, 60, 30))
                    out.dropped = { class = IsValid(ent) and ent:GetClass(), item = item and summary({ item }), slotAfter = b:GetNWInt("SecondaryWep"), classAfter = b:GetNWString("SecondaryWepClass") }
                    -- death: generic things in the bag
                    RunConsoleCommand("advinv_death_drop", "3")
                    local pos = b:GetPos()
                    b:Kill()
                    timer.Simple(0.6, function()
                        local body
                        for _, e in ipairs(ents.FindByClass("prop_ragdoll")) do if I.IsBody(e) then body = e end end
                        out.body = IsValid(body) and summary(I.Get(body, "Uniform")) or "no body"
                        done(out)
                    end)
                end)
                return
            end
            I.Use(b, order[k])
            b.AdvInvUseDelay = 0
            timer.Simple(0.05, nextUse)
        end
        nextUse()
    end)
end)
