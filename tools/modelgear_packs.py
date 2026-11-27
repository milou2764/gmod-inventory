"""Packs of gear taken from playermodel addons' bodygroups (modelgear_pack.py). One AIS extension each.

An item: its class (its ID: the extension author's name inside), slot, names (English, French), stats,
("lift": head gear raised on other playermodels, units of its own head: a cap its model wears over the
eyes) and what shows it worn: (start of the bodypart's name, start of the submodel's name) for each bodygroup
it sets; "stored": what shows it on the ground and in the inventory when that differs (webbing: its
straps are folded away, only the pouches show). The model's other bodygroups are set to their empty
choice when it is drawn alone.
"""
WW1 = [f"models/adamwassim/player/imperialcommunity/ww1/soldatfrancais{k}.mdl" for k in range(1, 7)]
P = "advinv_milou_ww1fr_"
VN = [f"models/namsoldiers/male_0{k}.mdl" for k in range(1, 10)] + ["models/namsoldiers/nick.mdl"]
V = "advinv_milou_vnus_"
RF = [f"models/leygun/rfarmy/soilder_rf_0{k}.mdl" for k in (2, 4, 5, 7, 8, 9)]
CW_UNION = [f"models/humans/civilwar/male_0{k}.mdl" for k in (1, 2, 3, 4)]
CW_CONFEDERATE = [f"models/humans/civilwar/male_0{k}.mdl" for k in (6, 7, 8, 9)]
PAVN = ["models/player/kerberos_risingstorm2.mdl", "models/player/kerberos_risingstorm3.mdl"]
VC = ["models/vietnam/humans/vc/gmod/vc_1.mdl", "models/vietnam/humans/vc/gmod/vc_5.mdl"]
PMC = [f"models/pmc/{m}.mdl" for m in ("pmc_1/pmc_pm", "pmc_2/acu_pm", "pmc_3/mpt_pm", "pmc_4/swat_pm", "pmc_5/sas_pm",
                                         "pmc_6/desert_pm", "pmc_7/super_pm", "pmc_8/snw_pm")]
M = "advinv_milou_pmc_"
DL = [f"models/dl/{m}_p.mdl" for m in ("gre1", "gre2", "gre3", "policeman1", "policeman2", "policeman3", "soldier1", "soldier2",
                                         "tear_soldier1", "tear_soldier2", "tear_soldier3")]
D = "advinv_milou_dlsec_"

