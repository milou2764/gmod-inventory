--[[
    Playermodels with gear of their own as bodygroups (a cap, a helmet, a vest, a backpack). Gear is
    the inventory's business: such a bodygroup shows only while the matching item is worn.
    AdvInv.ModelGear[model] = {
        lock = { [bodygroup] = value },   -- headgear, vest, backpack bodygroups: that value (none)
                                          -- whatever the player picks (menu, job), unless an item
                                          -- worn sets another; { [gear value] = none value } locks
                                          -- only those values (a "Head" bodygroup whose choice 0 is a
                                          -- helmet and the others are faces: the faces stay free)
        items = { class = { [bodygroup] = value } }, -- an item that is this model's own gear: shown by
                                          -- the bodygroup, rigged for that body, not by a prop
        slots = { Slot = { [bodygroup] = value } },  -- other bodygroups, set while a slot holds an item
    }
    The player's own choice comes back when nothing asks for a bodygroup any more (sv_modelgear.lua).
    The fits of these playermodels are measured with the "none" values (tools/playermodel_bodygroups.txt).
    Servers add theirs (models in lowercase), e.g. in a shared autorun file:
        AdvInv.ModelGear["models/mine/soldier.mdl"] = { lock = { [2] = 0 }, items = { advinv_my_helmet = { [2] = 3 } } }
--]]
local I = AdvInv
I.ModelGear = I.ModelGear or {}
local G = I.ModelGear

local function def(model, t)
    if G[model] == nil then G[model] = t end -- a server's own entry wins
end

