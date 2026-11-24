"""Workshop addons the inventory is compatible with (dev data, not in the .gma).

Their models are NOT part of the inventory: when a server (and its players) have one of these
addons installed, its models become inventory items. fit_compat.py reads this table, fits every
model on every default playermodel and writes lua/advinv/sh_compat_data.lua and cl_fits_compat.lua.

IDs are saved in databases: NEVER change or reuse one. New models take new IDs (1000-1999).

Item: (id, model, kind, orientation, english name, french name, extra stats)
  kind: "helmet" (Helmet slot, on the head), "back" (Rucksack slot, on the back),
        "vest" (Vest slot, around the torso)
  orientation (the prop's own axes, as seen on the tools' contact sheets):
        "x_front" front +X, up +Z;  "y_front" front +Y, up +Z;  "-y_front" front -Y, up +Z;
        "x_out" (backpacks) outer face +X, up +Z, the side against the body -X;
        "auto" round helmet: dome axis and straps found from the mesh
  extra "outer": (width ratio, top gap) for helmets whose inside can't be measured (visor, face parts
        inside): outer width = ratio x head width (the skull's, or the whole head's with "full"),
        outer top that gap above the head
  extra "min_ratio": open helmets fitted by their inside, but at least that ratio x the skull's width
        wide (outside): a helmet whose shape lets it perch small on the skull (the Adrian: 1.4,
        measured on the Adrian helmet modelled on the WW1 French playermodels, Workshop 3433822040)
  extra "tilt": back items turned around the shoulder axis before fitting (degrees)
  extra "lift": helmets raised by that many units after fitting (a shell deeper than the head, made to
        cover the eyes like the TF2 Soldier's)
  extra "sizes": (min, max) helmet sizes for this item (TF2 helmets are made for TF2's big heads)
  extra "size": vests: the size on the reference body (male_07), chosen by eye; other bodies get it
        times their chest girth / the reference's
  extra "ref": (size, height[, back]) of a helmet on male_07, chosen by eye on a grid of both (the
        height: units above "the inside of the dome on the top of the head"; back: units towards the
        back of the head, negative: forwards, off the forehead); other heads get them times
        their head's size / male_07's (the skull, or the whole head with "full")
  extra "full": the helmet encloses the whole head (face, ears, jaw): fitted to the whole head, not
        only to the skull
"""