PACKS = {
    "ww1_french": {
        "key": "ww1_french",
        "title": "WW1 French soldiers",
        "wid": "3433822040",
        "author": "milou2764 (gear of the playermodels by Adam / Imperial Community)",
        "category": ("Inventory: WW1 French gear", "Inventaire : équipement français 14-18"),
        "models": WW1,
        "items": [
            {"class": P + "adrian", "slot": "Helmet", "name": ("Adrian helmet, strap on the brim", "Casque Adrian, jugulaire sur la visière"), "mass": 14, "armor": 60,
             "show": [("Casque", "capote_francois_fra_adrian_helmet.smd")]},
            {"class": P + "adrian_2", "slot": "Helmet", "name": ("Adrian helmet, chin strap", "Casque Adrian, jugulaire"), "mass": 14, "armor": 60,
             "show": [("Casque", "capote_francois_fra_adrian_helmet2")]},
            {"class": P + "adrian_3", "slot": "Helmet", "name": ("Adrian helmet with mail veil", "Casque Adrian à camail"), "mass": 14, "armor": 60,
             "show": [("Casque", "capote_francois_fra_adrian_helmet3")]},
            {"class": P + "adrian_4", "slot": "Helmet", "name": ("Adrian helmet and M2 gas mask", "Casque Adrian et masque à gaz M2"), "mass": 14, "armor": 60,
             "show": [("Casque", "capote_francois_fra_adrian_helmet4")]},
            {"class": P + "kepi", "slot": "Helmet", "name": ("Kepi", "Képi"), "mass": 3,
             "show": [("Casque", "kepiww1")]},
            {"class": P + "beanie", "slot": "Helmet", "name": ("Beanie", "Bonnet"), "mass": 2,
             "show": [("Casque", "beanie")]},
            {"class": P + "assault_roll", "slot": "Rucksack", "name": ("Blanket roll", "Couverture roulée"), "mass": 25, "load": 30,
             "show": [("Sac a dos", "capote_francois_fra_assault_roll")]},
            {"class": P + "backpack", "slot": "Rucksack", "name": ("Backpack (as de carreau)", "Sac as de carreau"), "mass": 40, "load": 60,
             "show": [("Sac a dos", "capote_francois_fra_capote_backpack1")]},
            {"class": P + "berthier_webbing", "slot": "Vest", "name": ("Webbing, Berthier pouches", "Brêlage, cartouchières Berthier"),
             "mass": 12, "load": 15, "show": [("Straps", "straps"), ("Cartouchieres", "capote_francois_fra_berthier_pouches")],
             "stored": [("Cartouchieres", "capote_francois_fra_berthier_pouches")]},
            {"class": P + "chauchat_webbing", "slot": "Vest", "name": ("Webbing, Chauchat pouches", "Brêlage, cartouchières Chauchat"),
             "mass": 14, "load": 20, "show": [("Straps", "straps"), ("Cartouchieres", "chauchat")],
             "stored": [("Cartouchieres", "chauchat")]},
            {"class": P + "holster_belt", "slot": "Vest", "name": ("Pistol holster", "Étui de pistolet"),
             "mass": 6, "load": 5, "show": [("Cartouchieres", "holster.smd")]},
            {"class": P + "holster_berthier", "slot": "Vest", "name": ("Webbing, holster and Berthier pouch", "Brêlage, étui et cartouchière Berthier"),
             "mass": 12, "load": 15, "show": [("Straps", "straps"), ("Cartouchieres", "holsterberthier")],
             "stored": [("Cartouchieres", "holsterberthier")]},
        ],
    },
    # NPC ragdolls, not playermodels (citizen animations), on the ValveBiped skeleton: their gear is
    # worn on any playermodel like the WW1 gear. The pack's weapons and its separate props are not used.
    "vietnam_us": {
        "key": "vietnam_us",
        "title": "Vietnam era US soldiers",
        "wid": "146299217",
        "author": "milou2764 (gear of the Vietnam era US Soldiers ragdolls, Workshop 146299217)",
        "category": ("Inventory: Vietnam US gear", "Inventaire : équipement US Vietnam"),
        "models": VN,
        "items": [
            {"class": V + "m1_cover", "slot": "Helmet", "name": ("M1 helmet, Mitchell cover", "Casque M1, couvre-casque Mitchell"),
             "mass": 14, "armor": 60, "show": [("headwear", "helmet1"), ("helmetstrap", "helmstrap1")]},
            {"class": V + "m1_cover_ace", "slot": "Helmet", "name": ("M1 helmet, cover, ace of spades", "Casque M1, couvre-casque, as de pique"),
             "mass": 14, "armor": 60, "show": [("headwear", "helmet1"), ("helmetstrap", "helmstrap2"), ("helmet_writing5", "helmwriting5")]},
            {"class": V + "m1_born_to_kill", "slot": "Helmet", "name": ("M1 helmet, Born to Kill", "Casque M1, Born to Kill"),
             "mass": 14, "armor": 60, "show": [("headwear", "helmet1"), ("helmetstrap", "helmstrap3"),
                                               ("helmet_writing1", "helmwriting1"), ("helmet_writing4", "helmwriting4")]},
            {"class": V + "m1", "slot": "Helmet", "name": ("M1 helmet", "Casque M1"), "mass": 14, "armor": 60,
             "show": [("headwear", "helmet2")]},
            {"class": V + "boonie", "slot": "Helmet", "name": ("Boonie hat", "Chapeau de brousse"), "mass": 2,
             "show": [("headwear", "booniehat")]},
            {"class": V + "tropical_rucksack", "slot": "Rucksack", "name": ("Tropical rucksack", "Sac tropical"), "mass": 25, "load": 40,
             "show": [("back", "back_rucksack2")]},
            {"class": V + "frame_rucksack", "slot": "Rucksack", "name": ("Rucksack on frame", "Sac à dos à armature"), "mass": 35, "load": 60,
             "show": [("back", "back_rucksack1")]},
            {"class": V + "radio", "slot": "Rucksack", "name": ("PRC-25 radio", "Radio PRC-25"), "mass": 40, "load": 5,
             "show": [("back", "back_radio")]},
            {"class": V + "web_gear", "slot": "Vest", "name": ("M1956 web gear", "Brêlage M1956"), "mass": 12, "load": 20,
             "show": [("suspenders", "suspenders"), ("gear", "gearsetup1"), ("buttpack", "buttpack"), ("compass_pouch", "compasspouch")],
             "stored": [("gear", "gearsetup1"), ("buttpack", "buttpack")]},
            {"class": V + "web_gear_2", "slot": "Vest", "name": ("M1956 web gear, more pouches", "Brêlage M1956, plus de poches"), "mass": 14, "load": 25,
             "show": [("suspenders", "suspenders"), ("gear", "gearsetup2"), ("buttpack", "buttpack"), ("compass_pouch", "compasspouch")],
             "stored": [("gear", "gearsetup2"), ("buttpack", "buttpack")]},
            {"class": V + "web_gear_bandolier", "slot": "Vest", "name": ("Web gear and bandolier", "Brêlage et cartouchière bandoulière"),
             "mass": 14, "load": 25, "show": [("suspenders", "suspenders"), ("gear", "gearsetup1"), ("buttpack", "buttpack"),
                                              ("compass_pouch", "compasspouch"), ("bandolier", "bandolier")],
             "stored": [("gear", "gearsetup1"), ("buttpack", "buttpack")]},
            {"class": V + "web_gear_m60_belt", "slot": "Vest", "name": ("Web gear and M60 ammunition belt", "Brêlage et bande de munitions M60"),
             "mass": 16, "load": 25, "show": [("suspenders", "suspenders"), ("gear", "gearsetup2"), ("buttpack", "buttpack"),
                                              ("compass_pouch", "compasspouch"), ("bandolier", "mg_belt")],
             "stored": [("gear", "gearsetup2"), ("buttpack", "buttpack")]},
        ],
    },    "rf_army": {
        "key": "rf_army",
        "title": "Russian Army RF soldiers",
        "wid": "2764717646",
        "author": "milou2764 (gear of the Russian Army | RF Soldier playermodels, Workshop 2764717646)",
        "category": ("Inventory: Russian Army gear", "Inventaire : équipement armée russe"),
        "models": RF,
        "items": [
            {"class": "advinv_milou_rfarmy_6b47", "slot": "Helmet", "name": ("6B47 helmet, cover and goggles", "Casque 6B47, couvre-casque et lunettes"),
             "mass": 20, "armor": 80, "show": [("helmet", "helmet_new_mask")]},
            {"class": "advinv_milou_rfarmy_plate_carrier", "slot": "Vest", "name": ("Plate carrier", "Gilet porte-plaques"),
             "mass": 60, "load": 20, "armor": 100, "show": [("vest", "carrier_vest")]},
        ],
    },
    # one pack per side: each kepi is drawn with a soldier of its own side (one model per pack)
    "civilwar_union": {
        "key": "civilwar_union",
        "title": "Civil War soldiers (Union)",
        "wid": "3614216336",
        "author": "milou2764 (gear of the Civil War Soldiers playermodels, ported from Fallout 76)",
        "category": ("Inventory: Civil War gear", "Inventaire : équipement guerre de Sécession"),
        "models": CW_UNION,
        "items": [
            {"class": "advinv_milou_cw_union_kepi", "slot": "Helmet", "name": ("Union kepi", "Képi de l'Union"), "mass": 3, "lift": 0.9,
             "show": [("hat", "union_hat")]},
        ],
    },
    "civilwar_confederate": {
        "key": "civilwar_confederate",
        "title": "Civil War soldiers (Confederate)",
        "wid": "3614216336",
        "author": "milou2764 (gear of the Civil War Soldiers playermodels, ported from Fallout 76)",
        "category": ("Inventory: Civil War gear", "Inventaire : équipement guerre de Sécession"),
        "models": CW_CONFEDERATE,
        "items": [
            {"class": "advinv_milou_cw_confederate_kepi", "slot": "Helmet", "name": ("Confederate kepi", "Képi confédéré"), "mass": 3, "lift": 0.9,
             "show": [("hat", "confederate_hat")]},
        ],
    },    # RS2: Forces of the East: the PAVN soldiers and the Viet Minh / Vietcong, one pack each (one model each)
    "rs2_pavn": {
        "key": "rs2_pavn",
        "title": "RS2: Forces of the East (PAVN)",
        "wid": "2944903873",
        "author": "milou2764 (gear of the RS2: Forces of the East playermodels)",
        "category": ("Inventory: PAVN and Vietcong gear", "Inventaire : équipement APVN et Viêt-cong"),
        "models": PAVN,
        "items": [
            {"class": "advinv_milou_pavn_pith_helmet", "slot": "Helmet", "name": ("PAVN pith helmet", "Casque colonial de l'APVN"), "mass": 5,
             "show": [("Headgear_Pith02", "headgear_pith02")]},
            {"class": "advinv_milou_pavn_chest_rig", "slot": "Vest", "name": ("AK chest rig", "Porte-chargeurs AK"), "mass": 8, "load": 15, "stored_cut": 0.42,
             "show": [("AK_carrier_NVA", "ak_carrier_nva")]},
            {"class": "advinv_milou_pavn_chest_rig_grenades", "slot": "Vest", "name": ("AK chest rig and grenade pouch", "Porte-chargeurs AK et grenades"),
             "mass": 11, "load": 18, "stored_cut": 0.42, "show": [("AK_carrier_NVA", "ak_carrier_nva"), ("Grenadepouch01", "grenadepouch01"),
                                              ("Grenadepouch01_g01", "grenadepouch01_g01"), ("Grenadepouch01_g02", "grenadepouch01_g02")]},
            {"class": "advinv_milou_pavn_backpack", "slot": "Rucksack", "name": ("PAVN backpack", "Sac de l'APVN"), "mass": 20, "load": 40, "stored_cut": 0.62, "drop": 3.0,
             "show": [("Backpack_NVA", "backpack_nva")]},
        ],
    },
    "rs2_vc": {
        "key": "rs2_vc",
        "title": "RS2: Forces of the East (Viet Minh)",
        "wid": "2944903873",
        "author": "milou2764 (gear of the RS2: Forces of the East playermodels)",
        "category": ("Inventory: PAVN and Vietcong gear", "Inventaire : équipement APVN et Viêt-cong"),
        "models": VC,
        "items": [
            {"class": "advinv_milou_vc_bush_hat", "slot": "Helmet", "name": ("Black bush hat", "Chapeau de brousse noir"), "mass": 2,
             "show": [("Headgear", "vn_headgear_hat")]},
            {"class": "advinv_milou_vc_pith_helmet", "slot": "Helmet", "name": ("Pith helmet", "Casque colonial"), "mass": 5,
             "show": [("Headgear", "vn_headgear_helmet.smd")]},
            {"class": "advinv_milou_vc_pith_helmet_cover", "slot": "Helmet", "name": ("Pith helmet, black cloth cover", "Casque colonial, couvre-casque noir"), "mass": 5,
             "show": [("Headgear", "vn_headgear_helmet2")]},
            {"class": "advinv_milou_vc_non_la", "slot": "Helmet", "name": ("Conical hat (nón lá)", "Chapeau conique (nón lá)"), "mass": 1,
             "show": [("Headgear", "vn_headgear_nonla")]},
        ],
    },    # PMC Pack Redux: their plate carrier is part of the body, the chest pouches go on it (not items)
    "pmc_redux": {
        "key": "pmc_redux",
        "title": "PMC Pack Redux",
        "wid": "1769231405",
        "author": "milou2764 (gear of the PMC Pack Redux playermodels)",
        "category": ("Inventory: PMC gear", "Inventaire : équipement PMC"),
        "models": PMC,
        "items": [
            {"class": M + "beret", "slot": "Helmet", "name": ("Black beret", "Béret noir"), "mass": 1, "show": [("head", "pmc_beret")]},
            {"class": M + "cap", "slot": "Helmet", "name": ("Cap", "Casquette"), "mass": 1, "show": [("head", "pmc_cap")]},
            {"class": M + "beanie", "slot": "Helmet", "name": ("Black beanie", "Bonnet noir"), "mass": 1, "show": [("head", "pmc_beanie")]},
            {"class": M + "mich", "slot": "Helmet", "name": ("Tan MICH helmet", "Casque MICH beige"), "mass": 14, "armor": 70,
             "show": [("head", "pmc_helmet_01")]},
            {"class": M + "black_helmet", "slot": "Helmet", "name": ("Black helmet with ear defenders", "Casque noir avec casque antibruit"), "mass": 15, "armor": 70,
             "show": [("head", "pmc_helmet_02_no_goggles")]},
            {"class": M + "black_helmet_goggles", "slot": "Helmet", "name": ("Black helmet, goggles up", "Casque noir, lunettes relevées"), "mass": 16, "armor": 70,
             "show": [("head", "pmc_helmet_02_goggles_up")]},
            {"class": M + "black_helmet_goggles_down", "slot": "Helmet", "name": ("Black helmet, goggles down", "Casque noir, lunettes baissées"), "mass": 16, "armor": 70,
             "show": [("head", "pmc_helmet_02_goggles_down")]},
            {"class": M + "cover_helmet", "slot": "Helmet", "name": ("Helmet, desert cover", "Casque, couvre-casque désert"), "mass": 14, "armor": 70,
             "show": [("head", "pmc_helmet_03_no_goggles")]},
            {"class": M + "cover_helmet_goggles", "slot": "Helmet", "name": ("Helmet, desert cover and goggles", "Casque, couvre-casque désert et lunettes"), "mass": 15, "armor": 70,
             "show": [("head", "pmc_helmet_03_goggles_up")]},
            {"class": M + "visor_helmet", "slot": "Helmet", "name": ("Helmet with visor, raised", "Casque à visière relevée"), "mass": 18, "armor": 75,
             "show": [("head", "pmc_helmet_03_no_goggles"), ("visor", "pmc_helmet_03_visor_up")]},
            {"class": M + "visor_helmet_down", "slot": "Helmet", "name": ("Helmet with visor, lowered", "Casque à visière baissée"), "mass": 18, "armor": 80,
             "show": [("head", "pmc_helmet_03_no_goggles"), ("visor", "pmc_helmet_03_visor_down")]},
            {"class": M + "gasmask", "slot": "Gasmask", "name": ("Gas mask", "Masque à gaz"), "mass": 6, "show": [("face", "pmc_gasmask_01.smd")]},
            {"class": M + "gasmask_black", "slot": "Gasmask", "name": ("Black gas mask", "Masque à gaz noir"), "mass": 6, "show": [("face", "pmc_gasmask_02")]},
            {"class": M + "nvg", "slot": "NVGs", "name": ("Night vision goggles", "Lunettes de vision nocturne"), "mass": 4, "show": [("face", "pmc_nightvision")]},
            {"class": M + "headset", "slot": "Radio", "name": ("Tactical headset", "Casque audio tactique"), "mass": 2, "show": [("headsets", "pmc_headset.smd")]},
            {"class": M + "assault_pack", "slot": "Rucksack", "name": ("Assault pack", "Sac d'assaut"), "mass": 12, "load": 25,
             "show": [("back_gear", "pmc_back_gear")], "stored": [("back_gear", "pmc_back_gear")]},
            {"class": M + "backpack", "slot": "Rucksack", "name": ("Tactical backpack", "Sac à dos tactique"), "mass": 30, "load": 55,
             "show": [("back_gear", "pmc_backpack")]},
            {"class": M + "belt_kit", "slot": "Vest", "name": ("Belt, magazine pouches", "Ceinturon, porte-chargeurs"), "mass": 5, "load": 12,
             "show": [("belt_gear", "pmc_belt_gear")], "stored": [("belt_gear", "pmc_belt_gear")]},
            {"class": M + "belt_kit_holster", "slot": "Vest", "name": ("Belt, pouches, holster and leg pouches", "Ceinturon, poches, étui et poches de cuisse"),
             "mass": 9, "load": 18, "show": [("belt_gear", "pmc_belt_pouches"), ("holster", "pmc_holster.smd"), ("leg_gear", "pmc_leg_gear")],
             "stored": [("belt_gear", "pmc_belt_pouches"), ("holster", "pmc_holster.smd"), ("leg_gear", "pmc_leg_gear")],
             "rigged": True},
        ],
    },
    # Dying Light Security forces (3551549411): face, head and eye gear on all eleven; the first T.E.A.R.
    # soldier's kit in a pack of its own (drawn with his model). The GRE and police "equipment" is a few
    # things clipped on a vest that is part of their body: not an item.
    "dl_security": {
        "key": "dl_security",
        "title": "Dying Light Security forces",
        "wid": "3551549411",
        "author": "milou2764 (gear of the Dying Light Security forces playermodels)",
        "category": ("Inventory: Dying Light gear", "Inventaire : équipement Dying Light"),
        "models": DL,
        "items": [
            {"class": D + "helmet", "slot": "Helmet", "name": ("Combat helmet", "Casque de combat"), "mass": 14, "armor": 60,
             "show": [("headgear", "helmet")]},
            {"class": D + "cap", "slot": "Helmet", "name": ("Black cap", "Casquette noire"), "mass": 1, "show": [("headgear", "cap")]},
            {"class": D + "gasmask", "slot": "Gasmask", "name": ("Gas mask", "Masque à gaz"), "mass": 6, "show": [("face", "gasmask")]},
            {"class": D + "respirator", "slot": "Gasmask", "name": ("Half-face respirator", "Demi-masque respiratoire"), "mass": 3,
             "show": [("face", "respirator")]},
            {"class": D + "mask", "slot": "Gasmask", "name": ("Cloth face mask and goggles", "Masque en tissu et lunettes"), "mass": 2,
             "show": [("face", "mask.smd")]},
            {"class": D + "mask_white", "slot": "Gasmask", "name": ("Metal half mask", "Demi-masque en métal"), "mass": 3, "show": [("face", "mask2")]},
            {"class": D + "balaclava", "slot": "Gasmask", "name": ("Black balaclava", "Cagoule noire"), "mass": 1, "show": [("face", "balaclava.smd")]},
            # (not "balaclava2": its mesh has a helmet over the balaclava, and on these soldiers it takes
            # the face bodygroup the masks use)
            {"class": D + "goggles", "slot": "NVGs", "name": ("Protective goggles", "Lunettes de protection"), "mass": 1, "show": [("goggles", "goggles")]},
        ],
    },
    "dl_tear": {
        "key": "dl_tear",
        "title": "Dying Light T.E.A.R. soldier",
        "wid": "3551549411",
        "author": "milou2764 (gear of the Dying Light Security forces playermodels)",
        "category": ("Inventory: Dying Light gear", "Inventaire : équipement Dying Light"),
        "models": [DL[8]],
        "items": [
            {"class": D + "tear_rig", "slot": "Vest", "name": ("T.E.A.R. chest rig and belts", "Brêlage et ceinturons T.E.A.R."), "mass": 10, "load": 25,
             "show": [("belt1", "belt1"), ("belt2", "belt2"), ("ammo1", "ammo1"), ("ammo2", "ammo2"), ("radio", "radio"), ("pouch1", "pouch1"),
                      ("pouch2", "pouch2"), ("pouch3", "pouch3"), ("pouch4", "pouch4"), ("pouch5", "pouch5")]},
            {"class": D + "tear_bag", "slot": "Rucksack", "name": ("T.E.A.R. shoulder bag", "Sacoche T.E.A.R."), "mass": 6, "load": 15,
             "show": [("bag", "bag")]},
        ],
    },
    # Escape From Tarkov PMC playermodels [Redux] (2568198284): six USEC and three BEAR operators, the same
    # gear bodyparts on all nine. What all of them have in one pack (drawn with the USEC operator); each
    # side's cap, and the BEAR-only PACA, in a pack of that side (a pack's items exist on all its models).
    # The armour choices are armour and a chest rig in one mesh: one item each.
    "eft_pmc": {
        "key": "eft_pmc",
        "bind_positions": True,  # (anim0.BIND_POSITIONS: the game ignores their first sequence's positions)
        "title": "Escape From Tarkov PMC",
        "wid": "2568198284",
        "author": "milou2764 (gear of the Escape From Tarkov PMC playermodels)",
        "category": ("Inventory: Escape From Tarkov PMC gear", "Inventaire : équipement PMC Escape From Tarkov"),
        "models": [f"models/player/eft/pmc/eft_usec/models/eft_usec_pm_{k}.mdl" for k in ("redux", "beltstaff", "hoody", "nightpatrol", "tier2", "tier3")]
                  + [f"models/player/eft/pmc/eft_bear/models/eft_bear_pm_{k}.mdl" for k in ("redux", "lynx", "summer")],
        "items": [
            {"class": "advinv_milou_eftpmc_mich", "slot": "Helmet", "name": ("MICH 2001 helmet (olive)", "Casque MICH 2001 (olive)"), "mass": 14, "armor": 70,
             "show": [("Headgear", "eft_mich")]},
            {"class": "advinv_milou_eftpmc_ulach", "slot": "Helmet", "name": ("ULACH IIIA helmet (olive)", "Casque ULACH IIIA (olive)"), "mass": 15, "armor": 80,
             "show": [("Headgear", "eft_ulach")]},
            {"class": "advinv_milou_eftpmc_fast_mt", "slot": "Helmet", "name": ("FAST MT helmet (black)", "Casque FAST MT (noir)"), "mass": 10, "armor": 70,
             "show": [("Headgear", "eft_fastmt")]},
            {"class": "advinv_milou_eftpmc_altyn", "slot": "Helmet", "name": ("Altyn helmet with face shield", "Casque Altyn à visière"), "mass": 30, "armor": 90,
             "show": [("Headgear", "eft_altyn")]},
            {"class": "advinv_milou_eftpmc_cold_fear", "slot": "Gasmask", "name": ("Cold Fear balaclava (grey)", "Cagoule Cold Fear (grise)"), "mass": 1,
             "show": [("Face Cover", "eft_coldmask")]},
            {"class": "advinv_milou_eftpmc_momex", "slot": "Gasmask", "name": ("Momex balaclava (black)", "Cagoule Momex (noire)"), "mass": 1,
             "show": [("Face Cover", "eft_momex")]},
            {"class": "advinv_milou_eftpmc_gp7", "slot": "Gasmask", "name": ("GP-7 gas mask", "Masque à gaz GP-7"), "mass": 6,
             "show": [("Face Cover", "eft_gasmask")]},
            {"class": "advinv_milou_eftpmc_comtac", "slot": "Radio", "name": ("ComTac 2 headset", "Casque audio ComTac 2"), "mass": 2,
             "show": [("Headset", "eft_comtacs")]},
            {"class": "advinv_milou_eftpmc_6b34", "slot": "NVGs", "name": ("6B34 anti-fragmentation glasses", "Lunettes anti-éclats 6B34"), "mass": 1,
             "show": [("Eyewear", "eft_6b34goggles")]},
            {"class": "advinv_milou_eftpmc_6b23", "slot": "Vest", "name": ("6B23-1 body armour and Triton chest harness", "Gilet pare-balles 6B23-1 et harnais Triton"),
             "mass": 45, "armor": 70, "load": 20, "show": [("Armour", "eft_6b23")]},
            {"class": "advinv_milou_eftpmc_m1", "slot": "Vest", "name": ("M1 armoured rig", "Gilet de combat blindé M1"), "mass": 40, "armor": 70, "load": 20,
             "show": [("Armour", "eft_m1")]},
            {"class": "advinv_milou_eftpmc_tactec", "slot": "Vest", "name": ("TacTec plate carrier", "Porte-plaques TacTec"), "mass": 45, "armor": 90, "load": 25,
             "show": [("Armour", "eft_tactec")]},
            {"class": "advinv_milou_eftpmc_hexgrid", "slot": "Vest", "name": ("Hexgrid plate carrier and Azimut chest harness", "Porte-plaques Hexgrid et harnais Azimut"),
             "mass": 50, "armor": 90, "load": 20, "show": [("Armour", "eft_hexgrid")]},
            {"class": "advinv_milou_eftpmc_slick", "slot": "Vest", "name": ("Slick plate carrier and BlackRock chest rig", "Porte-plaques Slick et porte-chargeurs BlackRock"),
             "mass": 55, "armor": 100, "load": 25, "show": [("Armour", "eft_slick")]},
            {"class": "advinv_milou_eftpmc_mbss", "slot": "Rucksack", "name": ("MBSS backpack", "Sac à dos MBSS"), "mass": 12, "load": 25,
             "show": [("Backpack", "eft_mbss")]},
            {"class": "advinv_milou_eftpmc_attack2", "slot": "Rucksack", "name": ("SSO Attack 2 raid backpack", "Sac de raid SSO Attack 2"), "mass": 30, "load": 60,
             "show": [("Backpack", "eft_attack2")]},
        ],
    },
    "eft_pmc_usec": {
        "key": "eft_pmc_usec",
        "bind_positions": True,  # (anim0.BIND_POSITIONS: the game ignores their first sequence's positions)
        "title": "Escape From Tarkov PMC (USEC)",
        "wid": "2568198284",
        "author": "milou2764 (gear of the Escape From Tarkov PMC playermodels)",
        "category": ("Inventory: Escape From Tarkov PMC gear", "Inventaire : équipement PMC Escape From Tarkov"),
        "models": [f"models/player/eft/pmc/eft_usec/models/eft_usec_pm_{k}.mdl" for k in ("redux", "beltstaff", "hoody", "nightpatrol", "tier2", "tier3")],
        "items": [
            {"class": "advinv_milou_eftpmc_cap_usec", "slot": "Helmet", "name": ("USEC cap", "Casquette USEC"), "mass": 1,
             "show": [("Headgear", "eft_capusec")]},
        ],
    },
    "eft_pmc_bear": {
        "key": "eft_pmc_bear",
        "bind_positions": True,  # (anim0.BIND_POSITIONS: the game ignores their first sequence's positions)
        "title": "Escape From Tarkov PMC (BEAR)",
        "wid": "2568198284",
        "author": "milou2764 (gear of the Escape From Tarkov PMC playermodels)",
        "category": ("Inventory: Escape From Tarkov PMC gear", "Inventaire : équipement PMC Escape From Tarkov"),
        "models": [f"models/player/eft/pmc/eft_bear/models/eft_bear_pm_{k}.mdl" for k in ("redux", "lynx", "summer")],
        "items": [
            {"class": "advinv_milou_eftpmc_cap_bear", "slot": "Helmet", "name": ("BEAR cap", "Casquette BEAR"), "mass": 1,
             "show": [("Headgear", "eft_capbear")]},
            {"class": "advinv_milou_eftpmc_paca", "slot": "Vest", "name": ("PACA soft armour and Bank Robber chest rig", "Gilet souple PACA et porte-chargeurs Bank Robber"),
             "mass": 25, "armor": 50, "load": 15, "show": [("Armour", "eft_paca")]},
        ],
    },
}
