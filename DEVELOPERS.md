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
  lua/autorun/my_gear.lua         -- registers the IDs (shared)
  lua/entities/my_helmet.lua      -- one entity per item
```

```lua
-- lua/autorun/my_gear.lua
AdvInv = AdvInv or {}
AdvInv.ClassID = AdvInv.ClassID or {}
AdvInv.ClassID["my_helmet"] = 40      -- unique, 2-127, never changed afterwards
AdvInv.ClassID["my_backpack"] = 41
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

- Between **2 and 127** (sent on 7 bits). 0 = no slot, 1 = empty slot.
- **Unique** across all installed addons, and **never changed** once a server uses them: they
  are what the database saves. Changing an ID turns saved items into another item, or into
  nothing.
- Taken: 100-127 by the AIS (100 any weapon, 103 any whitelisted entity, 125 any ammo type,
  the HL2 weapons, ammo and gear), 62-99 by `mrpi-military`. Tell the users of your addon which
  range it takes, and keep a few IDs free for later items.
- Register them in a **shared** file with the `AdvInv = AdvInv or {}` line, whatever the loading
  order of the addons. The table of IDs to classes is built at `InitPostEntity`
  (hook `AdvInv_ItemsInitialized`); `AdvInv.IDClass[id]` and `AdvInv.EntityTable(id)` work after it.

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
| `WeaponClass` | weapons | the SWEP given when equipped |
| `Ammo`, `ClipSize`, `Rounds` | weapons | ammo type, magazine size, rounds when spawned (`ClipSize = -1`: no magazine) |
| `CarryModes`, `CarryDefault` | long guns | `{ "sling_up", "back_carry", ... }`, default mode |
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
- Client: `AdvInv.mountedGear[userid][slot]` is the clientside model drawn on a player.

## Weapons and carry modes

A weapon item (`advinv_base_wep`) gives its `WeaponClass` when equipped and takes it away when
taken off; the magazine is kept in the item. Long guns are always carried on the body in one of
five modes (`sling_up`, `sling_down`, `cross_body`, `back_carry`, `front_hang`), one per body zone,
chosen by the player (right-click). Configure a weapon by class (shared):

```lua
AdvInv.CarryWeapons = AdvInv.CarryWeapons or {}
AdvInv.CarryWeapons["my_rifle"] = { default = "sling_up" }                          -- every mode
AdvInv.CarryWeapons["my_launcher"] = { modes = { "back_carry" }, default = "back_carry" }
```

A registered weapon item can set `ENT.CarryModes` / `ENT.CarryDefault` instead. A generic weapon
(a SWEP without an item of its own, see below) with no entry gets every mode if it is a primary
weapon, `back_carry`/`sling_up` if it is a launcher. Without exact positions, a weapon is placed by
a template fitted to the shape of its world model. Exact positions per playermodel:
`tools/fit_carry.py` writes `cl_carry_data.lua`; tune in game with `advinv_carry_tune`
(`advinv_carry_cycle` cycles through the modes). Hooks: `CanChangeCarryMode`,
`OnCarryModeChanged`.

## Ammunition

The reserve of a weapon is the ammo boxes stored in the player's containers: reloading uses them
up (the least full first), unloading a weapon fills them. Never give reserve ammo with
`ply:GiveAmmo` for an inventory weapon: the next count sets the reserve back to the boxes. Use
`AdvInv.GiveRounds(ply, ammoType, rounds)` (server): it fills the started boxes, then new boxes,
then the ground.

- A registered ammo box: an item based on `advinv_base_ammobox`.
- Any other ammo type gets a **generic box** (ID 125, `c = ammo type`): sizes per type in
  `AdvInv.AmmoBoxSize[type]`, `AdvInv.AmmoBoxMass[type]`, `AdvInv.AmmoBoxModel[type]`.
- An ammo entity of another addon is taken with Use when it says its type and amount:
  `ENT.AmmoType = "5.56x45MM"` and `ENT.AmmoCount` (or `AmmoAmount`, `Amount`).

## Things that are not items: generic items

Any SWEP lying in the world becomes a **generic weapon** (ID 100, `c = class`): its slot is guessed
from `SWEP.Slot` and its hold type (`HoldType` or `NormalHoldType`), its mass from the slot. Tables
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

## Other weapon bases

- **Attachments** travel with the item in `x` (a string, at most 4096 characters). Built-in:
  ARC9 (preset code), TFA (selected attachments), CW 2.0 (names; whoever equips the weapon is given
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
| `AdvInv.CanFit(holder, cont, id, c)`, `Used`, `Free`, `MaxLoad` | capacity checks (points) |
| `AdvInv.Equip(ply, item, contents)` | equips an item (slot must be free); `true` or `false, reason` |
| `AdvInv.TakeOff(ply, slot)` | empties a slot; returns the item (and a vest/backpack's contents) |
| `AdvInv.SpawnItem(item, pos, contents, count)` | puts an item in the world; returns the entity |
| `AdvInv.DropStack(item, n, pos)` | n identical items as one stack on the ground |
| `AdvInv.DropPos(ply)` | where a player drops things |
| `AdvInv.GiveRounds(ply, ammo, rounds)` | ammo into boxes (see Ammunition) |
| `AdvInv.Use(ply, ent)` | takes an entity from the world as if the player pressed Use |
| `AdvInv.ItemFromEntity(ent)` | the item an entity would become, or nil |
| `AdvInv.ItemForWeaponClass(class, rounds)` | the item for a weapon class (registered or generic) |
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
| `AdvInv_ShouldAutoInit` | server | ply | `false`: no reset at spawn |
| `AdvInv_Changed` | client | holder, cont | a container was received |
| `AdvInv_CanOpen` | client | ply | `false`: the inventory doesn't open |
| `AdvInv_PanelCreated` | client | panel, target | adjust the inventory window |
| `AdvInv_UseItem` | server | ply, item | `false` to forbid using it |
| `AdvInv_DeathDrop` | server | ply | `false`: nothing stays on the body this time |
| `AdvInv_DeathBody` | server | ply, body | the body was made |
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
| `fit_carry.py` | carry mode positions of the long guns (`cl_carry_data.lua`) |
| `carry_sheets.py`, `fit_sheets.py` | contact sheets to check them |
| `mount_check.py` | renders worn items on playermodels, without the game |
| `bodyfit.py`, `bodyfit_lua.py` | torso measurements of playermodels (`cl_bodyfit_data.lua`) |
| `weapon_check.py`, `mdl_render.py`, `studio.py`, `vpk.py`, `anim0.py`, `refbody.py` | model reading and rendering |

In game: `advinv_attach_editor` (worn item positions), `advinv_carry_tune` / `advinv_carry_cycle`
(carry positions), `advinv_admin` (admin menu). Tests: `tests/README.md`.
