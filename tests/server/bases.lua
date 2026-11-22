local done = ASYNC(20)
local I = AdvInv
local idOf = {}
for id, c in pairs(AdvInv.IDClass) do idOf[c] = id end
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
local out = {}
local function summary(items)
    local t = {}
    for _, it in ipairs(items) do t[#t + 1] = (AdvInv.IDClass[it.id] or "?") .. (it.c and ("[" .. it.c .. "]") or "") .. "(" .. (it.r or 0) .. ")" .. (it.x and ("{" .. it.x .. "}") or "") end
    table.sort(t)
    return table.concat(t, " ")
end
player.CreateNextBot("Gunner")
timer.Simple(1, function()
    local p = player.GetBots()[1]
    I.SetDefaults(p)
    p:SetPos(Vector(-2800, -1800, -140))
    out.boxFor = { I.AmmoBoxFor("SniperRound") }
    out.boxForAr2 = { I.AmmoBoxFor("AR2") }
    out.info = (function() local i = I.Info(I.GENERIC_AMMO, "SniperRound") return { name = i.name, isBox = i.isBox, ammo = i.ammo, rounds = i.boxRounds, mass = i.mass } end)()
    I.Store(p, I.NewItem(I.GENERIC_AMMO, "SniperRound"))
    I.GiveRounds(p, "SniperRound", 45)
    out.afterGive = summary(I.Get(p, "Uniform"))
    timer.Simple(0.2, function()
        out.reserve = p:GetAmmoCount("SniperRound")
        -- drop one box and take it back
        local items = I.Get(p, "Uniform")
        local box = table.remove(items, 1)
        I.MarkDirty(p, "Uniform")
        local ent = I.SpawnItem(box, p:GetPos() + Vector(40, 0, 20))
        out.dropped = { class = IsValid(ent) and ent:GetClass(), ammo = IsValid(ent) and ent:GetNWString("AdvInvAmmo"), item = IsValid(ent) and summary({ I.ItemFromEntity(ent) }) }
        I.PickupEntity(p, ent)
        out.afterPickup = summary(I.Get(p, "Uniform"))
        -- another base's ammo entity (fields AmmoType / AmmoCount)
        local fake = ents.Create("prop_physics")
        fake:SetModel("models/items/boxmrounds.mdl") fake:SetPos(p:GetPos() + Vector(60, 0, 20)) fake:Spawn()
        fake.AmmoType, fake.AmmoCount = "SniperRound", 12
        out.otherBase = summary({ I.ItemFromEntity(fake) })
        fake:Remove()
        -- extra weapon data through take off / save / equip
        local applied
        hook.Add("AdvInv_WeaponData", "t", function(w) if w:GetClass() == "weapon_ar2" then return "scope=acog" end end)
        hook.Add("AdvInv_ApplyWeaponData", "t", function(w, d) applied = w:GetClass() .. ":" .. d return true end)
        I.Set(p, "Uniform", {})
        I.Equip(p, { id = idOf.advinv_hl2_ar2, r = 10 })
        local item = I.TakeOff(p, "PrimaryWep")
        out.takenOff = summary({ item })
        local json = util.TableToJSON(I.PackItems({ item }))
        local back = I.UnpackItems(util.JSONToTable(json))
        out.roundTrip = summary(back)
        out.stackDiffers = I.StackKey(back[1]) ~= I.StackKey({ id = idOf.advinv_hl2_ar2, r = 10, a = 0 })
        I.Equip(p, back[1])
        timer.Simple(0.4, function()
            out.applied = applied
            hook.Remove("AdvInv_WeaponData", "t") hook.Remove("AdvInv_ApplyWeaponData", "t")
            done(out)
        end)
    end)
end)