-- Rusty's National Guard Redux (Workshop 3037475566): bodygroup 3 = 0 patrol cap, 1 beret, 2 none; 2 = vest: 0 none, 1 harness
def("models/rusty/natguard/player/male_01.mdl", { lock = { [3] = 2, [2] = 0 } })
def("models/rusty/natguard/player/male_02.mdl", { lock = { [3] = 2, [2] = 0 } })
def("models/rusty/natguard/player/male_03.mdl", { lock = { [3] = 2, [2] = 0 } })
def("models/rusty/natguard/player/male_04.mdl", { lock = { [3] = 2, [2] = 0 } })
def("models/rusty/natguard/player/male_05.mdl", { lock = { [3] = 2, [2] = 0 } })
def("models/rusty/natguard/player/male_06.mdl", { lock = { [3] = 2, [2] = 0 } })
def("models/rusty/natguard/player/male_07.mdl", { lock = { [3] = 2, [2] = 0 } })
def("models/rusty/natguard/player/male_08.mdl", { lock = { [3] = 2, [2] = 0 } })
def("models/rusty/natguard/player/male_09.mdl", { lock = { [3] = 2, [2] = 0 } })
def("models/rusty/natguard/player/female_01.mdl", { lock = { [3] = 2, [2] = 0 } })
def("models/rusty/natguard/player/female_02.mdl", { lock = { [3] = 2, [2] = 0 } })
def("models/rusty/natguard/player/female_03.mdl", { lock = { [3] = 2, [2] = 0 } })
def("models/rusty/natguard/player/female_04.mdl", { lock = { [3] = 2, [2] = 0 } })
def("models/rusty/natguard/player/female_06.mdl", { lock = { [3] = 2, [2] = 0 } })
def("models/rusty/natguard/player/female_07.mdl", { lock = { [3] = 2, [2] = 0 } })
-- Star Wars Imperial Officers (Workshop 1133511197): bodygroup 2 = 0 cap, 1 none
def("models/player/swbf_imperial_officer_isbofficerv2/swbf_imperial_officer_isbofficerv2.mdl", { lock = { [2] = 1 } })
def("models/player/swbf_imperial_officer_lieutenantv2/swbf_imperial_officer_lieutenantv2.mdl", { lock = { [2] = 1 } })
def("models/player/swbf_imperial_officer_ensignv2/swbf_imperial_officer_ensignv2.mdl", { lock = { [2] = 1 } })
def("models/player/swbf_imperial_officer_commodorev2/swbf_imperial_officer_commodorev2.mdl", { lock = { [2] = 1 } })
def("models/player/swbf_imperial_officer_colonelv2/swbf_imperial_officer_colonelv2.mdl", { lock = { [2] = 1 } })
def("models/player/swbf_imperial_officer_admiralv2/swbf_imperial_officer_admiralv2.mdl", { lock = { [2] = 1 } })
def("models/player/swbf_imperial_officer_grand_admiralv2/swbf_imperial_officer_grand_admiralv2.mdl", { lock = { [2] = 1 } })
def("models/player/swbf_imperial_officer_ncov2/swbf_imperial_officer_ncov2.mdl", { lock = { [2] = 1 } })
def("models/player/swbf_imperial_isb_agentv2/swbf_imperial_isb_agentv2.mdl", { lock = { [2] = 1 } })
-- Rogue One Imperial crew (Workshop 2593940310): bodygroup 1 = their cap or helmet (none: no headgear, or a bare head)
def("models/nada/pms/female/admiral.mdl", { lock = { [1] = 4, [7] = { [3] = 0 } } })
def("models/nada/pms/female/admiral_esb.mdl", { lock = { [1] = 4, [7] = { [3] = 0 } } })
def("models/nada/pms/female/atst_driver.mdl", { lock = { [1] = 3 } })
def("models/nada/pms/female/black_naval_officer.mdl", { lock = { [1] = 4, [7] = { [3] = 0 } } })
def("models/nada/pms/female/bridgecrew.mdl", { lock = { [1] = 2 } })
def("models/nada/pms/female/grandadmiral.mdl", { lock = { [1] = 3, [4] = { [3] = 0 } } })
def("models/nada/pms/female/grey_admiral.mdl", { lock = { [1] = 4, [7] = { [3] = 0 } } })
def("models/nada/pms/female/groundcrew.mdl", { lock = { [1] = 1, [3] = 1 } })
def("models/nada/pms/female/gunner.mdl", { lock = { [1] = { [0] = 1 }, [2] = { [2] = 1 } } })
def("models/nada/pms/female/imperialweapontechnician.mdl", { lock = { [1] = { [0] = 1 }, [2] = { [2] = 1 } } })
def("models/nada/pms/female/mechanicalcrew.mdl", { lock = { [1] = 3 } })
def("models/nada/pms/female/medic.mdl", { lock = { [1] = 4, [7] = { [3] = 0 } } })
def("models/nada/pms/female/naval_officer.mdl", { lock = { [1] = 4, [7] = { [3] = 0 } } })
def("models/nada/pms/female/navy_trooper.mdl", { lock = { [1] = 3, [5] = { [3] = 0 } } })
def("models/nada/pms/female/navy_trooper_jr.mdl", { lock = { [1] = 3, [3] = { [1] = 0 } } })
def("models/nada/pms/female/scanner.mdl", { lock = { [1] = 2 } })
def("models/nada/pms/female/navy_colourable.mdl", { lock = { [1] = 4, [7] = { [3] = 0 } } })
def("models/nada/pms/male/admiral.mdl", { lock = { [1] = 4, [7] = { [3] = 0 } } })
def("models/nada/pms/male/admiral_esb.mdl", { lock = { [1] = 4, [7] = { [3] = 0 } } })
def("models/nada/pms/male/atst_driver.mdl", { lock = { [1] = 4 } })
def("models/nada/pms/male/black_naval_officer.mdl", { lock = { [1] = 4, [7] = { [3] = 0 } } })
def("models/nada/pms/male/bridgecrew.mdl", { lock = { [1] = 2 } })
def("models/nada/pms/male/grandadmiral.mdl", { lock = { [1] = 3, [4] = { [3] = 0 } } })
def("models/nada/pms/male/grey_admiral.mdl", { lock = { [1] = 4, [7] = { [3] = 0 } } })
def("models/nada/pms/male/groundcrew.mdl", { lock = { [1] = 1, [3] = 1 } })
def("models/nada/pms/male/gunner.mdl", { lock = { [1] = { [0] = 1 }, [2] = { [2] = 1 } } })
def("models/nada/pms/male/imperialweapontechnician.mdl", { lock = { [1] = { [0] = 1 }, [2] = { [2] = 1 } } })
def("models/nada/pms/male/mechanicalcrew.mdl", { lock = { [1] = 3 } })
def("models/nada/pms/male/medic.mdl", { lock = { [1] = 3, [7] = { [3] = 0 } } })
def("models/nada/pms/male/naval_officer.mdl", { lock = { [1] = 4, [7] = { [3] = 0 } } })
def("models/nada/pms/male/navy_trooper.mdl", { lock = { [1] = 3, [5] = { [3] = 0 } } })
def("models/nada/pms/male/navy_trooper_jr.mdl", { lock = { [1] = 3, [3] = { [1] = 0 } } })
def("models/nada/pms/male/scanner.mdl", { lock = { [1] = 2 } })
def("models/nada/pms/male/navy_colourable.mdl", { lock = { [1] = 4, [7] = { [3] = 0 } } })
-- WW1 French soldiers (Workshop 3433822040): bodygroup 6 = 0-3 their Adrian, 4 kepi, 5 beanie, 6 none; 9 = backpack, 2 none;
-- 5 = webbing straps, 1 none; 8 = cartridge pouches, 4 none (off under a vest)
def("models/adamwassim/player/imperialcommunity/ww1/soldatfrancais1.mdl", { lock = { [6] = 6, [9] = 2, [5] = 1, [8] = 4 }, items = { advinv_c_adrian_adrian_helmet = { [6] = 0 } } })
def("models/adamwassim/player/imperialcommunity/ww1/soldatfrancais2.mdl", { lock = { [6] = 6, [9] = 2, [5] = 1, [8] = 4 }, items = { advinv_c_adrian_adrian_helmet = { [6] = 0 } } })
def("models/adamwassim/player/imperialcommunity/ww1/soldatfrancais3.mdl", { lock = { [6] = 6, [9] = 2, [5] = 1, [8] = 4 }, items = { advinv_c_adrian_adrian_helmet = { [6] = 0 } } })
def("models/adamwassim/player/imperialcommunity/ww1/soldatfrancais4.mdl", { lock = { [6] = 6, [9] = 2, [5] = 1, [8] = 4 }, items = { advinv_c_adrian_adrian_helmet = { [6] = 0 } } })
def("models/adamwassim/player/imperialcommunity/ww1/soldatfrancais5.mdl", { lock = { [6] = 6, [9] = 2, [5] = 1, [8] = 4 }, items = { advinv_c_adrian_adrian_helmet = { [6] = 0 } } })
def("models/adamwassim/player/imperialcommunity/ww1/soldatfrancais6.mdl", { lock = { [6] = 6, [9] = 2, [5] = 1, [8] = 4 }, items = { advinv_c_adrian_adrian_helmet = { [6] = 0 } } })
-- Russian Army | RF Soldier (Workshop 2764717646): bodygroup 3 = 0 helmet, 1 none; 4 = 0 plate carrier, 1 none
def("models/leygun/rfarmy/soilder_rf_02.mdl", { lock = { [3] = 1, [4] = 1 } })
def("models/leygun/rfarmy/soilder_rf_04.mdl", { lock = { [3] = 1, [4] = 1 } })
def("models/leygun/rfarmy/soilder_rf_05.mdl", { lock = { [3] = 1, [4] = 1 } })
def("models/leygun/rfarmy/soilder_rf_07.mdl", { lock = { [3] = 1, [4] = 1 } })
def("models/leygun/rfarmy/soilder_rf_08.mdl", { lock = { [3] = 1, [4] = 1 } })
def("models/leygun/rfarmy/soilder_rf_09.mdl", { lock = { [3] = 1, [4] = 1 } })
-- Civil War Soldiers (Workshop 3614216336): bodygroup 3 = 0 kepi, 1 none
def("models/humans/civilwar/male_01.mdl", { lock = { [3] = 1 } })
def("models/humans/civilwar/male_02.mdl", { lock = { [3] = 1 } })
def("models/humans/civilwar/male_03.mdl", { lock = { [3] = 1 } })
def("models/humans/civilwar/male_04.mdl", { lock = { [3] = 1 } })
def("models/humans/civilwar/male_06.mdl", { lock = { [3] = 1 } })
def("models/humans/civilwar/male_07.mdl", { lock = { [3] = 1 } })
def("models/humans/civilwar/male_08.mdl", { lock = { [3] = 1 } })
def("models/humans/civilwar/male_09.mdl", { lock = { [3] = 1 } })
-- RS2: Forces of the East (Workshop 2944903873): PAVN 5 = pith helmet, 6 = AK chest rig, 7-9 = grenade pouch
-- and grenades, 10 = backpack (0 the gear, 1 none); Viet Minh 2 = 0-3 hats and helmets, 4 none
def("models/player/kerberos_risingstorm2.mdl", { lock = { [5] = 1, [6] = 1, [7] = 1, [8] = 1, [9] = 1, [10] = 1 } })
def("models/player/kerberos_risingstorm3.mdl", { lock = { [5] = 1, [6] = 1, [7] = 1, [8] = 1, [9] = 1, [10] = 1 } })
def("models/vietnam/humans/vc/gmod/vc_1.mdl", { lock = { [2] = 4 } })
def("models/vietnam/humans/vc/gmod/vc_5.mdl", { lock = { [2] = 4 } })
-- PMC Pack Redux (Workshop 1769231405): 3 = head (0 none, 1-9 caps and helmets), 6 = helmet visor, 5 = headsets,
-- 4 = face: 4-7 gas masks, 8 night vision locked (1-3 glasses and goggles stay free), 10 = back (0 none);
-- their plate carrier is built in (no Vest item on them): its chest pouches, belt, holster and leg pouches stay free
def("models/pmc/pmc_1/pmc_pm.mdl", { lock = { [3] = 0, [6] = 0, [5] = 0, [4] = { [4] = 0, [5] = 0, [6] = 0, [7] = 0, [8] = 0 }, [10] = 0 } })
def("models/pmc/pmc_2/acu_pm.mdl", { lock = { [3] = 0, [6] = 0, [5] = 0, [4] = { [4] = 0, [5] = 0, [6] = 0, [7] = 0, [8] = 0 }, [10] = 0 } })
def("models/pmc/pmc_3/mpt_pm.mdl", { lock = { [3] = 0, [6] = 0, [5] = 0, [4] = { [4] = 0, [5] = 0, [6] = 0, [7] = 0, [8] = 0 }, [10] = 0 } })
def("models/pmc/pmc_4/swat_pm.mdl", { lock = { [3] = 0, [6] = 0, [5] = 0, [4] = { [4] = 0, [5] = 0, [6] = 0, [7] = 0, [8] = 0 }, [10] = 0 } })
def("models/pmc/pmc_5/sas_pm.mdl", { lock = { [3] = 0, [6] = 0, [5] = 0, [4] = { [4] = 0, [5] = 0, [6] = 0, [7] = 0, [8] = 0 }, [10] = 0 } })
def("models/pmc/pmc_6/desert_pm.mdl", { lock = { [3] = 0, [6] = 0, [5] = 0, [4] = { [4] = 0, [5] = 0, [6] = 0, [7] = 0, [8] = 0 }, [10] = 0 } })
def("models/pmc/pmc_7/super_pm.mdl", { lock = { [3] = 0, [6] = 0, [5] = 0, [4] = { [4] = 0, [5] = 0, [6] = 0, [7] = 0, [8] = 0 }, [10] = 0 } })
def("models/pmc/pmc_8/snw_pm.mdl", { lock = { [3] = 0, [6] = 0, [5] = 0, [4] = { [4] = 0, [5] = 0, [6] = 0, [7] = 0, [8] = 0 }, [10] = 0 } })
-- Day of Defeat: Source soldiers: bodygroup 1 = 0 their helmet, 1 none
def("models/player/dod_american.mdl", { lock = { [1] = 1 } })
def("models/player/dod_german.mdl", { lock = { [1] = 1 } })
-- Half-Life 2 zombie: bodygroup 1 = 0 none, 1 a headcrab on the head
def("models/player/zombie_classic.mdl", { slots = { Helmet = { [1] = 0 } } })