PACKS = [
    {
        "key": "sw_imperial", "wid": 943349673, "title": "Imperial Helmet Props Star wars",
        "category": ("Inventory: Star Wars", "Inventaire : Star Wars"),
        "items": [
            (1000, "models/player/mewtwo/icn_helmet_prop.mdl", "helmet", "x_front", "Stormtrooper helmet", "Casque de stormtrooper", {"full": True, "armor": 50, "ref": (0.99, 0.75)}),
            (1001, "models/player/mewtwo/mew2_212_helm.mdl", "helmet", "x_front", "212th helmet", "Casque du 212e", {"full": True, "armor": 50, "ref": (0.96, 1.0)}),
            (1002, "models/player/mewtwo/mew2_boba_fett_helm.mdl", "helmet", "x_front", "Boba Fett helmet", "Casque de Boba Fett", {"full": True, "armor": 70, "ref": (0.97, 0.0)}),
            (1003, "models/player/mewtwo/mew2_death_helm.mdl", "helmet", "x_front", "Death trooper helmet", "Casque de death trooper", {"full": True, "armor": 60, "ref": (1.04, 1.0)}),
            (1004, "models/player/mewtwo/mew2_scout_helm.mdl", "helmet", "x_front", "Scout trooper helmet", "Casque de scout trooper", {"full": True, "armor": 40, "ref": (0.95, 0.5)}),
            (1005, "models/player/mewtwo/mew2_shadow_helm.mdl", "helmet", "x_front", "Shadow trooper helmet", "Casque de shadow trooper", {"full": True, "armor": 60, "ref": (1.22, 0.0)}),
            (1006, "models/player/mewtwo/mew2_shore_helm.mdl", "helmet", "x_front", "Shoretrooper helmet", "Casque de shoretrooper", {"full": True, "armor": 50, "ref": (1.04, 0.25)}),
            (1007, "models/player/mewtwo/mew2_vader_helm.mdl", "helmet", "x_front", "Darth Vader helmet", "Casque de Dark Vador", {"full": True, "armor": 80, "ref": (1.01, 0.25)}),
        ],
    },
    {
        "key": "sw_clone_windu", "wid": 973353552, "title": "[AN] Mace Windu's Clone Helmets",
        "category": ("Inventory: Star Wars", "Inventaire : Star Wars"),
        "items": [
            (1008, "models/gonzo/cgicloneheads/p1/p1.mdl", "helmet", "x_front", "Clone helmet (phase 1)", "Casque de clone (phase 1)", {"full": True, "armor": 50, "ref": (1.12, 1.5)}),
            (1009, "models/gonzo/cgicloneheads/p2/p2.mdl", "helmet", "x_front", "Clone helmet (phase 2)", "Casque de clone (phase 2)", {"full": True, "armor": 55, "ref": (1.12, 1.5)}),
        ],
    },
    {
        "key": "sw_rebel_pilot", "wid": 1268434165, "title": "[NGRP] Rebel Pilot Helmet Prop",
        "category": ("Inventory: Star Wars", "Inventaire : Star Wars"),
        "items": [
            (1010, "models/gonzo/rebelpilothelmet/rebelpilothelmet.mdl", "helmet", "-y_front", "Rebel pilot helmet", "Casque de pilote rebelle", {"armor": 30, "ref": (0.9, 1.0)}),
        ],
    },
    {
        "key": "tf2_bils", "wid": 242772309, "title": "TF2 Hex - Helmet of Victory",
        "category": ("Inventory: TF2", "Inventaire : TF2"),
        "items": [
            (1020, "models/player/items/demo/demo_bils.mdl", "helmet", "auto", "Helmet of Victory (Demoman)", "Casque de la victoire (Demoman)", {"armor": 60, "ref": (0.97, 0.0)}),
            (1021, "models/player/items/engineer/engineer_bils.mdl", "helmet", "auto", "Helmet of Victory (Engineer)", "Casque de la victoire (Engineer)", {"armor": 60, "ref": (0.92, 0.0)}),
            (1022, "models/player/items/heavy/heavy_bils.mdl", "helmet", "auto", "Helmet of Victory (Heavy)", "Casque de la victoire (Heavy)", {"armor": 60, "ref": (0.86, 0.0)}),
            (1023, "models/player/items/medic/medic_bils.mdl", "helmet", "auto", "Helmet of Victory (Medic)", "Casque de la victoire (Medic)", {"armor": 60, "ref": (0.97, 0.0)}),
            (1024, "models/player/items/pyro/pyro_bils.mdl", "helmet", "auto", "Helmet of Victory (Pyro)", "Casque de la victoire (Pyro)", {"armor": 60, "ref": (0.87, 0.0)}),
            (1025, "models/player/items/scout/scout_bils.mdl", "helmet", "auto", "Helmet of Victory (Scout)", "Casque de la victoire (Scout)", {"armor": 60, "ref": (0.99, 0.0)}),
            (1026, "models/player/items/sniper/sniper_bils.mdl", "helmet", "auto", "Helmet of Victory (Sniper)", "Casque de la victoire (Sniper)", {"armor": 60, "ref": (0.91, 0.0)}),
            (1027, "models/player/items/soldier/soldier_bils.mdl", "helmet", "auto", "Helmet of Victory (Soldier)", "Casque de la victoire (Soldier)", {"armor": 60, "ref": (0.76, 1.0)}),
            (1028, "models/player/items/spy/spy_bils.mdl", "helmet", "auto", "Helmet of Victory (Spy)", "Casque de la victoire (Spy)", {"armor": 60, "ref": (0.97, 0.0)}),
        ],
    },
    {
        "key": "tank_crew", "wid": 327527107, "title": "US & Soviet Tank crew helmets",
        "category": ("Inventory: Military", "Inventaire : militaire"),
        "items": [
            (1030, "models/kali/miscstuff/cvc_helmet.mdl", "helmet", "x_front", "CVC tank crew helmet", "Casque de tankiste CVC", {"armor": 30, "radio": True, "ref": (0.91, -1.0, -0.5)}),
            (1031, "models/kali/miscstuff/soviet_tanker_helmet.mdl", "helmet", "x_front", "Soviet tank crew helmet", "Casque de tankiste soviétique", {"armor": 20, "ref": (0.96, 0.0, 0.5)}),
        ],
    },
    {
        "key": "adrian", "wid": 3613961508, "title": "Amnesia: The Bunker/Rebirth \"Adrian helmet\"",
        "category": ("Inventory: Military", "Inventaire : militaire"),
        "items": [
            (1032, "models/amnesiathebunker/adrianhelmet/adrian_helmet.mdl", "helmet", "x_front", "Adrian helmet", "Casque Adrian", {"armor": 60, "min_ratio": 1.4}),
        ],
    },
    {
        "key": "dayz_police_vest", "wid": 1448797869, "title": "DayZ Police vest",
        "category": ("Inventory: Military", "Inventaire : militaire"),
        "items": [
            (1040, "models/dayz/vest_police.mdl", "vest", "y_front", "Police vest", "Gilet de police", {"armor": 80, "load": 30, "size": 1.05}),
        ],
    },
    {
        "key": "petruz_pmc", "wid": 3626263716, "title": "Petruz PMC Vests(Effect)",
        "category": ("Inventory: Military", "Inventaire : militaire"),
        "items": [
            (1041, "models/martha/armario/cartuchera.mdl", "vest", "x_front", "Chest rig", "Porte-chargeurs", {"armor": 0, "load": 90, "front": True, "size": 0.85}),
            (1042, "models/martha/armario/cartucherafem.mdl", "vest", "x_front", "Chest rig (women)", "Porte-chargeurs (femme)", {"armor": 0, "load": 90, "front": True, "size": 0.95}),
            (1043, "models/martha/armario/chalecofem.mdl", "vest", "x_front", "PMC plate carrier (women)", "Porte-plaques PMC (femme)", {"armor": 100, "load": 40, "size": 1.0}),
            (1044, "models/martha/armario/chalecopmc.mdl", "vest", "x_front", "PMC plate carrier", "Porte-plaques PMC", {"armor": 100, "load": 40, "size": 0.82}),
        ],
    },
    {
        "key": "hev_tactical_vest", "wid": 3838802156, "title": "Tactical Vest H.E.V Replacement",
        "category": ("Inventory: Military", "Inventaire : militaire"),
        # replaces a base game model: installed when its own material is there and the model is not
        # the base game's one (fit_compat.py writes the base model's size)
        "probe_material": "materials/models/humans/marines/body.vmt",
        "items": [
            (1045, "models/items/hevsuit.mdl", "vest", "x_front", "Tactical vest", "Gilet tactique", {"armor": 100, "load": 60, "size": 0.92}),
        ],
    },
    {
        "key": "fo3_custom", "wid": 891790188, "title": "Fallout 3 Custom Backpacks",
        "category": ("Inventory: Fallout 3", "Inventaire : Fallout 3"),
        "items": [
            (1050 + k, f"models/fallout 3/backpack_{k + 1}.mdl", "back", "x_out", f"Fallout 3 backpack {k + 1}",
             f"Sac à dos Fallout 3 n° {k + 1}", {}) for k in range(6)
        ],
    },
    {
        "key": "fo3_campish", "wid": 315810701, "title": "FO3 Backpacks",
        "category": ("Inventory: Fallout 3", "Inventaire : Fallout 3"),
        "items": [
            (1056, "models/fallout 3/campish_pack.mdl", "back", "x_out", "Camping frame pack", "Sac à armature de camping", {}),
        ],
    },
]

