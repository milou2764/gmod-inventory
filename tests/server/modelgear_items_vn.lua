-- The Vietnam US gear extension (addons/advinv-ext-vietnam-us): gear of NPC ragdolls (not playermodels)
-- worn as fitted copies. Needs the Vietnam era US Soldiers models on the server and a bot.
-- Asynchronous (the items dropped on the ground settle): run with ASYNC.
local I, C = AdvInv, AdvInv.ClassID
local done = ASYNC(12)
local P = "advinv_milou_vnus_"
local SOLDIER, CIT = "models/namsoldiers/male_01.mdl", "models/player/group01/male_07.mdl"
local CLASSES = { "m1_cover", "m1_cover_ace", "m1_born_to_kill", "m1", "boonie", "tropical_rucksack",
    "frame_rucksack", "radio", "web_gear", "web_gear_2", "web_gear_bandolier", "web_gear_m60_belt" }
if not I.Items[P .. "web_gear"] then return done({ skipped = "the Vietnam US gear extension isn't installed" }) end
if not util.IsValidModel(SOLDIER) then return done({ skipped = "the Vietnam era US Soldiers models aren't installed" }) end
local b = player.GetBots()[1]
if not IsValid(b) then return done({ skipped = "no bot" }) end
if not b:Alive() then b:Spawn() end
local out = { registered = 0, available = 0, physics = 0 }

-- every item: registered by name, available, on the ground with its hull's physics
local tr = util.TraceLine({ start = b:GetPos() + Vector(80, 0, 60), endpos = b:GetPos() + Vector(80, 0, -200) })
local spawned = {}
for k, c in ipairs(CLASSES) do
    local cls = P .. c
    if (C[cls] or 0) >= I.DYNAMIC_ID_START and I.IDClass[C[cls]] == cls then out.registered = out.registered + 1 end
    local t = scripted_ents.Get(cls)
    if t and t.AdvInvAvailable == true then out.available = out.available + 1 end
    local ent = ents.Create(cls)
    ent:SetPos(tr.HitPos + Vector((k - 6) * 30, 0, 30))
    ent:Spawn()
    if IsValid(ent:GetPhysicsObject()) then out.physics = out.physics + 1 end
    spawned[#spawned + 1] = { ent = ent, z = ent:GetPos().z }
end                                                                       -- registered, available, physics: 12

local web, frame, boonie, m1 = scripted_ents.Get(P .. "web_gear"), scripted_ents.Get(P .. "frame_rucksack"),
    scripted_ents.Get(P .. "boonie"), scripted_ents.Get(P .. "m1_cover")
out.webSlot = web.AdvInvCategory                                          -- "Vest"
out.storedNoSuspenders = web.ModelBodygroups[14] ~= web.WornBodygroups[14] -- true (folded away when stored)
out.storedNoCompass = web.ModelBodygroups[6] ~= web.WornBodygroups[6]     -- true (hangs from the suspenders)
out.webInPieces = web.ModelPieces ~= nil                                  -- true
out.frameBehindBack = frame.BackDepth ~= nil and frame.BackDepth > 8     -- true
out.m1Armor = m1.Armor                                                    -- 60
out.boonieArmor = boonie.Armor                                            -- 0
out.wornBox = web.WornBox ~= nil and web.WornBox[2].z > web.WornBox[1].z  -- true

-- worn on a citizen: fitted copies (not playermodels: never shown by a bodygroup)
I.SetDefaults(b)
b:SetModel(CIT)
out.wearsHelmet = I.Equip(b, { id = C[P .. "m1_born_to_kill"], a = 60 }) == true -- true
out.wearsVest = I.Equip(b, { id = C[P .. "web_gear_m60_belt"] }, {}) == true     -- true
out.wearsPack = I.Equip(b, { id = C[P .. "frame_rucksack"] }, {}) == true        -- true
out.helmetCopy = not I.ShownByModel(b, b:GetNW2Int("Helmet"))            -- true
I.Save(b, "advinv_test_mgv")
local rec = I.Record("advinv_test_mgv")
out.savedByClass = rec.s.Rucksack and rec.s.Rucksack[1]                   -- "advinv_milou_vnus_frame_rucksack"
I.DeleteRecord("advinv_test_mgv")
I.TakeOff(b, "Rucksack")
I.TakeOff(b, "Vest")
I.TakeOff(b, "Helmet")
I.SetDefaults(b)

timer.Simple(4, function()
    local fell, resting = 0, 0
    for _, s in ipairs(spawned) do
        if IsValid(s.ent) then
            local p = s.ent:GetPhysicsObject()
            if s.z - s.ent:GetPos().z > 5 then fell = fell + 1 end
            if IsValid(p) and (p:IsAsleep() or p:GetVelocity():Length() < 1) then resting = resting + 1 end
            s.ent:Remove()
        end
    end
    out.fell, out.resting = fell, resting                                -- 12, 12
    done(out)
end)
