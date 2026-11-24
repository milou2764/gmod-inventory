-- Gear of the playermodel itself (sh_modelgear.lua). A bodygroup is taken off under our item (the Day
-- of Defeat soldiers' helmet); gear in the mesh refuses ours (headgear on headgear, vest on vest, backpack
-- on backpack), and a player who takes such a playermodel while wearing ours gets it back (inventory, or
-- at the feet, with what it holds). Needs a bot. Synchronous: it calls AdvInv.ApplyModelGear /
-- GearBuiltInCheck itself. The vest part needs a compatible vest addon (else only the rule is checked).
local I, C = AdvInv, AdvInv.ClassID
local b = player.GetBots()[1]
if not IsValid(b) then return { skipped = "no bot" } end
if not b:Alive() then b:Spawn() end
local out = {}
local function helmet() return { id = C.advinv_barney_helmet, a = 100 } end
local function where(class)
    for _, cont in ipairs(I.ContainersOf(b)) do
        for _, it in ipairs(I.Get(b, cont)) do
            if it.id == C[class] then return "inventory" end
        end
    end
    for _, e in ipairs(ents.FindInSphere(b:GetPos(), 150)) do
        if e:GetClass() == class then
            local n = e.AdvInvContents and #e.AdvInvContents or 0
            e:Remove()
            return n > 0 and ("ground with " .. n) or "ground"
        end
    end
    return "lost"
end
I.SetDefaults(b)

-- headgear in the mesh: refused, with the message
b:SetModel("models/player/combine_soldier.mdl")
local ok, why = I.Equip(b, helmet())
out.combineHelmetRefused = ok == false                            -- true
out.combineHelmetMessage = why == I.L("msg_headgear_on_headgear") -- true
out.combineSlotEmpty = b:GetNW2Int("Helmet") <= 1                 -- true
out.combineHasVest = I.HasBuiltInGear(b, "Vest")                  -- true
out.combineNoPack = not I.HasBuiltInGear(b, "Rucksack")           -- true
-- a rebel: beanie, vest and backpack; another slot is still fine (a mask)
b:SetModel("models/player/group03/male_04.mdl")
out.rebelHelmetRefused = I.Equip(b, helmet()) == false            -- true
local okPack, whyPack = I.Equip(b, { id = C.advinv_jetpack }, {})
out.rebelPackRefused = okPack == false                            -- true
out.rebelPackMessage = whyPack == I.L("msg_backpack_on_backpack") -- true
out.rebelMaskOK = I.Equip(b, { id = C.advinv_cp_mask, a = 0 }) == true -- true
I.TakeOff(b, "Gasmask")
local vest = C.advinv_c_dayz_police_vest_vest_police or C.advinv_c_petruz_pmc_chalecopmc
if vest then
    local okV, whyV = I.Equip(b, { id = vest, a = 0 }, {})
    out.rebelVestRefused = okV == false                           -- true
    out.rebelVestMessage = whyV == I.L("msg_vest_on_vest")        -- true
end

-- a bare citizen wears them; taking a playermodel with its own gives ours back
b:SetModel("models/player/group01/male_07.mdl")
out.citizenWearsHelmet = I.Equip(b, helmet()) == true             -- true
out.citizenWearsPack = I.Equip(b, { id = C.advinv_jetpack }, { { id = C.advinv_barney_helmet, a = 100 } }) == true -- true
b:SetModel("models/player/group03m/male_02.mdl") -- a medic: vest and medical backpack, no headgear
I.GearBuiltInCheck(b)
out.medicKeepsHelmet = b:GetNW2Int("Helmet") > 1                  -- true (a medic's head is bare)
out.medicPackTakenOff = b:GetNW2Int("Rucksack") <= 1              -- true
out.medicPackKept = where("advinv_jetpack")                       -- "ground with 1" (it holds something: down with it)
b:SetModel("models/player/police.mdl")
I.GearBuiltInCheck(b)
out.policeHelmetTakenOff = b:GetNW2Int("Helmet") <= 1             -- true
out.policeHelmetKept = where("advinv_barney_helmet")              -- "inventory" (or "ground" without room), never "lost"

-- Day of Defeat: its own helmet (bodygroup 1) is gear, locked: picked in a menu, it goes off again;
-- our helmet over it; its webbing refuses a vest
b:SetModel("models/player/dod_american.mdl")
I.ApplyModelGear(b)
b:SetBodygroup(1, 0) -- the player picks the helmet
I.ApplyModelGear(b)  -- (the 1 s timer does it in game)
out.dodPickedHelmetOff = b:GetBodygroup(1)                        -- 1 (none: only an item shows gear)
out.dodWears = I.Equip(b, helmet()) == true                       -- true
I.ApplyModelGear(b)
out.dodUnderOurs = b:GetBodygroup(1)                              -- 1
I.TakeOff(b, "Helmet")
I.ApplyModelGear(b)
out.dodAfter = b:GetBodygroup(1)                                  -- 1
out.dodHasVest = I.HasBuiltInGear(b, "Vest")                      -- true

-- Vault-Tec (Workshop 3612720459, if installed): only the helmeted outfits refuse
local V = "models/humans/vaulttec/male_01.mdl"
if util.IsValidModel(V) then
    b:SetModel(V)
    b:SetBodygroup(2, 0) -- vault suit
    out.vaultSuitWears = I.Equip(b, helmet()) == true             -- true
    b:SetBodygroup(2, 3) -- the hazard suit and its hood
    I.GearBuiltInCheck(b)
    out.vaultHoodTakesItOff = b:GetNW2Int("Helmet") <= 1          -- true
    b:SetBodygroup(2, 1) -- the security suit: helmet and armour vest
    out.vaultSecurityRefused = I.Equip(b, helmet()) == false      -- true
    out.vaultSecurityVest = I.HasBuiltInGear(b, "Vest")           -- true
    b:SetBodygroup(2, 0)
end

b:SetModel("models/player/group01/male_07.mdl")
for _, cat in ipairs({ "Helmet", "Rucksack", "Vest" }) do
    if b:GetNW2Int(cat) > 1 then I.TakeOff(b, cat) end
end
I.SetDefaults(b)
return out
