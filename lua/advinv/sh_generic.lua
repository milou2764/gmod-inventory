--[[
    Generic items: things with no registered item of their own, kept with their class name.
        { id = I.GENERIC_WEAPON, c = "weapon_class" }   any weapon: SWEPs and the HL2 engine weapons
        { id = I.GENERIC_ENTITY, c = "entity_class" }   a whitelisted entity (health kit, battery...)
        { id = I.GENERIC_AMMO, c = "ammo type" }        ammo of a type with no registered ammo item
    Any item may also carry x = extra data of its weapon (attachments: sv_generic.lua).
    An equipped generic weapon keeps its class in the player's NW string <slot>.."Class".

    Server settings (sv_generic.lua):
        advinv_pickup_weapons 1      weapons lying in the world are taken with the Use key into the
                                   inventory instead of being picked up by walking over them
        advinv_pickup_any_weapon 1   weapons with no registered item of their own become generic items
        advinv_pickup_entities 1     whitelisted entities are taken with Use into the inventory

    Tables other addons can fill (shared):
        I.PickupWhitelist[class] = { name = "...", model = "...", mass = 5 }
        I.WeaponBlacklist[class] = true        never turned into an item (tools, keys, hands...)
        I.PickupConvert[class] = "item_class"  becomes that registered item (HL2 ammo -> ammo boxes)
        I.WeaponCategory[class] = "PrimaryWep" / "SecondaryWep" / "RocketLauncher"
--]]
local I = AdvInv

-- Created here (shared) so that the client reads the server's values (sv_generic.lua uses them).
local PFLAGS = { FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED }
CreateConVar("advinv_pickup_weapons", "1", PFLAGS, "Weapons lying in the world are taken with Use into the inventory (not by walking over them)", 0, 1)
CreateConVar("advinv_pickup_any_weapon", "1", PFLAGS, "Weapons with no registered item of their own become generic inventory items", 0, 1)
CreateConVar("advinv_pickup_entities", "1", PFLAGS, "Whitelisted entities (health kits, batteries, HL2 ammo...) are taken with Use into the inventory", 0, 1)

I.GENERIC_WEAPON = 100
I.GENERIC_ENTITY = 103
I.GENERIC_AMMO = 125
AdvInv.ClassID = AdvInv.ClassID or {}
AdvInv.ClassID.advinv_any_weapon = I.GENERIC_WEAPON
AdvInv.ClassID.advinv_any_entity = I.GENERIC_ENTITY
AdvInv.ClassID.advinv_any_ammo = I.GENERIC_AMMO

function I.IsGeneric(id)
    return id == I.GENERIC_WEAPON or id == I.GENERIC_ENTITY or id == I.GENERIC_AMMO
end

-- Generic ammo boxes: rounds per box, mass and model by ammunition type (defaults: 30, 8, a box).
I.AmmoBoxSize = I.AmmoBoxSize or {}
I.AmmoBoxMass = I.AmmoBoxMass or {}
I.AmmoBoxModel = I.AmmoBoxModel or {}

-- HL2 weapons built into the engine (weapons.Get knows only Lua weapons). The HL2 guns have their
-- own registered items (advinv_hl2_*); these are the others.
local HL2 = {
    weapon_crowbar = { "Crowbar", "Pied-de-biche", "models/weapons/w_crowbar.mdl", "SecondaryWep", -1, "" },
    weapon_stunstick = { "Stunstick", "Matraque électrique", "models/weapons/w_stunbaton.mdl", "SecondaryWep", -1, "" },
    weapon_frag = { "Grenade", "Grenade", "models/weapons/w_grenade.mdl", "SecondaryWep", -1, "Grenade" },
    weapon_slam = { "S.L.A.M", "S.L.A.M", "models/weapons/w_slam.mdl", "SecondaryWep", -1, "slam" },
    weapon_bugbait = { "Bugbait", "Phéropode", "models/weapons/w_bugbait.mdl", "SecondaryWep", -1, "" },
}

I.WeaponBlacklist = I.WeaponBlacklist or {}
for _, class in ipairs({
    "weapon_physgun", "weapon_physcannon", "gmod_tool", "gmod_camera", "weapon_fists", "weapon_medkit",
    "manhack_welder", "weapon_flechettegun", "keys", "pocket", "weapon_keypadchecker", "arrest_stick",
    "unarrest_stick", "stunstick", "door_ram", "lockpick", "med_kit", "weaponchecker", "weapon_inventory",
}) do
    if I.WeaponBlacklist[class] == nil then I.WeaponBlacklist[class] = true end
end

I.WeaponCategory = I.WeaponCategory or {}

