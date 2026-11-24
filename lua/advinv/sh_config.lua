AdvInv = AdvInv or {}

--[[
    Item registry. An item's ID is its entity class name: unique whatever the addons (Garry's Mod
    allows one class per name; put your name in it, e.g. "advinv_myname_helmet"). Saved inventories
    store class names. An addon registers its items, whatever the loading order:
        AdvInv = AdvInv or {}
        AdvInv.Items = AdvInv.Items or {}
        AdvInv.Items["advinv_myname_helmet"] = true
    Within a game session each item also has a number (AdvInv.ClassID[class] / AdvInv.IDClass[id]):
    the network sends that, never saves it. 0 = no slot, 1 = empty slot (advinv_null).
    The older way, AdvInv.ClassID["my_helmet"] = 42, still registers the item; that number is how
    saves made before class names refer to it (AdvInv.LegacyID), and the item keeps it as its
    session number (the built-in items 100-127 and the compatible addons' 1000-1999 do).
--]]
AdvInv.Items = AdvInv.Items or {}
AdvInv.LegacyID = AdvInv.LegacyID or {}
AdvInv.ClassID = AdvInv.ClassID or {}
AdvInv.IDClass = AdvInv.IDClass or {}
AdvInv.DYNAMIC_ID_START = 20000 -- session numbers of the items registered by name only (given by the server)
function AdvInv.RegisterItem(class) AdvInv.Items[class] = true end
AdvInv.mountedGear = AdvInv.mountedGear or {}

if CLIENT then
    AdvInv.MountedWeps = AdvInv.MountedWeps or {}
end

--[[
    Returns the class name associated with the given ID
    @param itemID Unique ID
--]]
-- An item class's table, inherited fields included. scripted_ents.Get copies the whole base chain
-- at every call (costly in drawing and damage code): copied once per class, cleared when the item
-- list is built. READ ONLY: never write into it.
local tableCache = {}
function AdvInv.ClassTable(class)
    if not class then return end
    local t = tableCache[class]
    if t == nil then
        t = scripted_ents.GetStored(class) and scripted_ents.Get(class) or false
        tableCache[class] = t
    end
    return t or nil
end

function AdvInv.EntityTable(itemID)
    return AdvInv.ClassTable(AdvInv.IDClass[itemID])
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

-- Session numbers of the items registered by name only, as the server gave them (sent to each client).
AdvInv.ServerIDs = AdvInv.ServerIDs or {}

local function validLegacy(id)
    return isnumber(id) and id >= 2 and id < AdvInv.DYNAMIC_ID_START and math.floor(id) == id
end

-- Builds the session numbers once every addon has registered its items.
local function AdvInv_InitItems()
    tableCache = {}
    -- the older registration, AdvInv.ClassID[class] = number: the item, and how older saves name it
    for class, id in pairs(AdvInv.ClassID) do
        if validLegacy(id) and AdvInv.LegacyID[class] == nil then AdvInv.LegacyID[class] = id end
        AdvInv.Items[class] = true
    end
    AdvInv.ClassID = {}
    AdvInv.IDClass = {
        [0] = "advinv_null", -- no item slot
        [1] = "advinv_null", -- empty item slot
    }
    local classes = table.GetKeys(AdvInv.Items)
    table.sort(classes) -- the same class wins a number whatever the load order
    local byName = {}
    for _, class in ipairs(classes) do
        local id = AdvInv.LegacyID[class]
        if validLegacy(id) and not AdvInv.IDClass[id] then
            AdvInv.IDClass[id] = class
            AdvInv.ClassID[class] = id
        else
            if id ~= nil and AdvInv.IDClass[id] then
                ErrorNoHalt("[Advanced Inventory System] number " .. tostring(id) .. " is used by " .. AdvInv.IDClass[id] ..
                    " and " .. class .. ": " .. class .. " gets another one (its class name is its ID)\n")
            end
            byName[#byName + 1] = class
        end
    end
    -- items registered by name only: numbered by the server, in class order; clients take the server's numbers
    if SERVER then
        AdvInv.ServerIDs = {}
        for k, class in ipairs(byName) do AdvInv.ServerIDs[class] = AdvInv.DYNAMIC_ID_START + k - 1 end
    end
    for class, id in pairs(AdvInv.ServerIDs) do
        if AdvInv.Items[class] and not AdvInv.IDClass[id] then
            AdvInv.IDClass[id] = class
            AdvInv.ClassID[class] = id
        end
    end
    AdvInv.entityModels = {}

    hook.Call("AdvInv_InitItems")
    hook.Call("AdvInv_ItemsInitialized")
    AdvInv.EntitiesInitialized = true
end

hook.Add("InitPostEntity", "AdvInv_InitItems", AdvInv_InitItems)

-- The session numbers of the items registered by name only go from the server to each client: when
-- the client asks (once loaded: a message sent while it connects may be lost), and to all after a reload.
if SERVER then
    util.AddNetworkString("advinv_ids")
    function AdvInv.SendItemIDs(ply)
        net.Start("advinv_ids")
        net.WriteUInt(table.Count(AdvInv.ServerIDs), 16)
        for class, id in pairs(AdvInv.ServerIDs) do
            net.WriteString(class)
            net.WriteUInt(id, 16)
        end
        if ply then net.Send(ply) else net.Broadcast() end
    end
    local asked = {}
    net.Receive("advinv_ids", function(_, ply)
        if asked[ply] and asked[ply] > CurTime() - 5 then return end -- once in a while is plenty
        asked[ply] = CurTime()
        if AdvInv.EntitiesInitialized then AdvInv.SendItemIDs(ply) end
    end)
    hook.Add("PlayerDisconnected", "AdvInv_ItemIDs", function(ply) asked[ply] = nil end)
    hook.Add("AdvInv_ItemsInitialized", "AdvInv_ItemIDs", function() AdvInv.SendItemIDs() end)
else
    net.Receive("advinv_ids", function()
        local ids = {}
        for _ = 1, net.ReadUInt(16) do
            local class = net.ReadString()
            ids[class] = net.ReadUInt(16)
        end
        AdvInv.ServerIDs = ids
        if not AdvInv.EntitiesInitialized then return end -- used by the client's own init
        for class, id in pairs(ids) do
            local old = AdvInv.ClassID[class]
            if AdvInv.Items[class] and old ~= id then
                if old and AdvInv.IDClass[old] == class then AdvInv.IDClass[old] = nil end
                AdvInv.IDClass[id] = class
                AdvInv.ClassID[class] = id
            end
        end
        tableCache = {}
        hook.Call("AdvInv_ItemsInitialized")
    end)
    hook.Add("InitPostEntity", "AdvInv_AskItemIDs", function()
        timer.Simple(0, function()
            net.Start("advinv_ids")
            net.SendToServer()
        end)
    end)
end
