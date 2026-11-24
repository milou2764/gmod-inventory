-- Compatibility with Workshop addons (sh_compat.lua): run with only some of the addons installed
-- (the test server had Fallout 76 backpacks, Imperial helmets and the H.E.V tactical vest).
local done = ASYNC(30)
local I = AdvInv
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
local out = { packs = {} }
local total, avail = 0, 0
for _, pack in ipairs(I.CompatPacks) do
    out.packs[pack.key] = pack.installed and "installed" or "-"
    for _, it in ipairs(pack.items) do
        total = total + 1
        local t = scripted_ents.Get(it.class)
        if t and t.AdvInvAvailable then avail = avail + 1 end
        assert(I.ClassID[it.class] == it.id, "id " .. it.class)
    end
end
out.items = { registered = total, available = avail }
out.idClass = { [1060] = I.IDClass[1060], [1000] = I.IDClass[1000], [1050] = I.IDClass[1050] }
local fo76 = scripted_ents.Get("advinv_c_fo76_backpacks_backpack_bomber")
out.bomber = fo76 and { base = fo76.Base, cat = fo76.Category, load = fo76.MaxLoad, mass = fo76.Mass, blocks = fo76.BlocksCarryZones and fo76.BlocksCarryZones.back, spawnable = fo76.Spawnable, attachBone = fo76.Attach and fo76.Attach.bone }
local missing = scripted_ents.Get("advinv_c_fo3_custom_backpack_1")
out.missingPack = missing and { spawnable = missing.Spawnable, available = missing.AdvInvAvailable }
out.info = { name = I.Info(1060).name, cat = I.Info(1060).cat, maxLoad = I.Info(1060).maxLoad, mass = I.Info(1060).mass }

player.CreateNextBot("Compat")
timer.Simple(1, function()
    local b = player.GetBots()[1]
    b:SetPos(Vector(-2800, -700, -140))
    I.SetDefaults(b)
    local packID = I.ClassID["advinv_c_fo76_backpacks_backpack_bomber"]
    local helmID = I.ClassID["advinv_c_sw_imperial_mew2_vader_helm"]
    local vestID = I.ClassID["advinv_c_hev_tactical_vest_hevsuit"]
    out.equip = {
        pack = { I.Equip(b, { id = packID }, { { id = I.ClassID.advinv_ammo_pistol, r = 20 } }) },
        helmet = { I.Equip(b, { id = helmID, a = 77 }) },
        vest = { I.Equip(b, { id = vestID, a = 90 }) },
    }
    out.slots = { b:GetNW2Int("Rucksack"), b:GetNW2Int("Helmet"), b:GetNW2Int("Vest"), I.MaxLoad(b, "Rucksack"), I.MaxLoad(b, "Vest") }
    -- save / load with IDs above 127
    I.Save(b, "test_compat")
    I.Clear(b)
    I.Load(b, "test_compat")
    out.afterLoad = { b:GetNW2Int("Rucksack"), b:GetNW2Int("Helmet"), b:GetNW2Int("Vest"), b:GetNWInt("HelmetArmor"), #I.Get(b, "Rucksack") }
    I.DeleteRecord("test_compat")
    -- a pack that is not installed: refused by the admin "give"
    local saved = { net.ReadEntity, net.ReadUInt, net.ReadString }
    local reads = { b, I.ClassID["advinv_c_fo3_custom_backpack_1"], 1 }
    local k = 0
    net.ReadEntity = function() return b end
    net.ReadUInt = function(bits) k = k + 1 return k == 1 and I.ClassID["advinv_c_fo3_custom_backpack_1"] or 1 end
    net.ReadString = function() return "" end
    local admin = player.GetBots()[1]
    out.giveMissing = { pcall(function() return I.AdminGive and I.AdminGive(admin) end) }
    net.ReadEntity, net.ReadUInt, net.ReadString = saved[1], saved[2], saved[3]
    -- items on the ground keep their ID
    local ent = I.SpawnItem({ id = packID }, b:GetPos() + Vector(60, 0, 20))
    out.ground = IsValid(ent) and { class = ent:GetClass(), model = ent:GetModel(), item = I.ItemFromEntity(ent) and I.ItemFromEntity(ent).id }
    timer.Simple(0.5, function() if IsValid(ent) then ent:Remove() end done(out) end)
end)
