AdvInv = AdvInv or {}

--[[
    Registre des objets : nom de classe d'entité -> ID numérique.
    - 0 = pas d'emplacement, 1 = emplacement vide (advinv_null).
    - Les ID sont enregistrés en base : ne jamais changer l'ID d'un objet existant.
    - Les ID doivent rester entre 2 et 127 (ils sont envoyés sur 7 bits).
    Un addon ajoute ses objets ainsi, quel que soit l'ordre de chargement :
        AdvInv = AdvInv or {}
        AdvInv.ClassID = AdvInv.ClassID or {}
        AdvInv.ClassID["mon_casque"] = 42
--]]
AdvInv.ClassID = AdvInv.ClassID or {}
AdvInv.IDClass = AdvInv.IDClass or {}
AdvInv.mountedGear = AdvInv.mountedGear or {}

if CLIENT then
    AdvInv.MountedWeps = AdvInv.MountedWeps or {}
end

--[[
    Returns the class name associated with the given ID
    @param itemID Unique ID
--]]
function AdvInv.EntityTable(itemID)
    return scripted_ents.Get(AdvInv.IDClass[itemID])
end

AdvInv.WeaponCat = {
    "PrimaryWep",
    "SecondaryWep",
    "RocketLauncher",
}

AdvInv.GearCat = {
    ["NVGs"] = true,
    ["Helmet"] = true,
    ["Gasmask"] = true,
    ["Rucksack"] = true,
    ["Vest"] = true,
    ["Radio"] = true, -- casque audio / radio
    ["Uniform"] = true, -- tenue : fixe la capacité des poches (enregistrée avec le contenu de l'inventaire)
}

-- Catégories équipées sans modèle affiché sur le joueur (la tenue ne change pas le playermodel).
AdvInv.NoMountCat = { Uniform = true }

AdvInv.CategoryID = {
    NVGs = 0,
    Gasmask = 1,
    Helmet = 2,
    Vest = 3,
    Rucksack = 4,
    PrimaryWep = 5,
    SecondaryWep = 6,
    RocketLauncher = 7,
    Radio = 8, -- envoyé sur 4 bits : 15 au maximum
    Uniform = 9,
}
AdvInv.IDCategory = {}
for cat,id in pairs(AdvInv.CategoryID) do
    AdvInv.IDCategory[id]=cat
end

-- Construit la table ID -> classe une fois que tous les addons ont rempli AdvInv.ClassID.
local function AdvInv_InitItems()
    AdvInv.IDClass = {
        [0] = "advinv_null", -- no item slot
        [1] = "advinv_null", -- empty item slot
    }
    for class, id in pairs(AdvInv.ClassID) do
        AdvInv.IDClass[id] = class
    end
    AdvInv.entityModels = {}

    hook.Call("AdvInv_InitItems")
    hook.Call("AdvInv_ItemsInitialized")
    AdvInv.EntitiesInitialized = true
end

hook.Add("InitPostEntity", "AdvInv_InitItems", AdvInv_InitItems)