I.PickupWhitelist = I.PickupWhitelist or {}
for class, d in pairs({
    item_healthkit = { name = I.T("Health kit", "Trousse de soins"), model = "models/items/healthkit.mdl", mass = 10 },
    item_healthvial = { name = I.T("Health vial", "Fiole de soins"), model = "models/healthvial.mdl", mass = 4 },
    item_battery = { name = I.T("Suit battery", "Batterie de combinaison"), model = "models/items/battery.mdl", mass = 5 },
}) do
    if I.PickupWhitelist[class] == nil then I.PickupWhitelist[class] = d end
end

-- HL2 ammo lying in the world becomes the matching ammo box (with its usual count of rounds).
I.PickupConvert = I.PickupConvert or {}
for class, item in pairs({
    item_ammo_pistol = "advinv_ammo_pistol", item_ammo_pistol_large = "advinv_ammo_pistol",
    item_ammo_357 = "advinv_ammo_357", item_ammo_357_large = "advinv_ammo_357",
    item_ammo_smg1 = "advinv_ammo_smg1", item_ammo_smg1_large = "advinv_ammo_smg1",
    item_ammo_smg1_grenade = "advinv_ammo_smg1_grenade", item_ammo_ar2 = "advinv_ammo_ar2",
    item_ammo_ar2_large = "advinv_ammo_ar2", item_ammo_ar2_altfire = "advinv_ammo_ar2_altfire",
    item_box_buckshot = "advinv_ammo_buckshot", item_ammo_crossbow = "advinv_ammo_crossbow",
    item_rpg_round = "advinv_ammo_rpg",
}) do
    if I.PickupConvert[class] == nil then I.PickupConvert[class] = item end
end

local WEAPON_MASS = { PrimaryWep = 80, SecondaryWep = 20, RocketLauncher = 100 }

-- Ammunition and magazine size a weapon table declares. Most bases fill SWEP.Primary; ARC9 declares
-- SWEP.Ammo and SWEP.ClipSize, its Primary.Ammo staying the base's "" (and Primary.ClipSize
-- weapon_base's 8).
function I.SwepAmmo(swep)
    if not swep then return end
    if swep.ARC9 and isstring(swep.Ammo) and swep.Ammo ~= "" then return swep.Ammo end
    return swep.Primary and swep.Primary.Ammo
end

function I.SwepClipSize(swep)
    if not swep then return end
    if swep.ARC9 and isnumber(swep.ClipSize) then return swep.ClipSize end
    return swep.Primary and swep.Primary.ClipSize
end

-- Slot of a weapon that has no registered item: its own AdvInvCategory, I.WeaponCategory, else a guess
-- from its menu slot and hold type.
local function guessCategory(class, swep)
    if I.WeaponCategory[class] then return I.WeaponCategory[class] end
    if swep and swep.AdvInvCategory then return swep.AdvInvCategory end
    -- (some bases, CW 2.0, set their hold type only when deployed: NormalHoldType; ArcCW names it
    -- HoldtypeActive)
    local hold = swep and string.lower(swep.HoldType or swep.NormalHoldType or swep.HoldtypeActive or "") or ""
    local ammo = string.lower(tostring(I.SwepAmmo(swep) or ""))
    if hold == "rpg" or ammo == "rpg_round" then return "RocketLauncher" end
    -- (not SWEP.Slot: many weapons set it on the client only, the server would guess another slot)
    if hold == "pistol" or hold == "revolver" or hold == "melee" or hold == "knife"
        or hold == "fist" or hold == "grenade" or hold == "slam" or hold == "melee2" then
        return "SecondaryWep"
    end
    return "PrimaryWep"
end

local function phrase(name)
    if CLIENT and isstring(name) and name:sub(1, 1) == "#" then return language.GetPhrase(name:sub(2)) end
    return name
end

