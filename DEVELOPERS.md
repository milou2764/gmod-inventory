# Advanced Inventory System (AIS): developer guide

How to make an addon that works with the Advanced Inventory System: item packs (gear, weapons,
ammo), weapon bases, storage entities, character systems, and addons that read or change a
player's inventory. The player and server-owner documentation is `README.md` (`LISEZMOI.md` in
French); this guide only covers code.

- [Basics](#basics)
- [Quick start: an item pack](#quick-start-an-item-pack)
- [Item IDs](#item-ids)
- [Item fields](#item-fields)
- [Base classes and slots](#base-classes-and-slots)
- [Worn gear on the body](#worn-gear-on-the-body)
- [Weapons and carry modes](#weapons-and-carry-modes)
- [Ammunition](#ammunition)
- [Things that are not items: generic items](#things-that-are-not-items-generic-items)
- [Other weapon bases](#other-weapon-bases)
- [Storage entities](#storage-entities)
- [Using, crafting, loot, rarity, illegal items](#using-crafting-loot-rarity-illegal-items)
- [Character systems and saving](#character-systems-and-saving)
- [Server API](#server-api)
- [Hooks](#hooks)
- [Client side](#client-side)
- [Languages](#languages)
- [Settings and the admin menu](#settings-and-the-admin-menu)
- [Rules](#rules)
- [Tools](#tools)

## Basics

- Everything is in the global table **`AdvInv`** (written `I` inside the addon's own files).
  Folder `addons/advanced-inventory`, Lua in `lua/advinv/`, loaded in a fixed order by
  `lua/autorun/advinv_loader.lua`. Console commands, settings, network messages and entity classes
  start with `advinv_`; hooks with `AdvInv_`.
- **The server decides everything.** Clients send requests (one network message, `advinv_act`);
  the server checks distance, capacity, ownership and rights, then sends the new contents back.
  A request names an item by its place in a container and what it is (`AdvInv.ItemCheck(item)`,
  32 bits): if the list moved meanwhile, the server acts on that item where it is now, or refuses.
  Never change a player's inventory from the client, and on the server use the functions below
  rather than setting networked variables yourself.
- **An item** is a small table: `{ id = 42, r = 30, a = 100, m = 1, c = "class", x = "data" }`
  - `id`: the item's ID (its class, see [Item IDs](#item-ids));
  - `r`: rounds (ammo box, or the magazine of a weapon);
  - `a`: armour points left (helmets, vests);
  - `m`: carry mode of a long gun (index in `AdvInv.CARRY_MODES`);
  - `c`: class of a generic item (any weapon, whitelisted entity or ammo type, see below);
  - `x`: extra data of a weapon (its attachments, as a string).
- **Containers**: `"Uniform"` (pockets, always there), `"Vest"` and `"Rucksack"` (when the worn
  vest or backpack has a capacity), and `"Storage"` (crates, vehicle trunks, banks, bodies).
  Each has a capacity in points; every item has a mass in points (not slots).
- **Equipment slots**: `NVGs`, `Helmet`, `Gasmask`, `Radio`, `Rucksack`, `Vest`, `Uniform` (gear),
  `PrimaryWep`, `SecondaryWep`, `RocketLauncher` (weapons). `AdvInv.GearCat`, `AdvInv.WeaponCat`.
- Check that the AIS is installed before using it: `if AdvInv and AdvInv.Equip then ... end`
  (server), or require it in your addon's description.

## Quick start: an item pack

```
addons/my-gear/
  lua/autorun/my_gear.lua         -- registers the items (shared)
  lua/entities/my_helmet.lua      -- one entity per item
```

```lua
-- lua/autorun/my_gear.lua
AdvInv = AdvInv or {}
AdvInv.Items = AdvInv.Items or {}
AdvInv.Items["advinv_myname_helmet"] = true      -- the class name is the item's ID
AdvInv.Items["advinv_myname_backpack"] = true
```

```lua
-- lua/entities/my_helmet.lua
AddCSLuaFile()
ENT.Base = "advinv_base_helmet"
ENT.PrintName = AdvInv.T("Heavy helmet", "Casque lourd")       -- English / French
ENT.Category = AdvInv.T("Inventory: My gear", "Inventaire : mon équipement")
ENT.Spawnable = true
ENT.Model = "models/my_gear/helmet.mdl"
ENT.Mass = 15                       -- points
ENT.Armor = 150
ENT.Attach = { bone = "ValveBiped.Bip01_Head1", pos = Vector(1.5, 0.4, -1.5), ang = Angle(90, 10, 0), scale = 1 }
```

```lua
-- lua/entities/my_backpack.lua
AddCSLuaFile()
ENT.Base = "advinv_base_rucksack"
ENT.PrintName = AdvInv.T("Assault pack", "Sac d'assaut")
ENT.Category = AdvInv.T("Inventory: My gear", "Inventaire : mon équipement")
ENT.Spawnable = true
ENT.Model = "models/my_gear/backpack.mdl"   -- rigged to ValveBiped: bonemerged, no ENT.Attach
ENT.BodyFit = "back"                         -- shifted to each playermodel's build
ENT.MaxLoad = 120                            -- capacity of the "Rucksack" container
ENT.Mass = 25
ENT.BlocksCarryZones = { back = true }       -- no long gun across the back while worn
```

That is all: the items spawn from the spawn menu, are taken with Use, equipped, shown on the
player, saved, looted from bodies, searched, sold through DarkRP like the built-in ones. Entity
files are loaded after `lua/autorun`, so `AdvInv.T` exists when they run. The spawn menu shows the
model of an item that has no icon of its own (`materials/entities/<class>.png` or
`ENT.IconOverride`). `mrpi-military` (vests, backpack, headset) is a complete example.

## Item IDs

- An item's ID is its **entity class name**: unique whatever the addons installed (Garry's Mod
  takes one class per name). Put your name in it (`advinv_myname_helmet`) and **never rename** a
  class once a server uses it: the database saves class names.
- Register them in a **shared** file with the `AdvInv = AdvInv or {}` line, whatever the loading
  order of the addons: `AdvInv.Items[class] = true` (or `AdvInv.RegisterItem(class)`).
- Within a game session each item also has a number, for the network only: `AdvInv.ClassID[class]`,
  `AdvInv.IDClass[number]`, built at `InitPostEntity` (hook `AdvInv_ItemsInitialized`);
  `AdvInv.EntityTable(number)` works after it. The items registered by name are numbered by the
  server from 20000 and the clients get its numbers. 0 = no slot, 1 = empty slot.
- Older registration: `AdvInv.ClassID[class] = number` (2 to 19999) still registers an item and
  keeps that number in the session; saves made before class names (version 3) name items by those
  numbers and are read with them (`AdvInv.LegacyID`). Taken: 100-127 by the AIS (100 any weapon,
  103 any whitelisted entity, 125 any ammo type, the HL2 weapons, ammo and gear), 1000-1999 by the
  compatible Workshop addons (sh_compat.lua), 62-99 by `mrpi-military`.

## Item fields

Read from the item's entity table (`ENT.*`); all optional except `Model` and the slot.

| Field | For | Meaning |
|---|---|---|
| `PrintName` | all | name (use `AdvInv.T(en, fr)`; other languages fall back to English) |
| `Model`, `Skin` | all | world model, also used for icons and the preview |
| `Mass` | all | encombrement in points (default by base: weapons 80/20/100, others in `sh_containers.lua`) |
| `AdvInvCategory` | all | the slot it is worn in (see the bases) |
| `Rarity` | all | 1 common ... 5 legendary (frame colour, tooltip) |
| `Illegal` | all | `true`: shown in red when searched |
| `IconOverride` | all | spawn menu icon (else the model is shown) |
| `PhysBox` | all | `{ mins, maxs }` collision box on the ground when the model has no `.phy` |
| `Consumable` | all | `{ health = 25, armor = 0, sound = "..." }`: Use in the inventory consumes it |
| `ENT:OnUseItem(ply, item)` | all | custom use; return `true` when it was used up |
| `Armor` | worn | armour points when new |
| `ArmorHitgroups` | worn | `{ HITGROUP_HEAD, ... }` parts it protects (default: by slot, `AdvInv.ArmorZones`) |
| `Attach` | worn | `{ bone, pos, ang, scale }`: a prop following a bone (see below) |
| `BodyFit` | worn | `"vest"` / `"back"`: a rigged model shifted to each playermodel's build |
| `MaxLoad` | vest, backpack, uniform | capacity of its container (0/none: no container) |
| `BlocksCarryZones` | worn | `{ back = true, front = true, side = true, shoulder = true }`: zones taken from long guns |
| `BlocksCarryModes` | worn | `{ sling_down = true, ... }`: single carry modes taken |
| `BackDepth`, `BackHalfWidth` | backpack | how far it sticks out behind the back and to each side (else read from its model) |
| `WeaponClass` | weapons | the SWEP given when equipped |
| `Ammo`, `ClipSize`, `Rounds` | weapons | ammo type, magazine size, rounds when spawned (`ClipSize = -1`: no magazine) |
| `CarryModes`, `CarryDefault` | long guns | `{ "sling_up", "front_hang", ... }`, default mode |
| `CarryBackThickness` | vests | units it adds between the back and a slung weapon (default: measured by `tools/vest_back.py`, else `Config.CarryVestThickness` with armour, 0 without) |
| `AdaptAttach` | worn | `function(playermodel, attach)` -> the placement on a playermodel without a fit (else `Attach`) |
| `HideWhenWorn` | worn | `function(owner)` -> `true`: not drawn for now (drawn another way) |
| `WornColor` | worn | `function(owner)` -> a `Color` the worn model is tinted with |
| `CarryWide` | long guns | `true`: too wide to hang beside a backpack (a crossbow's bow): only in front while one is worn |
| `Ammo`, `Rounds`, `Capacity` | ammo boxes | ammo type, rounds when spawned, rounds when full |

## Base classes and slots

| Base | Slot (`AdvInvCategory`) | Notes |
|---|---|---|
| `advinv_base_helmet` | `Helmet` | `Armor` 100 |
| `advinv_base_gear` | set it yourself: `NVGs`, `Gasmask`, `Radio`, `Helmet`... | generic worn item |
| `advinv_base_vest` | `Vest` | armour, no pockets |
| `advinv_base_pocketvest` | `Vest` | armour and pockets: set `MaxLoad` |
| `advinv_base_rucksack` | `Rucksack` | set `MaxLoad`; blocks the back zone |
| `advinv_base_uniform` | `Uniform` | `MaxLoad` = pocket capacity (no uniform: `AdvInv.Config.DefaultUniformLoad`, 40); doesn't change the playermodel |
| `advinv_base_wep` | `PrimaryWep`, `SecondaryWep`, `RocketLauncher` | set `WeaponClass` |
| `advinv_base_ammobox` | none (stored only) | set `Ammo`, `Rounds`, `Capacity` |
| `advinv_base_entity` | none | anything that is only stored |

A vest or backpack keeps its contents when dropped, stored in a crate or taken from a body.

## Worn gear on the body

- **A prop** (any model): `ENT.Attach = { bone, pos, ang, scale }` follows the bone. Find the
  values with the console editor `advinv_attach_editor my_helmet` (preview, sliders, "Copy the
  code").
- **A rigged model** (ValveBiped skeleton): no `ENT.Attach`; it is bonemerged and bends with the
  body. `ENT.BodyFit = "vest"` or `"back"` shifts it to the build of each playermodel (measurements
  of the 87 default playermodels in `cl_bodyfit_data.lua`; add yours:
  `AdvInv.BodyFit.models["models/x.mdl"] = { front, back, shoulder }`, measured with
  `tools/bodyfit.py`).
- **Per playermodel**: `lua/advinv/cl_fits_data.lua` (generated by `tools/fit_items.py`) holds a
  position for every built-in item on every default playermodel. Items without an entry use their
  own `ENT.Attach`. Your addon can add entries the same way (`AdvInv.Fits`, see the file).
- A worn item parented to the local player is hidden in first person.
- Props are placed every frame from the bone (`AdvInv.GearPlacement(model, wearer)`) and lit from
  the wearer's centre, so a prop whose origin is far from its mesh is not drawn dark.
- A prop on the upper chest bone (`ValveBiped.Bip01_Spine4`: vests, pouches) follows the whole
  torso, between Spine1 and Spine4, so it stays on the chest when crouching or on a body. Set
  `AdvInv.Config.VestFollowsTorso = false` (client) to attach those to Spine4 only.
- Playermodel paths in fit tables (`AdvInv.Fits`, `AdvInv.BodyFit.models`, carry offsets) are
  matched in lowercase.
- Client: `AdvInv.mountedGear[userid][slot]` is the clientside model drawn on a player.
- **Playermodels with gear of their own** (bodygroups: a cap, a helmet, a vest, a backpack):
  `AdvInv.ModelGear["models/x.mdl"] = { lock = { [3] = 2 }, items = { my_helmet = { [3] = 0 } } }`
  (lowercase model, shared). `lock`: headgear, vest and backpack bodygroups held at that value (none)
  whatever the player picks, or `{ [gear value] = none value }` to lock only some values of a
  bodygroup mixing gear and faces; `items`: an item that is the model's own gear is shown by that
  bodygroup and its model isn't drawn; `slots = { Slot = { [bodygroup] = value } }`: other bodygroups
  set while a slot holds an item. The player's own choice comes back for what nothing asks for
  (`AdvInv.ApplyModelGear(ent)`, server: after every change of a worn item, on spawn and every
  second). Entries already in the table are kept, so define yours in a shared file. Measure that
  playermodel's fits with the "none" values: `tools/playermodel_bodygroups.txt`.
- **Gear in a playermodel's mesh** (no bodygroup to take it off): `AdvInv.GearBuiltIn["models/x.mdl"]
  = { Helmet = true, Vest = true, Rucksack = true }`; a slot can be `{ [bodygroup] = { [value] = true } }`
  when only some bodygroup choices have it, or `false` to allow it (shared, lowercase). `AdvInv.Equip`
  refuses those slots with the message of `AdvInv.GearBuiltInMessages` (`msg_headgear_on_headgear`,
  `msg_vest_on_vest`, `msg_backpack_on_backpack`); `AdvInv.GearBuiltInCheck(ply)` (server, every
  second) takes ours off a player who took such a playermodel or bodygroup (to the inventory, or the
  ground with its contents). `AdvInv.HasBuiltInGear(ent, slot)`. The fit tools give those slots' items
  no fit on those playermodels (`tools/builtin_gear.py` reads the table).

## Weapons and carry modes

A weapon item (`advinv_base_wep`) gives its `WeaponClass` when equipped and takes it away when
taken off; the magazine is kept in the item. Long guns are always carried on the body in one of
three modes (`sling_up` sling arms, `sling_down` back carry, `front_hang` front carry; `cross_body` and
the old `back_carry` were removed), one per body zone,
chosen by the player (right-click). Configure a weapon by class (shared):

```lua
AdvInv.CarryWeapons = AdvInv.CarryWeapons or {}
AdvInv.CarryWeapons["my_rifle"] = { default = "sling_up" }                          -- every mode
AdvInv.CarryWeapons["my_launcher"] = { modes = { "sling_up" }, default = "sling_up" }
AdvInv.CarryWeapons["my_crossbow"] = { default = "sling_up", wide = true } -- with a backpack: in front
```

A registered weapon item can set `ENT.CarryModes` / `ENT.CarryDefault` instead. A generic weapon
(a SWEP without an item of its own, see below) with no entry gets every mode if it is a primary
weapon, `sling_up` if it is a launcher. Without exact positions, a weapon is placed by
a template fitted to the shape of its world model (`AdvInv.WeaponGeometry`: its mesh as posed at
rest, checked against the model's hull, or its render box when the hull doesn't cover the mesh, as
on the Fallout 4 Institute rifle; a shape only taken from the hull is measured again a few times).
In the modes listed in `Config.CarryLongHang`
(the front carry), a gun longer than the one the templates were fitted with (`Config.CarryTemplateGun`,
the AR2) keeps its butt where that gun's butt is and turns toward the vertical, so it spans no wider:
a long rifle hangs down in front instead of sticking out past the shoulder. Exact positions per playermodel:
`tools/fit_carry.py` writes `cl_carry_data.lua`; tune in game with `advinv_carry_tune`
(`advinv_carry_cycle` cycles through the modes). Hooks: `CanChangeCarryMode`,
`OnCarryModeChanged`.

## Ammunition

The reserve of a weapon is the ammo boxes stored in the player's containers: reloading uses them
up (the least full first), unloading a weapon fills them. Never give reserve ammo with
`ply:GiveAmmo` for an inventory weapon: the next count sets the reserve back to the boxes. Use
`AdvInv.GiveRounds(ply, ammoType, rounds)` (server): it fills the started boxes, then new boxes,
then the ground (`AdvInv.GiveRounds(ply, ammoType, rounds, false, true)`: what doesn't fit is
returned instead of dropped). Worn gear keeps a state of an addon's (a string, `item.x`) while worn,
on a body and in saves: see the hooks `AdvInv_GearEquipped` / `AdvInv_GearTakenOff`.

- A registered ammo box: an item based on `advinv_base_ammobox`.
- Any other ammo type gets a **generic box** (ID 125, `c = ammo type`): sizes per type in
  `AdvInv.AmmoBoxSize[type]`, `AdvInv.AmmoBoxMass[type]`, `AdvInv.AmmoBoxModel[type]`.
- An ammo entity of another addon is taken with Use when it says its type and amount:
  `ENT.AmmoType = "5.56x45MM"` and `ENT.AmmoCount` (or `AmmoAmount`, `Amount`).
- Code that has to give reserve the game's way (an entity's own Use or Touch calling `GiveAmmo`):
  call `AdvInv.AllowAmmoGain(ply, ammoType)` just before; the gains of that type in the next two
  ticks become boxes. Any other reserve gain of a type the inventory manages is taken back at the
  next count. Code that turns its own gains into boxes itself (`AdvInv.GiveRounds` after comparing
  the reserve, like the ArcCW and CW 2.0 adapters) wraps the call in
  `AdvInv.BeginGainConversion(ply)` / `AdvInv.EndGainConversion(ply, { [ammoType] = true })`, so the
  same rounds are not made boxes twice.
- A weapon's ammunition and magazine size as a weapon table declares them: `AdvInv.SwepAmmo(swep)`,
  `AdvInv.SwepClipSize(swep)` (shared; `SWEP.Primary`, or ARC9's `SWEP.Ammo` / `SWEP.ClipSize`).
- Rounds in an underbarrel launcher (`Clip2`, ArcCW UBGL, CW 2.0's M203) are not kept in the
  item: they go into boxes when the weapon leaves its slot (`AdvInv.UnloadUnderbarrel(ply, wep)`),
  and a weapon the inventory gives starts with an empty launcher.

## Things that are not items: generic items

Any SWEP lying in the world becomes a **generic weapon** (ID 100, `c = class`): its slot is guessed
from its hold type (`HoldType`, `NormalHoldType` or ArcCW's `HoldtypeActive`) and its ammo (launcher:
rockets, missiles or warheads, or the RPG hold type with no magazine), `SWEP.Slot` for ARC9 and Sandstorm SWEPs weapons,
its mass from the slot. Tables
your addon can fill (shared):

```lua
AdvInv.WeaponCategory["my_knife"] = "SecondaryWep"     -- slot of a weapon class
AdvInv.WeaponBlacklist["my_tool"] = true               -- never an inventory item (tools, keys, hands)
AdvInv.PickupWhitelist["my_medkit"] = { name = "Medkit", model = "models/...", mass = 5 }
                                                       -- a world entity taken with Use (ID 103)
AdvInv.PickupConvert["item_ammo_smg1"] = "advinv_ammo_smg1"  -- becomes that registered item
AdvInv.Consumables["my_medkit"] = { health = 40 }      -- what using it does
```

A SWEP can also declare `SWEP.AdvInvCategory` and `SWEP.AdvInvMass`.

## Grenades

A grenade is not a slot weapon: it is one round of its ammunition type (a generic ammo item of
size 1). Register other grenade weapons (shared): `AdvInv.Grenades["my_grenade"] = "My Grenades"`
(its `Primary.Ammo`). The inventory keeps the items equal to the grenades (reserve + loaded): a
throw takes one away, ammo given by other code adds some, and Use puts the weapon in the hands.
Grenades a DarkRP job's loadout gives are job items (taken at death and at a job change, not
saved), and grenade items follow their weapon's DarkRP drop rules (`dropspawnedweapons`,
`DisallowDrop`, `restrictdrop`, `AdvInv_CanWeaponLeave`).

## Compatible Workshop addons (their models as items)

`tools/compat_packs.py` lists addons whose models become items when installed (fixed IDs
1000-1999, slot, orientation of the prop, stats). `tools/fit_compat.py` reads the extracted addons
(`MDL_EXTRA_DIRS`), fits every model on every default playermodel and writes
`lua/advinv/sh_compat_data.lua` and `cl_fits_compat.lua`; `tools/compat_sheets.py` renders them
to check. `sh_compat.lua` registers the items, spawnable only where the model is there. The addons'
files are never shipped.

## Gear from a playermodel's bodygroups (extensions)

A playermodel addon whose helmets, vests or backpacks are bodygroups can have them as items, in an
extension: a separate addon shipping **Lua only** (`addons/advinv-ext-ww1-french`,
`addons/advinv-ext-vietnam-us`). The pack's models need not be playermodels: NPC ragdolls on the
ValveBiped skeleton work too (the Vietnam soldiers); their gear is then only worn as fitted copies.
Each item is drawn with the playermodel's own model: its other bodygroups on their empty choice, the
parts that have none hidden by material (`materials/advinv/nodraw.vmt`). Nothing of the playermodel
addon is redistributed; without it the items aren't available (not spawnable, never given).

- On the pack's own playermodels the item is shown by the bodygroup itself (rigged for that body),
  and the bodygroups the pack's items use are locked to the pack's `blank` values there: their gear
  shows only while the item is worn (an `AdvInv.ModelGear` entry with its own `lock` wins; the locks of several packs of one model add up: the Dying Light soldier whose head gear is in one pack, his kit in another).
  Those bodygroups are locked (`ModelGear` `lock`): picking them in a menu does nothing, only the
  item worn shows them.
- On any other playermodel a copy follows the head or the torso, with a fit per playermodel (the
  extension's `fits`, merged into `AdvInv.Fits` on the client).
- On the ground: the gear alone, its physics its convex hull (`PhysHull`) around its centre
  (`ModelOrigin`: the entity's origin). A `stored` look may differ from the worn one (webbing: the
  straps folded away), and pieces with nothing between them are drawn pushed together (`pieces`:
  clip planes); `stored_cut` (a fraction of the item's height) keeps only what is below it on the
  ground (a chest rig's shoulder straps cut away).
- Slots: `Helmet`, `Vest`, `Rucksack`, and the head-worn `Gasmask`, `NVGs`, `Radio` (the headset),
  fitted by the skull like helmets. `lift` raises head gear on the other playermodels (units of its
  own head, scaled with the wearer's): the Civil War kepis, worn over the eyes on their own models,
  have their brim on the forehead elsewhere; `drop` lowers torso gear the same way (the PAVN
  backpack, which its own soldier wears low on the back). `rigged` bonemerges the item on its wearer instead of a
  rigid copy on a bone: each part follows its own bone (a drop-leg holster, leg pouches: the thighs),
  without a per-playermodel fit.
- Gear on a material the body also uses (the Vietnam soldiers' suspenders are painted on the
  uniform's texture): hiding the body would hide it. The pack marks those looks (`shared`), and the
  game reads their triangles from the installed model (`util.GetModelMeshes`: the item's bodygroups
  minus the gearless ones, on a hidden material) and draws them as a mesh where the model is drawn
  (worn, on the ground, in icons; `I.SharedPartsMesh`, `I.DrawSharedParts`). Nothing is shipped.

`tools/modelgear_pack.py <pack>` makes the extension's Lua from a pack in `tools/modelgear_packs.py`
(the playermodels, the bodygroup choices of each item, its stats; `stored` for a different look on
the ground). Bodyparts and submodels are named by the start of their name, else its end, else a part
of it (models of one pack may prefix them: `VN3_Headgear_Pith02`, `male_01_helmet1.smd`). The tool
measures each piece of gear in the playermodel's reference pose, transfers it to every
playermodel of a list (head gear by the skull; torso gear by the torso's girth at the height where
most of it is, both bodies measured at the same height between pelvis and neck, kept within 15 % of
the chest's ratio: a chest rig on a slim soldier's belly isn't sized by a citizen's chest) and writes
`lua/autorun/<name>.lua`. `--preview FILE` draws every item alone. The format is described at the top
of `lua/advinv/sh_modelgear_items.lua`; the item classes are their IDs, put your name in them.

## Fitting more playermodels

Options of an item in `tools/compat_packs.py` (the extra dict), for gear the measuring gets wrong:
`ref` (size, height of a helmet on male_07, chosen by eye with `tools/review_sheets.py`; other heads
by their head's size), `full` (a helmet enclosing the whole head), `outer` (width ratio, top gap:
helmets whose inside can't be measured), `min_ratio` (an open helmet at least that wide x the skull), `sizes` (min, max sizes),
`lift` (helmet raised, units), `size` (a vest's size on male_07, other bodies by their chest girth),
`tilt` (back item turned around the shoulders), `straps` (a pack modelled with its shoulder straps on: placed by its back panel, the straps wrap the shoulders). Orientations are read in the rest pose the tools use (`fit_items.rest_mesh`), which can be a quarter turn from the raw vertices. A playermodel without an "eyes" attachment (the Dying Light Security forces) gets the reference body's eyes frame, in the same place relative to its head bone, for fitting head gear. The review sheets (`tools/review_sheets.py`) show
every item on every playermodel of a list.

The fits are made offline by the tools, from the models' meshes (`tools/`, Python 3, numpy, PIL):
`fit_items.py` (built-in gear), `fit_compat.py` (compatible addons' gear), `bodyfit.py` +
`bodyfit_lua.py` (rigged vests and backpacks) and `fit_carry.py` (weapons on the body). Each takes
a list of playermodels; run them on the whole list, Garry's Mod's and the Workshop ones:

```
cat playermodels.txt playermodels_workshop.txt > all.txt
MDL_EXTRA_DIRS="<extracted addons, ; separated>" python fit_items.py all.txt   (then the others)
```

Only the numbers are written (`lua/advinv/cl_fits_*.lua`, `cl_bodyfit_data.lua`,
`cl_carry_data.lua`); the models are only read. Playermodel paths are matched in lowercase.

### Fit editor: approving every pair by hand

`tools/fit_editor/` (C, OpenGL) goes through every worn item on every playermodel, one pair at a
time, drawn the way the game places it (front, 3/4, side, back; the whole playermodel, arms
hideable). Adjust the size, the position (forward, up, left) and the tilt with the keys, the wheel
or the fields, then approve. An approved pair is final: it goes to `tools/fit_locks.txt`, into the
game's fit files at once (`python fit_locks.py apply`), the editor doesn't ask for it again (tick
"Show approved pairs too" to see it, Unlock to change it) and `fit_items.py` / `fit_compat.py` keep
it whatever their rules give. Playermodels whose head (or torso) and fit are the same are one pair.

Carried long guns are in it too: one item per weapon and carry mode ("AR2 - sling arms", class
`carry:weapon_ar2:sling_up` in `fit_locks.txt`), the weapon's world model on the mode's bone, without
worn gear. Their positions are shared by the playermodels of one
offset set (`cl_carry_data.lua`), so a set is one pair; an approval is written into that set and
`fit_carry.py` keeps it when it runs again. Weapons have no size: only their place and angles change.

**Weapon carry editor.** Double-click `tools/fit_editor/carry_editor.bat`: it finds the long guns
of your addons (below), computes their positions if some are new, and opens a window made for them:
the weapons in a list, the carry modes as buttons, the playermodel shown, sliders for forward/back,
up/down, left/right, lean, turn sideways and spin, the weapon drawn on the whole body (drag to turn
around, wheel to zoom). Save applies the move to every playermodel (each from where it has the
weapon; or only the one shown) and writes it into `cl_carry_data.lua` at once. Settings in
`tools/fit_editor/local.bat`: `ADVINV_PYTHON`, `MDL_EXTRA_DIRS` (other addons' unpacked models),
`ADVINV_WEAPON_DIRS` (more folders to look for weapons in).

Other addons' long guns (CW 2.0, TFA, a DarkRP shipment's AK...) can be set the same way, offline
(what the carry editor's launcher runs):

```
python carry_weapons.py scan [addon folders or .gma ...]   (default: the game's addons and Workshop downloads)
python fit_carry.py playermodels.txt                       (their positions on every playermodel)
tools/fit_editor/fit_editor.bat                            (one item per weapon and mode)
```

`carry_weapons.py` reads the weapon files as text (nothing is run) and writes `carry_weapons.txt`:
the long guns (held like one: ar2, smg, shotgun, crossbow, rpg hold types, or their
`AdvInvCategory`) whose world model it can read (put other addons' unpacked content in
`MDL_EXTRA_DIRS`). Edit the list freely. Their positions go into `cl_carry_data.lua` under their
weapon class; the game uses them instead of the mode's template (which stays for any weapon not
listed).

A world model is measured in its rest pose, the one its first animation gives (`anim0.py`, and the
game draws it so). Most guns lie there with the barrel along X and the top up. A model clearly longer
along Y than X (1.25 times) is taken as one whose animation turned it: the Sandstorm SWEPs, whose
world models made for the hand bone lie barrel along Y and upside down. `fit_carry.Weapon` and the
game's `AdvInv.WeaponGeometry` both turn such a model into that frame first (`g.turn`;
`AdvInv.GeomToModelAngles` / `ModelToGeomAngles` convert placements), and the carry editor spins it
around its longest axis.

Start it with `tools/fit_editor/fit_editor.bat`, with `ADVINV_PYTHON` (Python with numpy and
Pillow) and `MDL_EXTRA_DIRS` set in the environment or in `tools/fit_editor/local.bat` (not in
git). It runs `tools/fit_editor_export.py`, which reads the models once into
`%TEMP%\advinv_fit_editor` (about a minute the first time, then only new models), then opens
`fit_editor.exe`. Build it with `tools/fit_editor/build.sh` (MSYS2 UCRT64 gcc and zlib; no DLL
needed).

Batch use (reviewing many pairs at once): `--sheet ITEM OUT.bmp INDEX.txt [--tight] [--views 0,2,3]
[--size PX] [--cols N] [--which all|open|pending] [--adjust FILE]` draws every pair of an item on
the GPU in one picture (a fraction of a millisecond a pair); `--approve-item ITEM --adjust FILE --by
claude` approves them with the adjustments of FILE (`item<TAB>playermodel or *<TAB>size% forward up
left tilt`, or `skip`). Pairs approved that way are marked with who approved them: the user can
review them with "Review Claude's approvals" and change them; the user's own approvals stay final.

## Other weapon bases

- **Attachments** travel with the item in `x` (a string, at most 4096 characters). Built-in:
  ARC9 (preset code), TFA (selected attachments), Sandstorm SWEPs (attachments and skins), ArcCW (installed attachments), CW 2.0 (names; whoever equips the weapon is given
  them). Any base (server hooks):

```lua
hook.Add("AdvInv_WeaponData", "MyBase", function(wep)
    if wep.MyBase then return util.TableToJSON(wep:GetMyAttachments()) end
end)
hook.Add("AdvInv_ApplyWeaponData", "MyBase", function(wep, data)
    if wep.MyBase then wep:SetMyAttachments(util.JSONToTable(data)) return true end
end)
```

  Or add an adapter: `table.insert(AdvInv.WeaponDataAdapters, { match = fn(wep), save = fn(wep),
  load = fn(wep, data) })`. `load` runs 0.2 s after the weapon is given; a weapon lying in the
  world keeps its data in `ent.AdvInvExtra`.
- **A base's own "dropped weapon" entity**: tell the inventory what item it is (server), then it is
  taken with Use like a weapon:

```lua
AdvInv.EntityItemHandlers["mybase_dropped"] = function(ent)
    local item = AdvInv.ItemForWeaponClass(ent:GetWeaponClass(), ent.Clip or 0)
    if item then item.x = ent.AttachmentData end
    return item
end
```

- `lua/advinv/sv_cw2.lua` is a full example (its drop command, its dropped weapons, its ammo kits).
- `lua/advinv/sv_sandswep.lua`: a base that keeps spare magazines inside the weapon. Its magazine
  functions are wrapped as the base registers (`PreRegisterSWEP`): for a player's weapon the spare
  magazines mirror the reserve (the boxes), and what the base takes from them or puts back goes
  through the reserve (`RemoveAmmo`, `AdvInv.GiveRounds`).

## Storage entities

Any entity can have the "Storage" container: set `ENT.AdvInvStorage = true` (or
`AdvInv.StorageClasses[class] = true` for a class you don't own, like simfphys vehicles), give it a
capacity in points (`ENT.MaxLoad`), and open it with `AdvInv.StorageUse` on Use. The player sees its
contents next to his inventory and drags items in and out; distance and locks are checked.
`ENT:StorageTitle()` (client) sets the window title.

```lua
-- lua/entities/my_locker.lua
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Ammo locker"
ENT.Category = AdvInv.T("Inventory: Furniture", "Inventaire : mobilier")
ENT.Spawnable = true
ENT.Model = "models/props_c17/lockers001a.mdl"
ENT.AdvInvStorage = true
ENT.MaxLoad = 600

if SERVER then
    function ENT:Initialize()
        self:SetModel(self.Model)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
    end
    function ENT:Use(ply) AdvInv.StorageUse(self, ply) end -- opens it, or asks the lock code
end
```

Shared stores, personal stores, locks with codes, loot tables and permanence (saved with the map)
are settings of the built-in crate (`advinv_crate`, context menu > Storage settings); use it when
you need them.

## Using, crafting, loot, rarity, illegal items

```lua
AdvInv.AddRecipe({                                   -- shared; crafting is off by default (advinv_craft)
    id = "bandage", name = { en = "Bandage", fr = "Bandage" },
    needs = { { item = "advinv_cloth", count = 2 } }, -- item / entity / weapon / ammo
    gives = { entity = "item_healthvial" }, bench = false, time = 2,
})
AdvInv.LootTables["my_table"] = { rolls = { 1, 3 }, items = {
    { item = "advinv_ammo_ar2", weight = 5 }, { weapon = "weapon_shotgun", weight = 1 },
} }
AdvInv.ItemRarity["weapon_rpg"] = 4                  -- any class
AdvInv.IllegalItems["weapon_crowbar"] = true         -- any class
```

## Character systems and saving

On its own the AIS resets the inventory at every spawn and saves nothing. A character system (or
any addon that wants saved inventories) answers two hooks and calls Load / Save:

```lua
hook.Add("AdvInv_ShouldAutoInit", "MyRP", function(ply) return false end) -- no reset at spawn
hook.Add("AdvInv_OwnerID", "MyRP", function(ply) return ply:GetCharacterID() end) -- any string or number

AdvInv.CreateRecord(owner)        -- a new character
AdvInv.Load(ply, owner)           -- the player takes the character (gives the equipped items)
AdvInv.Save(ply, owner)           -- disconnect, shutdown, regularly
AdvInv.DeleteRecord(owner)        -- a deleted character
AdvInv.Record(owner)              -- the saved data without a player (character list previews)
AdvInv.RecordSlot(record, "Helmet") -- an item of a saved slot, or nil
AdvInv.GiveWeapons(ply)           -- gives back the slot weapons the player lacks (after StripWeapons)
```

Data: SQLite table `advinv_inventory (OwnerID TEXT PRIMARY KEY, Data TEXT)`, JSON
`{ v = 3, s = { slot = item }, c = { container = { items } } }`. Without an owner, nothing is
saved. When a player dies, his items go to his body and the emptied inventory is saved at once.
`mrp-characters` is a complete example (`lua/mrp_characters/sv_inventory_link.lua`).

## Server API

All on the server unless noted. `holder` is a player, a body or a storage entity.

| Function | |
|---|---|
| `AdvInv.Get(holder, cont)` | the item list of a container (edit in place, then `MarkDirty`) |
| `AdvInv.Set(holder, cont, items)` | replaces it (sends it) |
| `AdvInv.MarkDirty(holder, cont)` | sends a changed container (once per tick) |
| `AdvInv.Store(holder, item)` | puts an item where it fits (uniform, vest, backpack / storage); `true` or `false` |
| `AdvInv.CanFit(holder, cont, id, c)`, `Used`, `Free`, `MaxLoad` | capacity checks (points; 255 items at most per container, `AdvInv.MAX_ITEMS`) |
| `AdvInv.Equip(ply, item, contents)` | equips an item (slot must be free); `true` or `false, reason` |
| `AdvInv.TakeOff(ply, slot)` | empties a slot; returns the item (and a vest/backpack's contents) |
| `AdvInv.SpawnItem(item, pos, contents, count)` | puts an item in the world; returns the entity |
| `AdvInv.DropStack(item, n, pos)` | n identical items as one stack on the ground |
| `AdvInv.DropPos(ply)` | where a player drops things |
| `AdvInv.GiveRounds(ply, ammo, rounds)` | ammo into boxes (see Ammunition) |
| `AdvInv.MayLeaveItem(ply, item)` | may this item of his leave him (drop, crate, body)? -> true, or false and the reason (DarkRP drop rules, job items) |
| `AdvInv.ContentsMayLeave(ply, cat)` | the same for everything in his vest or backpack (`cat` "Vest" / "Rucksack") |
| `AdvInv.Use(ply, ent)` | takes an entity from the world as if the player pressed Use |
| `AdvInv.ItemFromEntity(ent)` | the item an entity would become, or nil |
| `AdvInv.ItemForWeaponClass(class, rounds)` | the item for a weapon class (registered or generic) |
| `AdvInv.ClassTable(class)`, `AdvInv.EntityTable(id)` | an item's table, inherited fields included (shared, cached: READ ONLY) |
| `AdvInv.ReleaseSlot(ply, slot)` | frees a weapon slot without taking the weapon (it left another way) |
| `AdvInv.GuardAmmo(ply)` | the next 2 ticks, reserve decreases don't use up ammo boxes (your code takes ammo away all at once) |
| `AdvInv.Info(id, c)` | cached facts: `name`, `cat`, `mass`, `maxLoad`, `isWeapon`, `weaponClass`, `isBox`, `ammo`... (shared) |
| `AdvInv.SlotRef(ent, slot)`, `AdvInv.SlotInfo(ent, slot)` | the item in a slot: id, class / its info (shared) |
| `AdvInv.CanAccess(ply, holder)` | may this player open it (distance, locks, rights) |
| `AdvInv.Tell(ply, text)` | a message in the player's inventory notice area |
| `AdvInv.Clear(ply)`, `AdvInv.SetDefaults(ply)` | empty everything / starting inventory |
| `AdvInv.IsBody(ent)`, `AdvInv.IsStorage(ent)` | (shared) |

Player helpers (shared, read only): `ply:AdvInvHas(slot)`, `ply:AdvInvGetID(slot)`,
`ply:AdvInvEntityTable(slot)`, `ply:AdvInvWeapon(slot)`, `ply:HasNVGs()`. Networked state: gear
slots `ply:GetNW2Int(slot)`, weapon slots `ply:GetNWInt(slot)` (+ `slot .. "Class"`,
`slot .. "Rounds"`, `slot .. "Carry"`), armour `ply:GetNWInt(slot .. "Armor")`. Read them, never set
them: use `Equip` / `TakeOff`.

## Hooks

| Hook | Realm | Arguments | Return |
|---|---|---|---|
| `AdvInv_ItemsInitialized` | shared | | after the ID tables are built |
| `AdvInv_OwnerID` | server | ply | owner of the inventory he carries (saving) |
| `AdvInv_ShouldAutoInit` | server | ply | `false`: no reset (first spawn, after a death that emptied him) |
| `AdvInv_CanPickup` | server | ply, ent | `false`: Use / the pickup key doesn't take it |
| `AdvInv_JobIsolation` | server | ply, oldTeam, newTeam | DarkRP job change: `false` keeps the inventory, `true` forgets it |
| `AdvInv_JobInventoryForgotten` | server | ply, oldTeam, newTeam | the inventory was forgotten (isolated job) |
| `AdvInv_CanWeaponLeave` | server | ply, class | `false`: the weapon can't be dropped or given to a crate / body |
| `AdvInv_StorageCodeFailed` | server | ply, storage, fails | every 3rd wrong code on a storage |
| `AdvInv_Changed` | client | holder, cont, entIndex | a container was received (holder can be NULL for an entity not known yet: use entIndex) |
| `AdvInv_CanOpen` | client | ply | `false`: the inventory doesn't open |
| `AdvInv_PanelCreated` | client | panel, target | adjust the inventory window |
| `AdvInv_UseItem` | server | ply, item | `false` to forbid using it |
| `AdvInv_DeathDrop` | server | ply | `false`: nothing stays on the body this time |
| `AdvInv_DeathBody` | server | ply, body | the body was made |
| `AdvInv_GearEquipped` | server | ply, cat, item | gear was put in its slot (`item.x`: the state kept with it) |
| `AdvInv_GearTakenOff` | server | ply, cat, item | gear is leaving its slot (still worn): write its state into `item.x` |
| `AdvInv_SlotsReset` | server | ply | the whole inventory is about to be emptied (a character loaded, a reset): what is worn is still in its slot |
| `AdvInv_WeaponData` | server | wep | attachments as a string |
| `AdvInv_ApplyWeaponData` | server | wep, data | `true` when applied |
| `CanSearchInventory` | shared | searcher, target | `false` to forbid, `true` to allow |
| `AdvInv_Searched` | server | searcher, target, found | a search ended |
| `AdvInv_Confiscated` | server | searcher, target, item | an item was taken in a search |
| `CanChangeCarryMode` | shared | ply, item, mode | `false` to forbid |
| `OnCarryModeChanged` | server | ply, item, mode, oldMode | |
| `AdvInv_CanCraft` | server | ply, recipe | `false` to forbid |
| `AdvInv_Crafted` | server | ply, recipe | |
| `AdvInv_AdminAction` | server | admin, action, target, text | log of the admin menu |
| `AdvInv_AdminMenu` | client | sheet, frame | add tabs to the admin menu |

## Client side

- `AdvInv.OpenInventory()` opens the player's inventory; `AdvInv.plyInvPanel` is the open window.
  In `AdvInv_PanelCreated(panel, target)`, `panel[slot].Model` is the clientside model shown in a
  gear slot (to change its bodygroups, for example).
- `AdvInv.Seen[entIndex][cont]`: the last contents received for a holder.
- Panels you can reuse: `AdvInvAdjustableModelPanel` (character preview, rotate with the mouse;
  `advinvAutoFit = true` keeps the whole model in frame), `AdvInvBinder` (a key binder),
  `AdvInvWeaponIcon`, `AdvInvSpawnIcon`. Fonts: `AdvInvTitle`, `AdvInvText`, `AdvInvSmall`,
  `AdvInvCount`. `AdvInv.S(px)` scales a 1920x1080 size to the screen.
- Client settings: `advinv_theme` (dark, light, military), `advinv_hover_text`.

## Languages

`AdvInv.L(key, ...)` (text by key, `string.format` arguments) and `AdvInv.T(en, fr)` (inline pair,
for names). The server picks the language for everyone (`advinv_language`). Your addon can add
strings or a whole language (shared); missing keys fall back to English:

```lua
AdvInv.Lang.en.my_message = "Your helmet is cracked"
AdvInv.Lang.fr.my_message = "Votre casque est fendu"
AdvInv.Lang.it = AdvInv.Lang.it or {}               -- a new language: advinv_language it
```

## Settings and the admin menu

Show your server setting in the admin menu (Settings tab), with its label in `AdvInv.Lang`:

```lua
CreateConVar("my_addon_option", "1", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "...", 0, 1)  -- server
AdvInv.AddAdminSetting("my_addon_option", "bool")    -- shared; "int"/"float" take min, max
AdvInv.Lang.en.set_my_addon_option = "My option"
```

Who is an admin: the CAMI privilege `Advanced Inventory System - Admin` (superadmins by default).

## Rules

- IDs: 2-127, unique, never changed.
- Server side only for changes; go through the API, then `MarkDirty`.
- No `ply:GiveAmmo` for inventory ammo: `AdvInv.GiveRounds`.
- No `ply:Give` for an inventory weapon: `AdvInv.Equip(ply, item)` (or `GiveWeapons`).
- A weapon or entity you give by code (`ply:Give`) stays outside the inventory, on purpose
  (loadouts, tools). DarkRP job weapons become inventory weapons only with
  `advinv_darkrp_loadout_to_inventory 1`.
- Test under the gamemode your server runs (DarkRP behaves differently from Sandbox).

## Tools

Developer scripts in `tools/` (not in the `.gma`, Python 3 with numpy and Pillow; they read the
game's models from its VPK files):

| Script | |
|---|---|
| `fit_items.py` | fits every worn item to every default playermodel (`cl_fits_data.lua`) |
| `fit_editor/` (C), `fit_editor_export.py`, `fit_locks.py` | the fit editor: every item on every playermodel approved by hand (`fit_locks.txt`) |
| `fit_carry.py` | carry mode positions of the long guns (`cl_carry_data.lua`) |
| `carry_sheets.py`, `fit_sheets.py` | contact sheets to check them |
| `mount_check.py` | renders worn items on playermodels, without the game |
| `bodyfit.py`, `bodyfit_lua.py` | torso measurements of playermodels (`cl_bodyfit_data.lua`) |
| `weapon_check.py`, `mdl_render.py`, `studio.py`, `vpk.py`, `anim0.py`, `refbody.py` | model reading and rendering |
| `vest_back.py` | how thick each compatible vest is on the back, where slung weapons rest (`cl_vest_back.lua`) |
| `workshop.py` | Workshop items through Garry's Mod's Steamworks DLL: animated (GIF) icon, description, screenshots, required items, visibility (what `gmpublish` can't do) |
| `shots/gear_gif.lua`, `shots/make_gif.py` | frames and GIF of the animated Workshop icon (a playermodel switching gear) |

In game: `advinv_attach_editor` (worn item positions), `advinv_carry_tune` / `advinv_carry_cycle`
(carry positions), `advinv_admin` (admin menu). Tests: `tests/README.md`.