FO76 = [
    ("atx_atomicset_backpack", "Atomic Set"), ("atx_backpack_ammobag", "Ammo Bag"),
    ("atx_backpack_firstresponders", "First Responders"), ("atx_backpack_freestatesresistance", "Free States Resistance"),
    ("atx_backpack_heist", "Heist"), ("atx_backpack_mothman", "Mothman"), ("atx_backpack_neutronite", "Neutronite"),
    ("atx_backpack_pioneer", "Pioneer"), ("atx_backpack_rigrollup", "Rig Roll-up"), ("atx_backpack_settler_unique", "Settler"),
    ("atx_backpack_skippy", "Skippy"), ("atx_backpack_surplussack", "Surplus Sack"), ("atx_backpack_wanderer", "Wanderer"),
    ("atx_cultist_backpack", "Cultist"), ("atx_enclave_backpack", "Enclave"), ("atx_floor_walker_backpack", "Floor Walker"),
    ("atx_gravedigger_backpack", "Gravedigger"), ("atx_heirloombasket_backpack", "Heirloom Basket"),
    ("atx_wingclipperbackpack", "Wing Clipper"), ("backpack_01", "Small Pack 1"), ("backpack_03", "Small Pack 3"),
    ("backpack_04", "Small Pack 4"), ("backpack_05", "Small Pack 5"), ("backpack_atx_flame_thrower_tank", "Flamer Tank"),
    ("backpack_atx_super_mutant", "Super Mutant"), ("backpack_bomber", "Bomber"), ("backpack_bos_tactical", "BoS Tactical"),
    ("backpack_bottle", "Bottle"), ("backpack_cappy", "Cappy"), ("backpack_cultist_b", "Cultist B"),
    ("backpack_deepcavehunter", "Deep Cave Hunter"), ("backpack_freestates", "Free States"), ("backpack_halloween_coffin", "Coffin"),
    ("backpack_kd_inkwell", "Inkwell"), ("backpack_mrfuzzy", "Mr. Fuzzy"), ("backpack_packrat", "Pack Rat"),
    ("backpack_parachute", "Parachute"), ("backpack_postalservice", "Postal Service"), ("backpack_raider", "Raider"),
    ("backpack_raider_unique", "Raider (unique)"), ("backpack_responderheavydispatch", "Responder Heavy Dispatch"),
    ("backpack_safari_crocodile", "Safari Crocodile"), ("backpack_safari_gorilla", "Safari Gorilla"),
    ("backpack_space_explorer", "Space Explorer"), ("backpack_space_explorer_jangles", "Space Explorer (Jangles)"),
    ("backpack_thanksgiving_cornucopia", "Cornucopia"), ("backpack_union", "Union"), ("backpack_valorousalistair", "Alistair"),
    ("backpack_vault_survivor", "Vault Survivor"), ("backpack_westvirginia", "West Virginia"), ("backpack_winter_santa_bag", "Santa Bag"),
    ("backpack_winter_wrapped_present", "Wrapped Present"), ("oguashellbackpack", "Ogua Shell"), ("score_s13_backpack_camera", "Camera"),
]
# per backpack: "tilt" (degrees, around the shoulder axis, - = bottom towards the back): packs made
# for another body (the super mutant's rope bag hangs from a much bigger shoulder: the best compromise,
# its sack still hangs a little off a human back)
FO76_EXTRA = {"backpack_atx_super_mutant": {"tilt": -25}}
PACKS.append({
    "key": "fo76_backpacks", "wid": 3234192542, "title": "Fallout 76 - Backpacks",
    "category": ("Inventory: Fallout 76", "Inventaire : Fallout 76"),
    "items": [(1060 + k, f"models/vex/fallout76/backpacks/{f}.mdl", "back", "x_out", f"{n} backpack", f"Sac à dos {n}", FO76_EXTRA.get(f, {}))
              for k, (f, n) in enumerate(FO76)],
})


def all_items():
    for p in PACKS:
        for it in p["items"]:
            yield p, it


ids = [it[0] for _, it in all_items()]
assert len(ids) == len(set(ids)), "duplicate compat ID"
assert all(1000 <= i <= 1999 for i in ids)