--[[
    Gear that is part of a playermodel's mesh (no bodygroup takes it off): nothing of that kind can be
    worn over it. It is impossible to put headgear on another headgear, a vest on another vest, a
    backpack on another backpack: AdvInv.Equip refuses it (sv_containers.lua), and a player who takes
    such a playermodel (or bodygroup) while wearing one gets it back (sv_modelgear.lua).
    AdvInv.GearBuiltIn[model] = { Helmet = true, Vest = true, Rucksack = true }; a slot can also be
    { [bodygroup] = { [value] = true, ... } } when only some of its bodygroup choices have that gear,
    or false to allow it. Servers add theirs (models in lowercase), e.g. in a shared autorun file:
        AdvInv.GearBuiltIn["models/mine/knight.mdl"] = { Helmet = true, Vest = true }
--]]
I.GearBuiltIn = I.GearBuiltIn or {}
local B = I.GearBuiltIn
-- the slots it applies to, and what the player is told
I.GearBuiltInMessages = I.GearBuiltInMessages or {
    Helmet = "msg_headgear_on_headgear", Vest = "msg_vest_on_vest", Rucksack = "msg_backpack_on_backpack",
}

local function builtin(model, slot, t)
    B[model] = B[model] or {}
    if B[model][slot] == nil then B[model][slot] = t or true end -- a server's own value wins
