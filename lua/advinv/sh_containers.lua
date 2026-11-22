--[[
    Contenants façon Arma 3.

    Chaque objet a un encombrement (ENT.Mass, en points) ; chaque contenant a une capacité
    (ENT.MaxLoad, en points). Un contenant accepte un objet tant que la somme des encombrements
    ne dépasse pas sa capacité : deux chargeurs de pistolet ne prennent pas la place de deux
    chargeurs tambours.

    Contenants d'un joueur : la tenue (« Uniform », poches du treillis), le gilet (« Vest ») et le
    sac à dos (« Rucksack »). Une caisse ou un véhicule n'a qu'un contenant, « Storage ».

    Un objet rangé est une petite table : { id = ID de l'objet, r = munitions, a = blindage }.
    Generic items (sh_generic.lua) also have c = their class name; m = carry mode of a long gun.
      - r : munitions d'une boîte de munitions, ou du chargeur d'une arme rangée ;
      - a : points de blindage restants d'un casque ou d'un gilet rangé.
--]]
AdvInv = AdvInv or {}
local I = AdvInv

I.Config = I.Config or {}
local C = I.Config
-- Capacité des poches d'un joueur qui ne porte pas d'objet « tenue » (voir advinv_base_uniform).
C.DefaultUniformLoad = C.DefaultUniformLoad or 40
-- Capacité d'une caisse de ravitaillement et du coffre d'un véhicule (simfphys) sans ENT.MaxLoad.
C.CrateLoad = C.CrateLoad or 1000
C.VehicleLoad = C.VehicleLoad or 500
-- Distance maximale pour fouiller une caisse ou un véhicule (unités).
C.UseDistance = C.UseDistance or 200

-- Contenants et leur numéro réseau (3 bits).
I.CONTAINERS = { "Uniform", "Vest", "Rucksack", "Storage" }
I.PLAYER_CONTAINERS = { "Uniform", "Vest", "Rucksack" }
I.ContID = { Uniform = 1, Vest = 2, Rucksack = 3, Storage = 4 }
I.IDCont = { "Uniform", "Vest", "Rucksack", "Storage" }
I.ContainerNames = I.ContainerNamesLang -- names in the server's language (sh_lang.lua)

-- Classes qui servent de contenant « Storage ».
I.StorageClasses = I.StorageClasses or {
    advinv_crate = true,
    gmod_sent_vehicle_fphysics_base = true,
}

---------------------------------------------------------------- encombrement et capacité

-- Encombrement par défaut des objets qui ne déclarent pas ENT.Mass (objets d'autres addons),
-- selon leur classe de base (la plus précise d'abord).
local DEFAULT_MASS = {
    { "advinv_base_ammobox", 8 },
    { "advinv_base_helmet", 40 },
    { "advinv_base_pocketvest", 80 },
    { "advinv_base_vest", 80 },
    { "advinv_base_rucksack", 30 },
    { "advinv_base_uniform", 30 },
    { "advinv_base_gear", 10 },
}
local WEAPON_MASS = { PrimaryWep = 80, SecondaryWep = 20, RocketLauncher = 100 }
-- Ancien système à places : un contenant qui ne déclare que ENT.Capacity (nombre de places)
-- reçoit cette capacité par place.
local LOAD_PER_OLD_SLOT = 16

local massCache, loadCache = {}, {}

local function entTable(id)
    if not id or id <= 1 then return end
    local class = AdvInv.IDClass and AdvInv.IDClass[id]
    return class and scripted_ents.GetStored(class) and scripted_ents.Get(class) or nil
end
I.EntTable = entTable

-- Encombrement d'un objet (points). c: class of a generic item.
function I.ItemMass(id, c)
    if I.IsGeneric and I.IsGeneric(id) then
        local d = I.DefTable(id, c)
        return d and d.Mass or 10
    end
    if massCache[id] then return massCache[id] end
    local t = entTable(id)
    if not t then return 0 end
    local m = t.Mass
    if not m and t.AdvInvCategory and WEAPON_MASS[t.AdvInvCategory] then m = WEAPON_MASS[t.AdvInvCategory] end
    if not m then
        for _, d in ipairs(DEFAULT_MASS) do
            if scripted_ents.IsBasedOn(t.ClassName, d[1]) or t.ClassName == d[1] then m = d[2] break end
        end
    end
    m = m or 10
    massCache[id] = m
    return m
end

-- Capacité d'un objet contenant (sac, gilet à poches, tenue), 0 si ce n'est pas un contenant.
function I.ItemMaxLoad(id)
    if loadCache[id] then return loadCache[id] end
    local t = entTable(id)
    local load = 0
    if t then
        if t.MaxLoad then
            load = t.MaxLoad
        elseif t.Capacity and (scripted_ents.IsBasedOn(t.ClassName, "advinv_base_rucksack")
            or scripted_ents.IsBasedOn(t.ClassName, "advinv_base_pocketvest")) then
            load = t.Capacity * LOAD_PER_OLD_SLOT
        end
    end
    loadCache[id] = load
    return load
end

-- Caractéristiques d'un objet utiles à l'inventaire (mises en cache).
local infoCache = {}
local EMPTY_INFO = { mass = 0, maxLoad = 0 }
function I.Info(id, c)
    local generic = I.IsGeneric and I.IsGeneric(id)
    local key = generic and (id .. ":" .. tostring(c)) or id
    local info = infoCache[key]
    if info then return info end
    local t = generic and I.DefTable(id, c) or entTable(id)
    if not t then return EMPTY_INFO end
    local class = t.ClassName
    info = {
        class = class,
        name = t.PrintName or class,
        cat = t.AdvInvCategory,
        model = t.Model,
        skin = t.skin,
        generic = generic or nil,
        entityClass = t.EntityClass,
        mass = I.ItemMass(id, c),
        maxLoad = I.ItemMaxLoad(id),
        isBox = scripted_ents.IsBasedOn(class, "advinv_base_ammobox") or nil,
        isWeapon = (t.WeaponClass and t.AdvInvCategory and table.HasValue(AdvInv.WeaponCat, t.AdvInvCategory)) or nil,
    }
    if info.isBox then
        info.ammo = t.Ammo
        info.boxRounds = t.Capacity or t.Rounds or 0
    end
    if info.isWeapon then
        info.weaponClass = t.WeaponClass
        info.clipSize = t.ClipSize
    end
    if t.Armor and t.Armor > 0 and AdvInv.GearCat[info.cat or ""] then info.armor = t.Armor end
    info.rarity = I.Rarity and I.Rarity(t) or nil
    info.isContainer = info.maxLoad > 0 or nil
    infoCache[key] = info
    return info
end

-- Les caches sont vidés quand la liste des objets est (re)construite.
hook.Add("AdvInv_ItemsInitialized", "AdvInv_MassCache", function()
    massCache, loadCache, infoCache = {}, {}, {}
end)

-- Contenant qui accueille un objet de cette catégorie quand on l'équipe.
I.ContainerOfCategory = { Uniform = "Uniform", Vest = "Vest", Rucksack = "Rucksack" }

-- A dead player's body (sv_death.lua): it holds his equipment and containers like a player.
function I.IsBody(ent)
    return IsValid(ent) and ent:GetNWBool("AdvInvBody") or false
end

function I.IsStorage(ent)
    return IsValid(ent) and (I.StorageClasses[ent:GetClass()] or ent.AdvInvStorage) and true or false
end

-- Le porteur a-t-il ce contenant ?
function I.HasContainer(holder, cont)
    if not IsValid(holder) then return false end
    if cont == "Storage" then return I.IsStorage(holder) end
    if not (holder:IsPlayer() or I.IsBody(holder)) then return false end
    if cont == "Uniform" then return true end
    return I.ItemMaxLoad(holder:GetNW2Int(cont)) > 0
end

-- Capacité d'un contenant du porteur (points).
function I.MaxLoad(holder, cont)
    if not I.HasContainer(holder, cont) then return 0 end
    if cont == "Storage" then
        local cap = holder:GetNWInt("AdvInvCap", 0) -- set in the storage settings (sv_storage.lua)
        if cap > 0 then return cap end
        return holder.MaxLoad or (holder:GetClass() == "advinv_crate" and C.CrateLoad) or C.VehicleLoad
    end
    if cont == "Uniform" then
        local id = holder:GetNW2Int("Uniform")
        local load = id > 1 and I.ItemMaxLoad(id) or 0
        return load > 0 and load or C.DefaultUniformLoad
    end
    return I.ItemMaxLoad(holder:GetNW2Int(cont))
end

-- Encombrement total d'une liste d'objets.
function I.ItemsLoad(items)
    local sum = 0
    for _, it in ipairs(items or {}) do sum = sum + I.ItemMass(it.id, it.c) end
    return sum
end

---------------------------------------------------------------- format réseau

I.NET_ID_BITS = 7       -- ID des objets (2 à 127)
I.NET_ROUNDS_BITS = 16  -- munitions d'un objet
I.NET_ARMOR_BITS = 8    -- blindage d'un objet (0 à 255)
I.NET_COUNT_BITS = 8    -- objets par contenant (255 au maximum)

function I.WriteItems(items)
    net.WriteUInt(math.min(#items, 255), I.NET_COUNT_BITS)
    for k = 1, math.min(#items, 255) do
        local it = items[k]
        net.WriteUInt(it.id, I.NET_ID_BITS)
        net.WriteUInt(math.Clamp(math.floor(it.r or 0), 0, 65535), I.NET_ROUNDS_BITS)
        net.WriteUInt(math.Clamp(math.floor(it.a or 0), 0, 255), I.NET_ARMOR_BITS)
        net.WriteUInt(math.Clamp(math.floor(it.m or 0), 0, 7), 3) -- carry mode of a long gun (0: none)
        if I.IsGeneric(it.id) then net.WriteString(it.c or "") end -- class of a generic item
        net.WriteBool(it.x ~= nil) -- extra weapon data (attachments)
        if it.x ~= nil then net.WriteString(it.x) end
    end
end

function I.ReadItems()
    local items = {}
    for k = 1, net.ReadUInt(I.NET_COUNT_BITS) do
        items[k] = { id = net.ReadUInt(I.NET_ID_BITS), r = net.ReadUInt(I.NET_ROUNDS_BITS), a = net.ReadUInt(I.NET_ARMOR_BITS) }
        local m = net.ReadUInt(3)
        if m > 0 then items[k].m = m end
        if I.IsGeneric(items[k].id) then items[k].c = net.ReadString() end
        if net.ReadBool() then items[k].x = net.ReadString() end
    end
    return items
end

-- Actions demandées par un client (4 bits).
I.ACT_BITS = 4
I.ACT = { MOVE = 1, DROP = 2, EQUIP = 3, UNEQUIP = 4, OPEN = 5, CLOSE = 6, CARRY = 7, ADMIN = 8, USE = 9, UNLOAD = 10, SEARCH = 11, SPLIT = 12, CRAFT = 13, LOOT = 14 }

-- Identical items (same object, same ammo, same armor) are shown as one stack.
function I.StackKey(item)
    return item.id .. ":" .. (item.r or 0) .. ":" .. (item.a or 0) .. ":" .. (item.m or 0) .. ":" .. (item.c or "") .. ":" .. (item.x or "")
end

---------------------------------------------------------------- contenu vu par le client

if CLIENT then
    -- I.Seen[entIndex][cont] = liste d'objets reçue du serveur
    I.Seen = I.Seen or {}

    -- Contenu d'un contenant tel que le serveur l'a envoyé.
    function I.Get(holder, cont)
        local byHolder = I.Seen[IsValid(holder) and holder:EntIndex() or -1]
        return byHolder and byHolder[cont] or {}
    end

    net.Receive("advinv_sync", function()
        local holder = net.ReadEntity()
        local idx = net.ReadUInt(14)
        local cont = I.IDCont[net.ReadUInt(3)]
        local items = I.ReadItems()
        I.Seen[idx] = I.Seen[idx] or {}
        I.Seen[idx][cont] = items
        hook.Run("AdvInv_Changed", holder, cont)
    end)

    net.Receive("advinv_msg", function()
        local text = net.ReadString()
        notification.AddLegacy(text, NOTIFY_ERROR, 3)
        surface.PlaySound("buttons/button10.wav")
    end)

    -- Demande au serveur une action sur l'inventaire.
    function I.Act(action, fn)
        net.Start("advinv_act")
        net.WriteUInt(action, I.ACT_BITS)
        if fn then fn() end
        net.SendToServer()
    end
end
