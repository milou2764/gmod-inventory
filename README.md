# Advanced Inventory System

Arma 3-style inventory for Garry's Mod: uniform, vest, backpack, helmet, NVGs, gas mask, radio
(headset) and three weapon slots. Containers have no number of slots but a **capacity**: every
item has a **mass**, so two pistol magazines don't take the room of two drum magazines (see
"Mass and capacity"). Worn gear is shown on the player. The inventory opens with the `I` key
(can be changed in Options > Advanced Inventory > Inventory).

Source code, issues and the developer guide (`DEVELOPERS.md`, to make addons compatible with
the inventory): https://github.com/milou2764/gmod-inventory

No required dependency. If ULX/ULib is installed, the gear of invisible players is hidden. If
simfphys is installed, vehicles work as trunks.

## Language

English by default; French, German, Spanish and Russian available. The server chooses for everyone, in `server.cfg`:

```
advinv_language en    // English
advinv_language fr    // French
```

Item names are read when the addon loads: after changing the language, restart the map. All
texts are in `lua/advinv/sh_lang.lua`; to add a language, add a table to
`AdvInv.Lang` (missing keys fall back to English).

## Mass and capacity

Like Arma 3's "mass", it is a number of points with no unit:

- every item declares `ENT.Mass`, every container `ENT.MaxLoad` (capacity);
- a container accepts an item as long as the sum of the masses stays within its capacity;
- player containers: the **uniform** (pockets), the **vest** (if it has pockets) and the
  **backpack**; crates and vehicle trunks have a "Storage" container.

| | Default values |
|---|---|
| Uniform | 40 without a "uniform" item (`AdvInv.Config.DefaultUniformLoad`), otherwise the uniform's `ENT.MaxLoad` |
| Crate / vehicle | 1000 / 500 (`Config.CrateLoad`, `Config.VehicleLoad`) |
| Ammo | 9 mm box 4, .357 3, SMG 8, shotgun 10, AR2 10, rocket 60; boxes of 100 rounds: 9×19 12, 5.56 20, 7.62 25, 12.7 50 |
| Weapons | pistol 20, .357 25, SMG 40, shotgun 70, AR2 80, crossbow 80, rocket launcher 120 |
| Gear | helmet 40, vest 80, backpack 30, NVGs 20, mask 15 to 20, headset 10 |

An item without `ENT.Mass` gets a value from its base class (ammo 8, helmet 40, vest 80,
backpack 30, primary weapon 80...). A backpack or vest from another addon that only declares the
old `ENT.Capacity` (number of slots) gets 16 points per slot.

**In the inventory (I key)**: every container has its "used / capacity" bar; click a container
to see what's inside. Drag an item onto a container or its tab (store it), onto a gear slot (equip
it), or outside the panels (drop it on the ground). Right-click: equip, store in..., drop.
Double-click: equip. Use key on an item on the ground: equip it if its slot is free, otherwise
store it (uniform, then vest, then backpack).

**Rules**: a backpack or vest dropped on the ground keeps its contents and gives them back when
worn again; a full backpack or vest can't be stored in another container (empty it or drop it);
a uniform can't be taken off if the pockets would overflow without it. The server checks every
action (distance, capacity, owner): a player can only touch their own inventory and the crates or
vehicles within reach.

**Ammo**: a weapon's reserve is the total of the ammo boxes stored in the uniform, vest and
backpack; reloading empties the boxes (least full first), and an empty box disappears. A box
picked up first tops up the started boxes of the same type. For a box, `ENT.Capacity` stays the
maximum number of rounds it holds.

**Stacks**: identical items in a container (same item, same ammo, same armor) show as one tile with
a count. Dragging moves one; right-click adds "Store all in..." and "Drop all" (the server stops when
there is no more room).

## Weapons

Equipped weapons that are not in the player's hands are shown on the body: long guns the way their
carry mode says (below), the sidearm in a holster on the right thigh. The side that rests on the
body is the weapon's thinner side, so a crossbow lies on its limbs. They are hidden while the
weapon is in the hands, when the player is dead or in a vehicle, and in your own first person. In the inventory, weapons are drawn from the side, horizontal, fitted to their box; long guns
take two cells in a container.