--[[
    Entity-like table of an item (fields of an ENT: ClassName, PrintName, Model, AdvInvCategory,
    WeaponClass, ClipSize, Ammo, Mass...): the registered item's own table, or one made for a generic
    item from its class. nil if unknown.
--]]
local defCache = {}
function I.DefTable(id, c)
    if not id or id <= 1 then return end
    if not I.IsGeneric(id) then return I.EntTable(id) end
    if not isstring(c) or c == "" then return end
    local key = id .. ":" .. c
    local d = defCache[key]
    if d ~= nil then return d or nil end
    if id == I.GENERIC_WEAPON then
        local swep, hl2 = weapons.Get(c), HL2[c]
        if swep or hl2 then
            local fr = I.Language and I.Language() == "fr"
            d = {
                ClassName = "advinv_any_weapon", Generic = true, WeaponClass = c,
                PrintName = phrase(swep and swep.PrintName) or (hl2 and (fr and hl2[2] or hl2[1])) or c,
                Model = (swep and swep.WorldModel ~= "" and swep.WorldModel) or (hl2 and hl2[3]) or "models/weapons/w_pistol.mdl",
                AdvInvCategory = (hl2 and not I.WeaponCategory[c]) and hl2[4] or guessCategory(c, swep),
                ClipSize = I.SwepClipSize(swep) or (hl2 and hl2[5]) or -1,
                Ammo = I.SwepAmmo(swep) or (hl2 and hl2[6]) or "",
            }
            d.Mass = (swep and swep.AdvInvMass) or WEAPON_MASS[d.AdvInvCategory] or 20
        end
    elseif id == I.GENERIC_AMMO then
        local grenade = I.GrenadeOfAmmo and I.GrenadeOfAmmo(c)
        if grenade and game.GetAmmoID(c) ~= -1 then
            -- a grenade (sh_grenades.lua): one per item, named and shown like the weapon
            local swep, hl2 = weapons.Get(grenade), HL2[grenade]
            local fr = I.Language and I.Language() == "fr"
            local sname = swep and swep.PrintName
            if sname == "Scripted Weapon" then sname = nil end -- (named on the client only: weapon_base's default)
            d = {
                ClassName = "advinv_any_ammo", Generic = true, Ammo = c, Grenade = grenade,
                PrintName = phrase(sname) or (hl2 and (fr and hl2[2] or hl2[1])) or c,
                Model = (swep and swep.WorldModel ~= "" and swep.WorldModel) or (hl2 and hl2[3]) or "models/weapons/w_grenade.mdl",
                Capacity = 1, Rounds = 1, Mass = I.AmmoBoxMass[c] or 6,
            }
        elseif game.GetAmmoID(c) ~= -1 then
            local name = c
            if CLIENT then
                local p = language.GetPhrase(c .. "_ammo")
                if p ~= c .. "_ammo" then name = p end
            end
            d = {
                ClassName = "advinv_any_ammo", Generic = true, Ammo = c,
                PrintName = I.L("generic_ammo", name),
                Model = I.AmmoBoxModel[c] or "models/items/boxmrounds.mdl",
                Capacity = I.AmmoBoxSize[c] or 30, Rounds = I.AmmoBoxSize[c] or 30,
                Mass = I.AmmoBoxMass[c] or 8,
            }
        end
    elseif id == I.GENERIC_ENTITY then
        local w = I.PickupWhitelist[c]
        if w then
            local sent = scripted_ents.Get(c)
            d = {
                ClassName = "advinv_any_entity", Generic = true, EntityClass = c,
                PrintName = w.name or phrase(sent and sent.PrintName) or c,
                Model = w.model or (sent and sent.Model) or "models/props_junk/cardboard_box004a.mdl",
                Mass = w.mass or 10,
            }
        end
    end
    defCache[key] = d or false
    return d
end

hook.Add("AdvInv_ItemsInitialized", "AdvInv_GenericCache", function() defCache = {} end)

-- registered item whose weapon is this class (advinv_hl2_ar2 for weapon_ar2...), or nil.
local byWeapon
function I.ItemForWeapon(class)
    if not byWeapon then
        byWeapon = {}
        for id, cls in pairs(AdvInv.IDClass or {}) do
            local t = id > 1 and not I.IsGeneric(id) and AdvInv.ClassTable(cls)
            if t and t.WeaponClass and not byWeapon[t.WeaponClass] then byWeapon[t.WeaponClass] = id end
        end
    end
    return byWeapon[class]
end
hook.Add("AdvInv_ItemsInitialized", "AdvInv_WeaponItems", function() byWeapon = nil end)

--[[
    Rarity (1 common ... 5 legendary): ENT.Rarity on an item, or AdvInv.ItemRarity[class]
    (any class, generic items too). Shown as the colour of the item's frame and in its tooltip.
--]]
I.ItemRarity = I.ItemRarity or {}
I.RarityColors = I.RarityColors or {
    Color(170, 170, 170), Color(90, 190, 90), Color(70, 140, 235), Color(170, 90, 230), Color(240, 150, 40),
}
-- Off by default (server setting advinv_rarity 1, or the admin menu).
local rarityVar = CreateConVar("advinv_rarity", "0", { FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED },
    "Rarity of items: coloured frames and tooltips (0: off)", 0, 1)
function I.RarityEnabled() return rarityVar:GetBool() end
cvars.AddChangeCallback("advinv_rarity", function() if I.ClearInfoCache then I.ClearInfoCache() end end, "AdvInv")

function I.Rarity(t)
    if not rarityVar:GetBool() then return nil end
    local r = t.Rarity or I.ItemRarity[t.WeaponClass or t.EntityClass or t.ClassName or ""]
    return isnumber(r) and r > 1 and math.min(math.floor(r), 5) or nil
end

-- Item in an equipment slot: id, class (generic weapons only).
function I.SlotRef(ent, cat)
    if AdvInv.GearCat[cat] then return ent:GetNW2Int(cat), nil end
    local id = ent:GetNWInt(cat)
    if id == I.GENERIC_WEAPON then return id, ent:GetNWString(cat .. "Class") end
    return id, nil
end

function I.SlotInfo(ent, cat)
    return I.Info(I.SlotRef(ent, cat))
end
