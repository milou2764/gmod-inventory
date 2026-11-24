-- Bodygroups of AdvInv.ModelGear (sh_modelgear.lua), gear locked: only an item worn shows it. Needs the National Guard Redux and WW1 French
-- playermodels (Workshop 3037475566, 3433822040) on the server, and a bot. Synchronous: it calls
-- AdvInv.ApplyModelGear itself (the hook does it on the next tick).
local I, C = AdvInv, AdvInv.ClassID
local NG = "models/rusty/natguard/player/male_03.mdl"
local WW1 = "models/adamwassim/player/imperialcommunity/ww1/soldatfrancais1.mdl"
if not util.IsValidModel(NG) or not util.IsValidModel(WW1) then return { skipped = "playermodels not installed" } end
if not C.advinv_c_adrian_adrian_helmet or not C.advinv_c_tank_crew_cvc_helmet then return { skipped = "compat addons not installed" } end
local b = player.GetBots()[1]
if not IsValid(b) then return { skipped = "no bot" } end
if not b:Alive() then b:Spawn() end
local out = {}
local function bg(ent, k) return ent:GetBodygroup(k) end

-- National Guard: a helmet takes the patrol cap off, taking it off gives it back
b:SetModel(NG)
I.SetDefaults(b)
b:SetBodygroup(3, 1) -- the player chose the beret
I.ApplyModelGear(b)
out.ngNoHelmet = bg(b, 3)                                   -- 2 (none: his beret is gear, locked)
I.Equip(b, { id = C.advinv_c_tank_crew_cvc_helmet, a = 50 })
I.ApplyModelGear(b)
out.ngHelmet = bg(b, 3)                                     -- 2 (none)
out.ngPropDrawn = not I.ShownByModel(b, b:GetNW2Int("Helmet")) -- true
I.TakeOff(b, "Helmet")
I.ApplyModelGear(b)
out.ngTakenOff = bg(b, 3)                                   -- 2 (still none)
out.ngOwnKept = b.AdvInvOwnBodygroups ~= nil               -- true (locked: tracked)

-- WW1: the Adrian is shown by the model's own bodygroup, another helmet takes theirs off
b:SetModel(WW1)
I.SetDefaults(b)
b:SetBodygroup(6, 4) -- kepi
b:SetBodygroup(9, 0) -- own backpack
I.ApplyModelGear(b)
I.Equip(b, { id = C.advinv_c_adrian_adrian_helmet, a = 60 })
I.ApplyModelGear(b)
out.ww1Adrian = bg(b, 6)                                    -- 0 (their Adrian)
out.ww1AdrianShownByModel = I.ShownByModel(b, b:GetNW2Int("Helmet")) -- true (no prop)
I.TakeOff(b, "Helmet")
I.Equip(b, { id = C.advinv_c_tank_crew_cvc_helmet, a = 50 })
I.ApplyModelGear(b)
out.ww1OtherHelmet = bg(b, 6)                               -- 6 (none)
local pack = C.advinv_c_fo76_backpacks_backpack_raider or C.advinv_c_fo3_campish_campish_pack
if pack then
    I.Equip(b, { id = pack, a = 0 }, {})
    I.ApplyModelGear(b)
    out.ww1Backpack = bg(b, 9)                              -- 2 (their own pack off)
    I.TakeOff(b, "Rucksack")
    I.ApplyModelGear(b)
    out.ww1BackpackOff = bg(b, 9)                           -- 2 (their own pack is gear: locked)
end
I.TakeOff(b, "Helmet")
I.ApplyModelGear(b)
out.ww1AllOff = bg(b, 6)                                    -- 6 (none: the kepi is gear, locked)

-- another playermodel: nothing is touched, and the saved values aren't applied to it
b:SetModel(WW1)
I.Equip(b, { id = C.advinv_c_tank_crew_cvc_helmet, a = 50 })
I.ApplyModelGear(b)
b:SetModel("models/player/group01/male_07.mdl")
I.ApplyModelGear(b)
out.otherModelCleared = b.AdvInvOwnBodygroups == nil        -- true
I.TakeOff(b, "Helmet")
return out