The exact shape of each weapon is measured on its mesh when it is first shown, so any weapon world
model works. Settings (client, `lua/advinv/cl_weapons.lua`): `Config.WeaponMounts` (bone,
point of the body surface and weapon angles for each slot), `Config.ShowMountedWeapons` (false to
turn it off), `Config.VestBackThickness`, `Config.WeaponMountGap`.

## Carry modes

Each long gun is carried one of these ways, chosen in the inventory: right-click the equipped
weapon, **Carry mode**. Everyone sees it on the player model.

| Mode | English | French | Where | Body zone |
|---|---|---|---|---|
| `sling_up` | Sling arms | Arme à la bretelle | from the right shoulder, muzzle up | shoulder |
| `sling_down` | Muzzle-down carry | Arme à la bretelle, canon en bas | from the right shoulder, muzzle down | shoulder |
| `cross_body` | Cross-body carry | Arme en bandoulière | sling across the torso, gun on the left hip | side |
| `back_carry` | Back carry | Arme à la grenadière | diagonally across the back | back |
| `front_hang` | Front carry / Hang | Arme en relâche avant | hanging in front of the chest | front |

A long gun is always carried one of these ways: it cannot be stowed out of sight.

Weapons: `weapon_smg1`, `weapon_ar2`, `weapon_shotgun`, `weapon_crossbow` (every mode) and
`weapon_rpg` (`back_carry`, `sling_up`). Defaults: sling arms, back carry for the launcher.

Rules, all decided by the server (a forged request is refused):

- one weapon per body zone: back + front is fine, two on the back is not;
- gear can take a zone: `ENT.BlocksCarryZones = { back = true }` on backpacks (the base
  `advinv_base_rucksack` has it); vests have `{ front = false }`, set `front = true` on a chest rig;
- when gear takes the zone of a carried weapon, the weapon moves to the first possible mode of
  `sling_up`, `cross_body`, `front_hang`, then its other modes (the other long gun moves too if
  that makes room) and the player is told. With `advinv_carry_refuse_gear 1` (server) the gear is
  refused instead;