end

-- Half-Life 2: the Combine soldiers' and Civil Protection's helmet and vest, the zombine's; Barney's vest, Eli's
builtin("models/player/combine_soldier.mdl", "Helmet")
builtin("models/player/combine_soldier.mdl", "Vest")
builtin("models/player/combine_soldier_prisonguard.mdl", "Helmet")
builtin("models/player/combine_soldier_prisonguard.mdl", "Vest")
builtin("models/player/combine_super_soldier.mdl", "Helmet")
builtin("models/player/combine_super_soldier.mdl", "Vest")
builtin("models/player/police.mdl", "Helmet")
builtin("models/player/police.mdl", "Vest")
builtin("models/player/police_fem.mdl", "Helmet")
builtin("models/player/police_fem.mdl", "Vest")
builtin("models/player/zombie_soldier.mdl", "Helmet")
builtin("models/player/zombie_soldier.mdl", "Vest")
builtin("models/player/barney.mdl", "Vest")
builtin("models/player/eli.mdl", "Vest")
-- Half-Life 2 rebels: beanie, vest and backpack; the medics: vest and medical backpack (one with a cap)
builtin("models/player/group03/female_01.mdl", "Helmet")
builtin("models/player/group03/female_01.mdl", "Vest")
builtin("models/player/group03/female_01.mdl", "Rucksack")
builtin("models/player/group03/female_02.mdl", "Helmet")
builtin("models/player/group03/female_02.mdl", "Vest")
builtin("models/player/group03/female_02.mdl", "Rucksack")
builtin("models/player/group03/female_03.mdl", "Helmet")
builtin("models/player/group03/female_03.mdl", "Vest")
builtin("models/player/group03/female_03.mdl", "Rucksack")
builtin("models/player/group03/female_04.mdl", "Helmet")
builtin("models/player/group03/female_04.mdl", "Vest")
builtin("models/player/group03/female_04.mdl", "Rucksack")
builtin("models/player/group03/female_05.mdl", "Helmet")
builtin("models/player/group03/female_05.mdl", "Vest")
builtin("models/player/group03/female_05.mdl", "Rucksack")
builtin("models/player/group03/female_06.mdl", "Helmet")
builtin("models/player/group03/female_06.mdl", "Vest")
builtin("models/player/group03/female_06.mdl", "Rucksack")
builtin("models/player/group03/male_01.mdl", "Helmet")
builtin("models/player/group03/male_01.mdl", "Vest")
builtin("models/player/group03/male_01.mdl", "Rucksack")
builtin("models/player/group03/male_02.mdl", "Helmet")
builtin("models/player/group03/male_02.mdl", "Vest")
builtin("models/player/group03/male_02.mdl", "Rucksack")
builtin("models/player/group03/male_03.mdl", "Helmet")
builtin("models/player/group03/male_03.mdl", "Vest")
builtin("models/player/group03/male_03.mdl", "Rucksack")
builtin("models/player/group03/male_04.mdl", "Helmet")
builtin("models/player/group03/male_04.mdl", "Vest")
builtin("models/player/group03/male_04.mdl", "Rucksack")
builtin("models/player/group03/male_05.mdl", "Helmet")
builtin("models/player/group03/male_05.mdl", "Vest")
builtin("models/player/group03/male_05.mdl", "Rucksack")
builtin("models/player/group03/male_06.mdl", "Helmet")
builtin("models/player/group03/male_06.mdl", "Vest")
builtin("models/player/group03/male_06.mdl", "Rucksack")
builtin("models/player/group03/male_07.mdl", "Helmet")
builtin("models/player/group03/male_07.mdl", "Vest")
builtin("models/player/group03/male_07.mdl", "Rucksack")
builtin("models/player/group03/male_08.mdl", "Helmet")
builtin("models/player/group03/male_08.mdl", "Vest")
builtin("models/player/group03/male_08.mdl", "Rucksack")
builtin("models/player/group03/male_09.mdl", "Helmet")
builtin("models/player/group03/male_09.mdl", "Vest")
builtin("models/player/group03/male_09.mdl", "Rucksack")
builtin("models/player/group03m/female_01.mdl", "Vest")
builtin("models/player/group03m/female_01.mdl", "Rucksack")
builtin("models/player/group03m/female_02.mdl", "Vest")
builtin("models/player/group03m/female_02.mdl", "Rucksack")
builtin("models/player/group03m/female_03.mdl", "Helmet")
builtin("models/player/group03m/female_03.mdl", "Vest")
builtin("models/player/group03m/female_03.mdl", "Rucksack")
builtin("models/player/group03m/female_04.mdl", "Vest")
builtin("models/player/group03m/female_04.mdl", "Rucksack")
builtin("models/player/group03m/female_05.mdl", "Vest")
builtin("models/player/group03m/female_05.mdl", "Rucksack")
builtin("models/player/group03m/female_06.mdl", "Vest")
builtin("models/player/group03m/female_06.mdl", "Rucksack")
builtin("models/player/group03m/male_01.mdl", "Vest")
builtin("models/player/group03m/male_01.mdl", "Rucksack")
builtin("models/player/group03m/male_02.mdl", "Vest")
builtin("models/player/group03m/male_02.mdl", "Rucksack")
builtin("models/player/group03m/male_03.mdl", "Vest")
builtin("models/player/group03m/male_03.mdl", "Rucksack")
builtin("models/player/group03m/male_04.mdl", "Vest")
builtin("models/player/group03m/male_04.mdl", "Rucksack")
builtin("models/player/group03m/male_05.mdl", "Vest")
builtin("models/player/group03m/male_05.mdl", "Rucksack")
builtin("models/player/group03m/male_06.mdl", "Vest")
builtin("models/player/group03m/male_06.mdl", "Rucksack")
builtin("models/player/group03m/male_07.mdl", "Vest")
builtin("models/player/group03m/male_07.mdl", "Rucksack")
builtin("models/player/group03m/male_08.mdl", "Vest")
builtin("models/player/group03m/male_08.mdl", "Rucksack")
builtin("models/player/group03m/male_09.mdl", "Vest")
builtin("models/player/group03m/male_09.mdl", "Rucksack")
builtin("models/player/odessa.mdl", "Helmet")
-- Counter-Strike: Source: helmets, balaclavas, tactical vests
builtin("models/player/riot.mdl", "Helmet")
builtin("models/player/riot.mdl", "Vest")
builtin("models/player/swat.mdl", "Helmet")
builtin("models/player/swat.mdl", "Vest")
builtin("models/player/urban.mdl", "Helmet")
builtin("models/player/urban.mdl", "Vest")
builtin("models/player/gasmask.mdl", "Helmet")
builtin("models/player/gasmask.mdl", "Vest")
builtin("models/player/arctic.mdl", "Helmet")
builtin("models/player/phoenix.mdl", "Helmet")
builtin("models/player/phoenix.mdl", "Vest")
builtin("models/player/guerilla.mdl", "Vest")
-- Day of Defeat: Source: webbing and ammo pouches (their helmet is a bodygroup: ModelGear above)
builtin("models/player/dod_american.mdl", "Vest")
builtin("models/player/dod_german.mdl", "Vest")
-- Rebel pilot (Workshop 1268173091): flight vest
builtin("models/gonzo/rebelpilotvariant/rebelpilotvariant.mdl", "Vest")
-- Rogue One Imperial crew (Workshop 2593940310): the ground crew's chest rig (its armoured bodies are locked bodygroups)
builtin("models/nada/pms/male/groundcrew.mdl", "Vest")
builtin("models/nada/pms/female/groundcrew.mdl", "Vest")
-- Vault-Tec (Workshop 3612720459): bodygroup 2 = outfit, 1 the security suit (helmet, armour vest), 3 the hazard suit (hood)
builtin("models/humans/vaulttec/male_01.mdl", "Helmet", { [2] = { [1] = true, [3] = true } })
builtin("models/humans/vaulttec/male_01.mdl", "Vest", { [2] = { [1] = true } })
builtin("models/humans/vaulttec/male_02.mdl", "Helmet", { [2] = { [1] = true, [3] = true } })
builtin("models/humans/vaulttec/male_02.mdl", "Vest", { [2] = { [1] = true } })
builtin("models/humans/vaulttec/male_03.mdl", "Helmet", { [2] = { [1] = true, [3] = true } })
builtin("models/humans/vaulttec/male_03.mdl", "Vest", { [2] = { [1] = true } })
builtin("models/humans/vaulttec/male_04.mdl", "Helmet", { [2] = { [1] = true, [3] = true } })
builtin("models/humans/vaulttec/male_04.mdl", "Vest", { [2] = { [1] = true } })
-- PMC Pack Redux (Workshop 1769231405): the plate carrier is part of their body (the pouches on it are bodygroups)
builtin("models/pmc/pmc_1/pmc_pm.mdl", "Vest")
builtin("models/pmc/pmc_2/acu_pm.mdl", "Vest")
builtin("models/pmc/pmc_3/mpt_pm.mdl", "Vest")
builtin("models/pmc/pmc_4/swat_pm.mdl", "Vest")
builtin("models/pmc/pmc_5/sas_pm.mdl", "Vest")
builtin("models/pmc/pmc_6/desert_pm.mdl", "Vest")
builtin("models/pmc/pmc_7/super_pm.mdl", "Vest")
builtin("models/pmc/pmc_8/snw_pm.mdl", "Vest")
-- Civil War Soldiers (Workshop 3614216336): the Union soldiers' knapsack and bedroll are part of their outfit
builtin("models/humans/civilwar/male_01.mdl", "Rucksack")
builtin("models/humans/civilwar/male_02.mdl", "Rucksack")
builtin("models/humans/civilwar/male_03.mdl", "Rucksack")
builtin("models/humans/civilwar/male_04.mdl", "Rucksack")

