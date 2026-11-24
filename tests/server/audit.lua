-- Fixes of the code audits (exploits, duplication, item loss). DarkRP.
local done = ASYNC(60)
local I = AdvInv
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
local out = {}
local function count(ply, pred)
    local n = 0
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        for _, it in ipairs(I.Get(ply, cont)) do if pred(it) then n = n + 1 end end
    end
    return n
end
local AR2 = I.ClassID.advinv_hl2_ar2
local BOX = I.ClassID.advinv_ammo_ar2
local function step(list, i)
    i = i or 1
    if i > #list then return done(out) end
    local ok, err = pcall(list[i][2])
    if not ok then out["error_" .. list[i][1]] = tostring(err) end
    timer.Simple(list[i][3] or 0.5, function() step(list, i + 1) end)
end
player.CreateNextBot("A")
player.CreateNextBot("B")
timer.Simple(1.5, function()
    local a, b = player.GetBots()[1], player.GetBots()[2]
    a:SetPos(Vector(-2800, -500, -140)) b:SetPos(Vector(-2760, -500, -140))
    I.SetDefaults(a) I.SetDefaults(b)
    local ground, wep
    step({
        { "giveswep", function()
            -- the hook no longer decides (returns nothing): the gamemode does
            out.giveSWEPHook = select("#", hook.GetTable().PlayerGiveSWEP.AdvInv_GiveSWEP(a, "weapon_ar2", weapons.Get("weapon_ar2"))) -- 0: returns nothing
            out.darkrpDecision = tostring(gamemode.Call("PlayerGiveSWEP", a, "weapon_ar2", {}))
            -- allowed: the weapon given goes into the slot, no copy left in hand outside it
            a:Give("weapon_ar2")
        end, 0.6 },
        { "giveswepAfter", function()
            out.afterGive = { slot = a:GetNWInt("PrimaryWep"), has = a:HasWeapon("weapon_ar2") }
            I.TakeOff(a, "PrimaryWep")
            -- equip: no free reserve (no AR2 box tracked)
            a:SetAmmo(0, "AR2")
            I.Equip(a, { id = AR2, r = 10 })
            out.reserveAfterEquip = a:GetAmmoCount("AR2")
            out.clipAfterEquip = a:GetWeapon("weapon_ar2"):Clip1()
        end },
        { "doubleTake", function()
            ground = I.SpawnItem({ id = BOX, r = 30 }, a:GetPos() + Vector(20, 0, 10))
            a.AdvInvUseDelay, b.AdvInvUseDelay = 0, 0
            I.Use(a, ground)
            I.Use(b, ground) -- same tick
            out.doubleTake = { a = count(a, function(it) return it.id == BOX end), b = count(b, function(it) return it.id == BOX end) }
        end },
        { "stripAmmo", function()
            I.SyncAmmo(a)
            local before = a:GetAmmoCount("AR2")
            a:StripAmmo()
            out.stripAmmo = { reserveBefore = before, boxesRightAfter = count(a, function(it) return it.id == BOX end) }
        end, 0.5 },
        { "stripAmmoAfter", function()
            out.stripAmmo.reserveAfter = a:GetAmmoCount("AR2")
            out.stripAmmo.boxesAfter = count(a, function(it) return it.id == BOX end)
        end },
        { "darkrpDrop", function()
            a:SelectWeapon("weapon_ar2")
            wep = a:GetWeapon("weapon_ar2")
            wep:SetClip1(7)
            a:dropDRPWeapon(wep)
        end, 0.6 },
        { "darkrpDropAfter", function()
            local sw
            for _, e in ipairs(ents.FindByClass("spawned_weapon")) do sw = e end
            out.darkrpDrop = { slot = a:GetNWInt("PrimaryWep"), has = a:HasWeapon("weapon_ar2"),
                ammoadd = IsValid(sw) and sw.ammoadd, clip = IsValid(sw) and sw.clip1,
                boxes = count(a, function(it) return it.id == BOX end), reserve = a:GetAmmoCount("AR2") }
            if IsValid(sw) then
                b.AdvInvUseDelay = 0
                I.Use(b, sw)
            end
        end },
        { "pickedByB", function()
            out.pickedByB = { slot = b:GetNWInt("PrimaryWep"), clip = IsValid(b:GetWeapon("weapon_ar2")) and b:GetWeapon("weapon_ar2"):Clip1() }
            -- a third-party drop (not DarkRP's): the slot is freed, the world weapon is the item
            b:SelectWeapon("weapon_ar2")
            b:DropWeapon(b:GetWeapon("weapon_ar2"))
        end, 0.5 },
        { "thirdPartyDrop", function()
            local w
            for _, e in ipairs(ents.FindByClass("weapon_ar2")) do if not IsValid(e:GetOwner()) then w = e end end
            out.thirdPartyDrop = { slot = b:GetNWInt("PrimaryWep"), worldWeapon = IsValid(w) }
            if IsValid(w) then w:Remove() end
            -- strip + loadout (job change): the slot weapon comes back with its magazine
            I.Equip(b, { id = AR2, r = 12 })
            b:GetWeapon("weapon_ar2"):SetClip1(5)
            b:StripWeapons()
            out.stripped = { slot = b:GetNWInt("PrimaryWep"), has = b:HasWeapon("weapon_ar2") }
            hook.Run("PlayerLoadout", b)
        end, 0.5 },
        { "loadout", function()
            local w = b:GetWeapon("weapon_ar2")
            out.afterLoadout = { has = IsValid(w), clip = IsValid(w) and w:Clip1() }
        end },
        { "split", function()
            I.Set(a, "Uniform", { { id = I.GENERIC_AMMO, c = "SniperRound", r = 20 } })
            local saved = { net.ReadEntity, net.ReadUInt }
            local reads = { 1, 1, 8 } -- cont id (Uniform), index, rounds
            local k = 0
            net.ReadEntity = function() return a end
            net.ReadUInt = function() k = k + 1 return reads[k] end
            I.Actor = a
            pcall(I.ActHandlers[I.ACT.SPLIT], a)
            I.Actor = nil
            net.ReadEntity, net.ReadUInt = saved[1], saved[2]
            local list = I.Get(a, "Uniform")
            out.split = {}
            for _, it in ipairs(list) do out.split[#out.split + 1] = tostring(it.c) .. ":" .. it.r end
        end },
        { "unknownKept", function()
            sql.Query("REPLACE INTO advinv_inventory (OwnerID, Data) VALUES ('test_unknown', " ..
                SQLStr(util.TableToJSON({ v = 3, s = { Helmet = { 1999, 0, 50 } }, c = { Uniform = { { 1998, 5, 0 }, { BOX, 30, 0 } } } })) .. ")")
            I.Load(a, "test_unknown")
            out.unknownLoaded = { uniform = #I.Get(a, "Uniform"), helmet = a:GetNW2Int("Helmet") }
            I.Save(a, "test_unknown")
            local back = I.Record("test_unknown")
            out.unknownSaved = { helmet = back.s.Helmet and back.s.Helmet[1], uniform = #back.c.Uniform }
            I.DeleteRecord("test_unknown")
            -- corrupt record: copied aside, not lost
            sql.Query("REPLACE INTO advinv_inventory (OwnerID, Data) VALUES ('test_bad', '{not json')")
            I.Load(a, "test_bad")
            out.corruptBackup = sql.QueryValue("SELECT COUNT(*) FROM advinv_inventory_bad WHERE OwnerID = 'test_bad'")
            sql.Query("DELETE FROM advinv_inventory_bad WHERE OwnerID = 'test_bad'")
            I.DeleteRecord("test_bad")
        end },
        { "duplicator", function()
            out.duplicator = { crate = scripted_ents.Get("advinv_crate").DisableDuplicator, helmet = scripted_ents.Get("advinv_barney_helmet").DisableDuplicator,
                bank = scripted_ents.Get("advinv_bank").DisableDuplicator }
            -- death mode 1: what stays on the player (gear) is still his after respawn
            RunConsoleCommand("advinv_death_drop", "1")
            I.SetDefaults(b)
            I.Equip(b, { id = I.ClassID.advinv_barney_helmet, a = 40 })
        end, 0.3 },
        { "die", function() b:Kill() end, 0.5 },
        { "respawn", function() b:Spawn() end, 0.8 },
        { "afterRespawn", function()
            out.deathMode1 = { helmet = b:GetNW2Int("Helmet"), armor = b:GetNWInt("HelmetArmor") }
            RunConsoleCommand("advinv_death_drop", "3")
        end },
    })
end)