- gear or a weapon that would leave a long gun with no possible mode is refused ("Your RPG would
  have no place left to be carried");
- checked again on spawn, inventory load, every equipment change and pickup. When two weapons want
  the same zone, the one already carried keeps it;
- the mode is saved with the weapon item: it follows the weapon into a container, onto the ground
  and back.

Unavailable modes are greyed out in the menu with the reason ("Back occupied by backpack").

Other weapons (data in `lua/advinv/sh_carry.lua`, shared):

```lua
AdvInv.CarryWeapons["my_rifle"] = { default = "sling_up" }   -- every mode
AdvInv.CarryWeapons["my_launcher"] = { modes = { "back_carry" }, default = "back_carry" }
```

or `ENT.CarryModes` / `ENT.CarryDefault` on the item. A weapon without computed offsets is placed by
the mode's template, fitted to its shape; tune it in game (below).

Hooks: `CanChangeCarryMode(ply, item, mode)` (return false to forbid; shared, it also greys out the
menu when defined on the client) and `OnCarryModeChanged(ply, item, mode, oldMode)` (server).
`item` is `{ id = item ID, cat = "PrimaryWep" or "RocketLauncher", m = current mode }`.

Drawing (client, `lua/advinv/cl_carry.lua`): offsets are stored per playermodel, weapon and
mode (`lua/advinv/cl_carry_data.lua`, below). A worn vest pushes the weapons out by
`Config.CarryVestThickness`, a backpack pushes the shoulder modes over it
(`Config.CarryOverPack`). When the launcher and the primary weapon are both on the back side and
cross, one goes over the other. A playermodel without the bone a mode uses does not show that
weapon. Models are removed on death, disconnect and Lua refresh.

### Offsets of every default playermodel

`tools/fit_carry.py` places each weapon in each mode on all 87 playermodels of the base game
(`tools/playermodels.txt`, from `player_manager`): the mode gives the direction and the side of the
body, then the weapon is lowered onto the body until its main body touches, without going into it
(arms left out, they move). Small parts sticking out sideways, like the AR2's side piece, may sink
in: counting them would hold the whole gun away from the body. Playermodels with the same
proportions share one offset set (`AdvInv.CarryAliases`, 49 sets): a model joins a set only if that set fits it without
clipping and within 1 unit of its own fit. A playermodel from another addon uses the `default`
set (male_07).

```
cd tools
python fit_carry.py                          # rewrites lua/advinv/cl_carry_data.lua
python carry_sheets.py out_dir               # one image per weapon and mode: every playermodel
python carry_sheets.py out_dir --one models/player/alyx.mdl     # every mode, 4 views
python carry_sheets.py out_dir --pairs models/player/alyx.mdl   # launcher + primary weapon
```

### Dev commands (client)

- `advinv_carry_tune`: a viewer with your playermodel, your long gun and its mode (or any other):
  sliders for the bone, position and angles. The change shows at once, in the viewer and in the
  world, on every playermodel of that set. **Print** writes the values to the console, **Save**
  writes every tuned value to `garrysmod/data/advinv_carry_tuned.json` (loaded again next time). To
  ship them, copy that file to `tools/carry_overrides.json` and run `python fit_carry.py`.
- `advinv_carry_cycle`: the same viewer going through every default playermodel x weapon x mode
  (1,914 views; Previous / Next, by model, or Auto with a delay), with a second weapon if wanted,
  and a choice of animation (idle, walk, run, holding a pistol...).

## Amounts and things on the ground

- Dragging a stack moves one item; **Shift + drag** moves the whole stack. Right-click a stack >
  **Store an amount in** / **Drop an amount...** to choose how many.
- Right-click an ammo box > **Split the box...**: the chosen rounds go into a new box.
- Identical items dropped together lie as one stack on the ground, and items dropped onto an
  identical stack join it. Taking a stack takes as many as there is room for; the rest stays.
- Looking at an item on the ground shows its name, how many there are, its rounds and mass, and
  the key that takes it (a dead player's body: his name and the key that searches it). Players
  who want more immersion turn this text off: Options > Advanced Inventory > Inventory: more,
  or the client setting `advinv_hover_text 0`.
- Items put on the ground by the inventory (dropped, swapped, a dead player's weapon...) disappear
  after `advinv_ground_item_time` seconds (server, default 600, 0: never; admin menu too).
  Picked up or stored, they no longer count; adding to a stack starts its time again. The item of
  a loot point stays until it is taken. Bodies have their own time (`advinv_death_loot_time`).

## Weapons and things lying around

Weapons lying in the world (dropped, spawned from the menu, placed by the map) are taken with the
Use key, not by walking over them: into their slot if it is free, else into the uniform, vest or
backpack. A weapon with its own registered item becomes that item (`weapon_ar2` -> the AR2 item); any
other weapon becomes a generic weapon item that keeps its class, its rounds and, for long guns,
gets every carry mode. Weapons given by code (job loadouts, `ply:Give`) are not touched, and a
weapon given from the spawn menu goes straight into the inventory.

The HL2 health kit, health vial and suit battery are taken with Use too (touching them no longer
uses them), and HL2 ammo becomes the matching ammo box.

```
advinv_pickup_weapons 1      // weapons lying around: taken with Use into the inventory
advinv_pickup_any_weapon 1   // weapons with no registered item become generic items
advinv_pickup_entities 1     // whitelisted entities and HL2 ammo: taken with Use
```

Lists other addons can fill (shared, `lua/advinv/sh_generic.lua`):

```lua
AdvInv.PickupWhitelist["my_medkit"] = { name = "Medkit", model = "models/...", mass = 6 }
AdvInv.WeaponBlacklist["my_tool"] = true          -- never turned into an item
AdvInv.PickupConvert["my_ammo_ent"] = "advinv_ammo_ar2"  -- becomes this registered item
AdvInv.WeaponCategory["my_rifle"] = "PrimaryWep"  -- force the slot of a weapon
```

The slot of a weapon with no registered item is guessed from its menu slot and hold type (pistols,
melee and grenades: sidearm; RPG: launcher; the rest: primary); `SWEP.AdvInvCategory` and
`SWEP.AdvInvMass` on a weapon override it. Physgun, toolgun, camera, hands and DarkRP's tools are
blacklisted.

## Other weapon bases (ARC9, TFA, CW 2.0, M9K...)

Weapons of any base become generic weapon items (see above). Their ammunition:

- Every ammunition type that has no registered ammo item gets a **generic ammo box** (30 rounds, mass 8):
  it is stored, feeds the reserve and is used up by reloading like the HL2 boxes, and receives the
  rounds of an unloaded weapon. Per type: `AdvInv.AmmoBoxSize[type]`, `AmmoBoxMass[type]`,
  `AmmoBoxModel[type]`. Admin menu > Items: give a box of any type.
- Ammunition entities of other bases are taken with Use into the inventory when they say their
  type and amount (`ENT.AmmoType` and `ENT.AmmoCount` / `AmmoAmount` / `Amount`).

Attachments: a weapon keeps its extra data through the inventory (taken off, stored, dropped,
equipped again, saved). Built-in, not tested on every version of these bases: ARC9 (preset code),
TFA (selected attachments), CW 2.0 (attachments). Any base: hooks (server)
`AdvInv_WeaponData(wep)` -> a string, and `AdvInv_ApplyWeaponData(wep, data)` -> true
when done. Weapons with different data don't stack.

**CW 2.0** (tested with the Workshop base, "Chuck's Weaponry 2.0", and its 15 weapons):

- rifles go to the primary slot (weight 80, all carry modes), pistols and grenades to the sidearm
  slot (weight 20); the slot comes from the weapon's menu slot and hold type
  (`AdvInv.WeaponCategory[class]` to change it);
- attachments stay on the weapon (taken off, stored, dropped, looted, saved). Whoever equips it
  is given its attachments, as CW 2.0 does for its own dropped weapons;
- `cw_dropweapon` on a weapon of the inventory drops it the inventory's way (out of its slot,
  attachments kept); CW 2.0's own dropped weapons are taken with Use into the inventory;
- the ammo of CW 2.0's ammo kits and crates goes into generic ammo boxes of its calibre.

## Using items, unloading weapons

Right-click an item of your inventory > **Use** (or double-click it): the HL2 health kit (+25
health), health vial (+10) and suit battery (+15 armour) are used up; nothing happens if you don't
need it. Right-click a weapon (stored or equipped) > **Unload**: the rounds of its magazine go back
into ammo boxes, the started ones first, then new boxes (on the ground if there is no room).

Other usable items (shared):

```lua
AdvInv.Consumables["my_ration"] = { health = 15, armor = 0, sound = "items/smallmedkit1.wav" }
ENT.Consumable = { health = 40 }                  -- on an registered item
function ENT:OnUseItem(ply, item) ... return true end  -- any effect; true = used up
```

Hook (server): `AdvInv_UseItem(ply, item)`, return false to forbid. A weapon can be unloaded
when its ammunition has an ammo box item.

## Storage: permanent, shared, personal, banks, locks, loot

Admins: context menu (C) on a crate > **Storage settings**:

- **Permanent**: the crate is saved with the map, contents included, and comes back at every start
  (and after a map cleanup). Players can't move or remove it.
- **Personal**: each player has their own contents in it (per character with a character system).
- **Shared name**: crates with the same name share one contents, anywhere on the map.
- **Capacity**: its own capacity (0: `Config.CrateLoad`).
- **Loot table**: when emptied, the crate is refilled with random items after the delay (minutes).

**Banks** (`advinv_bank`, spawn menu, admins): every bank opens the same personal store of the
player (capacity `Config.BankLoad`, 300), kept between sessions.

**Locks**: the player who spawned or bought a crate, and admins, can lock it and set a code
(context menu > Lock / unlock, Set the code). Others are asked for the code when they use it.

**Loot spawns** (admin menu > Loot spawns): invisible points where a random item of a loot table
appears, and appears again some seconds after it was taken. Add one where you look, then
right-click it in the list to go there, change it or delete it; the points are shown while the
tab is open.

Loot tables (shared): `supplies`, `medical`, `weapons` are provided; add your own:

```lua
AdvInv.LootTables["armory"] = { rolls = { 1, 2 }, items = {
    { item = "advinv_ammo_ar2", weight = 5 },          -- an registered item
    { weapon = "weapon_crowbar", weight = 2 },        -- any weapon class
    { entity = "item_healthkit", weight = 3, count = { 1, 2 } },  -- a whitelisted entity
} }
```

Saved in SQLite (tables created if missing, never dropped): `advinv_storage` (permanent storages,
settings and contents) and `advinv_stores` (shared and personal stores, banks).

## Death

A dead player's body keeps what he carried: his own ragdoll lies where he fell, wearing his gear
(helmet, vest, backpack...) with his weapons carried on it, his pockets, vest and backpack still
full. The weapon he held falls to the ground next to him.

Anyone within reach opens the body with the Use key: his inventory shows next to theirs. Equipped
items are taken with a double-click or right-click > Take (into your slot if it is free, else into
your containers): they leave the body, so a helmet taken is no longer on his head. Pockets, vest and
backpack are emptied by dragging, like a crate. Server settings:

```
advinv_death_drop 3          // left on the body: 0 nothing (the player keeps all), 1 the contents
                             // of the uniform/vest/backpack, 2 the same and the weapons, 3 everything
advinv_death_loot_time 300   // seconds before the body disappears (0: never)
advinv_death_body_max 20     // bodies at most, the oldest goes first
advinv_death_loot_name 1     // the dead player's name is shown on his body
```

Hooks (server): `AdvInv_DeathDrop(ply)` (return false: nothing stays on the body this time) and
`AdvInv_DeathBody(ply, body)`. With a character system the emptied inventory is saved at once, so
the next load doesn't give the items back; without one, the inventory is reset at every spawn.

## Searching a player

Context menu (C) on a player within reach > **Search**. After a few seconds, both players staying
close, the searcher sees the target's inventory on the right of the screen: illegal items have a
red frame and are listed in the chat. The searcher may take items (drag them, or right-click an
equipped weapon > Take) but can't put anything on the target. The target sees who is searching
them; moving away cancels or ends the search.

```
advinv_search_mode 1    // 0 nobody (admins excepted), 1 allowed jobs, 2 anyone
advinv_search_time 5    // seconds a search takes
advinv_search_take 1    // the searcher may take (confiscate) items
```

Allowed jobs (mode 1): DarkRP's police jobs, and the team names in
`AdvInv.Config.SearchTeams`; with neither (no DarkRP, empty list), anyone may search.
Illegal items: `ENT.Illegal = true` on an registered item, or `AdvInv.IllegalItems[class] = true`
for any class. Hooks: `CanSearchInventory(searcher, target)` (shared, false to forbid, true to
allow), `AdvInv_Searched(searcher, target, illegalNames)` and
`AdvInv_Confiscated(searcher, target, item)` (server).

## DarkRP

- What is bought from the F4 menu (entities, weapons, ammo) goes straight into the inventory when
  there is room (`advinv_darkrp_buy_to_inventory 1`). Shipments stay as they are; the weapons they
  give, like any DarkRP weapon lying around, are taken with Use (full magazine), one at a time.
- DarkRP ammo lying around becomes ammo boxes.
- `/drop` on an inventory weapon: DarkRP drops it as usual and its slot is freed. DarkRP's drop on
  death never drops an inventory weapon (it stays on the body).
- The inventory shows the wallet, with **Drop money**.
- `advinv_darkrp_loadout_to_inventory 1` (off by default): the job's weapons that fit a free slot
  become inventory weapons (on the body, carry modes, dropped on death). With death drops on,
  every respawn gives new ones to drop: think of it before turning it on.

## Administration

Admins open the admin menu with the console command `advinv_admin`, or right-click a player in the
context menu (C) > **Inventory (admin)**.

- **Players**: view a player's inventory next to yours, from anywhere on the map: drag items
  between you, right-click an item > Delete, right-click an equipped item > Take or Delete.
  **Clear the inventory** deletes everything the player carries and wears.
- **Items**: give any item, or any weapon by its class, to a player (boxes full, weapons loaded,
  gear at full armour).
- **Settings**: every server setting of the addon (the `advinv_*` console variables), applied at once.

Who is an admin: the CAMI privilege `Advanced Inventory System - Admin` (superadmins by default; ULX, SAM,
FAdmin... can give it to other groups). Without CAMI: superadmins. The server checks every request,
logs each action in its console and calls the hook `AdvInv_AdminAction(admin, action, target, text)`.

## More

- **Tooltips**: mass, slot, rarity, rounds and magazine, ammunition, carry modes, armour,
  capacity, what using it gives, and "Illegal".
- **Rarity** (1 common ... 5 legendary): `ENT.Rarity` on an item or
  `AdvInv.ItemRarity[class] = 3` for any class; the item's frame takes its colour.
- **Armour by body part**: any worn item with `ENT.Armor` protects the parts it covers, wears
  down as it is hit and lets more damage through as it does. Parts: `ENT.ArmorHitgroups` on the
  item, else by slot (`AdvInv.ArmorZones`: helmet head, vest chest and stomach, uniform body,
  arms and legs, gas mask head).
- **Themes**: Options > Advanced Inventory > Inventory: more > Colours (dark, light, military), or the
  client setting `advinv_theme`.
- **Languages**: `advinv_language en / fr / de / es / ru` (German, Spanish and Russian in
  `lua/advinv/sh_lang_more.lua`; item names stay in English there; corrections welcome).
- **Opening**: the I key, the chat commands `!inventory`, `/inventory`, `!inv`, `/inv`, or the
  Inventory tool (`advinv_inventory_tool`: left click opens, right click takes the item looked at).
- **Pickup key**: Options > Advanced Inventory > Inventory: more (none by default: the Use key).
- **Crafting** (off by default: `advinv_craft 1` on the server, or the admin menu): the Crafting
  button of the inventory, or a workbench (`advinv_workbench`, admins): recipes take their
  ingredients from the uniform, vest and backpack. Two examples are provided
  (health kit from 2 vials; .357 rounds from 3 pistol boxes, at a workbench). Add yours (shared):

```lua
AdvInv.AddRecipe({
    id = "bandage", name = { en = "Bandage", fr = "Bandage" },
    needs = { { item = "advinv_cloth", count = 2 } },     -- item / entity / weapon / ammo
    gives = { entity = "item_healthvial" },
    bench = false, time = 2,
})
```

  Hooks (server): `AdvInv_CanCraft(ply, recipe)` (false to forbid), `AdvInv_Crafted(ply, recipe)`.
- **Wiremod** (if installed): crates have the outputs Load, Capacity, Items and Viewers.

## Option: the load slows the player down

Off by default. In `server.cfg`:

```
advinv_load_slowdown 1        // turns the option on
advinv_load_free 300          // load without any effect (points)
advinv_load_max 1000          // load at which the slowdown is at its maximum
advinv_load_min_speed 0.55    // remaining speed at that load (fraction)
```

The load is the mass of everything the player carries (contents of the containers and equipped
items); it is shown in the inventory, with the speed when the option is on.

## Uniform

The "Uniform" slot takes an item based on `advinv_base_uniform`; its `ENT.MaxLoad` sets the
capacity of the pockets. Without a uniform, the pockets hold `Config.DefaultUniformLoad`. The
uniform doesn't change the player's appearance.

```lua
ENT.Base = "advinv_base_uniform"
ENT.PrintName = "F2 fatigues"
ENT.Spawnable = true
ENT.Model = "models/props_junk/cardboard_box004a.mdl"
ENT.MaxLoad = 60 -- pocket capacity
ENT.Mass = 30    -- mass when it is stored
```

## Contents

- `lua/autorun/advinv_loader.lua`: loads the addon
- `lua/advinv/`: logic (item registry, SQLite saving, interface, gear display, placement
  editor, languages)
- `lua/entities/advinv_base_*`: base classes of the items
  (`advinv_base_helmet`, `advinv_base_vest`, `advinv_base_pocketvest`, `advinv_base_rucksack`,
  `advinv_base_wep`, `advinv_base_ammobox`, `advinv_base_gear`)
- `lua/entities/advinv_*`: included items, made with base-game models
- `lua/entities/advinv_crate.lua`: storage crate (capacity 1000, contents not saved)

The addon is Lua only: models, icons and sounds all come from Garry's Mod.

## Included items

Spawn menu (Entities): "Inventory: Gear", "Inventory: Weapons", "Inventory: Ammo" and
"Inventory: Furniture" (crates, bank locker, workbench); the Inventory tool is in Weapons >
"Inventory". Items without an icon of their own show their model, like props. They only use
models installed with Garry's Mod. Reserved IDs: 100 to 127.

| Item | Slot | Model | Display |
|---|---|---|---|
| `advinv_cp_mask` | gas mask | `models/barneyhelmet_faceplate.mdl` | bone + offset |
| `advinv_top_hat` | helmet | `models/player/items/humans/top_hat.mdl` | bonemerge |
| `advinv_graduation_cap` | helmet | `models/player/items/humans/graduation_cap.mdl` | bonemerge |
| `advinv_barney_helmet` | helmet | `models/barneyhelmet.mdl` | bone + offset |
| `advinv_bucket` | helmet | `models/props_junk/metalbucket01a.mdl` | bone + offset |
| `advinv_jetpack` | backpack | `models/thrusters/jetpack.mdl` | bone + offset |
| `advinv_suitcase` | backpack | `models/props_c17/suitcase001a.mdl` | bone + offset |

HL2 weapons and their ammo:

| Weapon | Slot | Ammo type | Ammo item |
|---|---|---|---|
| `advinv_hl2_pistol` (`weapon_pistol`) | sidearm | `Pistol` | `advinv_ammo_pistol` (20) |
| `advinv_hl2_357` (`weapon_357`) | sidearm | `357` | `advinv_ammo_357` (6) |
| `advinv_hl2_smg1` (`weapon_smg1`) | primary weapon | `SMG1`, `SMG1_Grenade` | `advinv_ammo_smg1` (45), `advinv_ammo_smg1_grenade` (1) |
| `advinv_hl2_ar2` (`weapon_ar2`) | primary weapon | `AR2`, `AR2AltFire` | `advinv_ammo_ar2` (20), `advinv_ammo_ar2_altfire` (1) |
| `advinv_hl2_shotgun` (`weapon_shotgun`) | primary weapon | `Buckshot` | `advinv_ammo_buckshot` (20) |
| `advinv_hl2_crossbow` (`weapon_crossbow`) | primary weapon | `XBowBolt` | `advinv_ammo_crossbow` (6) |
| `advinv_hl2_rpg` (`weapon_rpg`) | launcher | `RPG_Round` | `advinv_ammo_rpg` (1) |

Spawn menu icons: weapons and ammo reuse Garry's Mod's (`ENT.IconOverride =
"entities/weapon_smg1.png"`); items without one (gear, crates) show their model, like props (the
addon ships no materials).

Reserve ammo is the ammo items stored in the inventory: reloading uses up these items. A weapon
without a magazine (`ENT.ClipSize = -1`, like the rocket launcher) is given without ammo.

## Making an item

An item is an entity that inherits from a base class, plus a unique ID. Give it a name in each
language with `AdvInv.T(english, french)`, or a plain string.

**Any prop**: attach it to a playermodel bone with `ENT.Attach`.

```lua
-- lua/entities/my_helmet.lua
AddCSLuaFile()
ENT.Base = "advinv_base_helmet"
ENT.PrintName = AdvInv.T("Heavy helmet", "Casque lourd")
ENT.Spawnable = true
ENT.Model = "models/my_addon/helmet.mdl"
ENT.Armor = 150
ENT.Attach = {
    bone = "ValveBiped.Bip01_Head1",
    pos = Vector(1.5, 0.4, -1.5),
    ang = Angle(90, 10, 0),
    scale = 1,
}

-- anywhere in a shared file (lua/autorun/...):
AdvInv = AdvInv or {}
AdvInv.ClassID = AdvInv.ClassID or {}
AdvInv.ClassID["my_helmet"] = 42
```

**Model rigged to the ValveBiped skeleton**: don't set `ENT.Attach`; the item is shown with
bonemerge and bends with the body (vests, backpacks with straps).

Two playermodels with the same skeleton don't have the same build (chest further forward,
shoulders higher...). A rigged item fitted on `models/player/group01/male_07.mdl` can declare
`ENT.BodyFit` to be shifted according to the playermodel wearing it:

```lua
ENT.BodyFit = "vest" -- centred on the torso, straps resting on the shoulders
ENT.BodyFit = "back" -- against the back
```

The shift follows the player's Spine4 bone (the item keeps bending with the body). The
measurements of the 87 playermodels that come with Garry's Mod are in
`lua/advinv/cl_bodyfit_data.lua`; a playermodel missing from the table keeps the original
placement. An addon can add its own: `AdvInv.BodyFit.models["models/x.mdl"] = { front, back, shoulder }`,
measured with `tools/bodyfit.py` (see the script's header).

To find the `ENT.Attach` values, open the editor from the console:

```
advinv_attach_editor                  -- Barney's helmet by default
advinv_attach_editor my_helmet        -- takes the model and settings of an item
advinv_attach_editor models/x/y.mdl   -- any model
```

Tune the bone, offset, rotation and size on the preview, then "Copy the code" and paste the block
into the item's file.

If the model has no collision model (`.phy`), the item dropped on the ground gets a collision box
around the model; `ENT.PhysBox = { Vector(...), Vector(...) }` sets it by hand.

ID rules: between 2 and 127, unique, and **never changed** once in production (they are saved in
the database).

Useful fields depending on the base: `Mass` (all items), `MaxLoad` (capacity of a backpack, a
vest with pockets or a uniform), `Armor` (helmet, vest), `NVGsHolder` (helmet that can carry
NVGs), `AdvInvCategory` (`Rucksack` for a backpack, `Gasmask` for a mask, `Radio` for a headset),
and for weapons `WeaponClass`, `Ammo`, `Rounds`, `ClipSize` with `AdvInvCategory` = `PrimaryWep`,
`SecondaryWep` or `RocketLauncher`.

## Fitted to each playermodel

Every worn item and the weapon mounts are adapted to each of the 87 playermodels that come with
Garry's Mod (`tools/playermodels.txt`): helmets rest on that head, hats and the bucket grow where a
head, hair or headgear would poke through, backpacks sit on that back, weapons on that back and
thigh. The values are in `lua/advinv/cl_fits_data.lua`, generated by `tools/fit_items.py`
(see its header for the rules); a playermodel that is not in it (a custom one) uses the item's own
`ENT.Attach` and `Config.WeaponMounts`. After changing an item or adding a playermodel to the list:

```
cd tools
python fit_items.py                 # rewrites lua/advinv/cl_fits_data.lua
python fit_sheets.py out_dir        # one image per item: the item on every playermodel
```

## Checking worn items without the game

`tools/mount_check.py` (not included in the `.gma`) puts every worn item of `lua/entities` on
playermodels the way the game does (FollowBone with `ENT.Attach`, bonemerge without it), in their
reference pose, and renders them from the front, the left and the back, without starting Garry's
Mod. Default bodies: Dr. Isaac Kleiner and male_07; any playermodel of the game can be given.

```
cd tools
python mount_check.py out_dir [models/player/alyx.mdl ...]
```

`tools/weapon_check.py` does the same for weapons: their inventory icons and loadouts on the body
(with and without a backpack). Weapon world models are posed in the first frame of their idle
sequence (`tools/anim0.py`), as the game draws them: barrel along +X, top along +Z.

Items are drawn in their rest pose (first frame of their idle sequence): many props are stored turned and only reach their real orientation through it (static props excepted). In the reference pose a ValveBiped body faces -Y; in the head bone, X points up, Y to the back
and Z to the right (useful when writing `ENT.Attach` by hand).

## Saving and linking to a character system

On its own, the addon resets the inventory at every spawn and saves nothing. To save inventories
(per player, per character...), answer who owns the inventory a player carries and call Load /
Save:

```lua
-- server
hook.Add("AdvInv_ShouldAutoInit", "MyRP", function() return false end) -- no reset at spawn
hook.Add("AdvInv_OwnerID", "MyRP", function(ply) return myCharacterID(ply) end)

AdvInv.Load(ply, owner)      -- when the player takes the character (equipped items are given)
AdvInv.Save(ply, owner)      -- on disconnect / server shutdown
AdvInv.Record(owner)         -- the saved data without a player (previews...)
AdvInv.RecordSlot(record, "Helmet") -- an item of a saved slot
AdvInv.DeleteRecord(owner)   -- a deleted character
AdvInv.GiveWeapons(ply)      -- gives back the slot weapons the player lacks (after a StripWeapons)
AdvInv.SetDefaults(ply)      -- empty starting inventory
AdvInv.Clear(ply)            -- empty everything
```

An owner is any string or number (a SteamID64, a character ID...). Client side:
`AdvInv_CanOpen(ply)` (return false to prevent opening) and `AdvInv_PanelCreated(panel, target)`.

The data is in the SQLite table `advinv_inventory` (`sv.db`), one row per owner, as JSON:
`{"v":3,"s":{slot: item},"c":{container: [items]}}` with items packed as
`[id, rounds, armour, carry mode, class, extra]`. The table's columns never change.

## Publishing

```
gmad.exe create -folder "addons/advanced-inventory" -out "advanced-inventory.gma"
gmpublish.exe create -addon "advanced-inventory.gma" -icon "icon_512x512.jpg"
```

The Workshop page's description (Steam formatting, every feature, link to GitHub) is in
`workshop/description.txt`: paste it into the page after publishing.