-- True when the entity's playermodel (and its bodygroups) already has gear of its own in that slot.
function I.HasBuiltInGear(ent, slot)
    local m = IsValid(ent) and ent:GetModel()
    local e = m and B[string.lower(m)]
    local h = e and e[slot]
    if h == true then return true end
    if istable(h) then
        for bg, values in pairs(h) do
            if values[ent:GetBodygroup(bg)] then return true end
        end
    end
    return false
end

function I.ModelGearOf(ent)
    local m = IsValid(ent) and ent:GetModel()
    return m and G[string.lower(m)] or nil
end

-- True when the wearer's model shows this item itself (a bodygroup): its model isn't drawn.
function I.ShownByModel(ent, id)
    local d = I.ModelGearOf(ent)
    local cls = d and d.items and isnumber(id) and id > 1 and I.IDClass[id]
    return cls and d.items[cls] ~= nil or false
end

-- The bodygroups the gear worn now asks for: { [index] = value }, or nil for other playermodels.
-- own: the player's own choices ({ [bodygroup] = value }, sv_modelgear.lua), for the partial locks.
function I.ModelGearBodygroups(ent, own)
    local d = I.ModelGearOf(ent)
    if not d then return nil end
    local want = {}
    for k, v in pairs(d.lock or {}) do
        if istable(v) then
            local choice = own and own[k] or ent:GetBodygroup(k)
            if v[choice] ~= nil then want[k] = v[choice] end
        else
            want[k] = v
        end
    end
    for cat, bg in pairs(d.slots or {}) do
        if ent:GetNW2Int(cat, 1) > 1 then
            for k, v in pairs(bg) do want[k] = v end
        end
    end
    if d.items then
        for cat in pairs(I.GearCat) do
            local bg = d.items[I.IDClass[ent:GetNW2Int(cat, 1)] or ""]
            if bg then
                for k, v in pairs(bg) do want[k] = v end
            end
        end
    end
    return want
end
