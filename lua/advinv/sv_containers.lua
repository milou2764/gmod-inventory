--[[
    Inventaire à capacité, côté serveur : le serveur seul décide.

    Contenu d'un porteur (joueur, caisse, véhicule) : holder.AdvInvData[contenant] = liste d'objets
    { id, r, a } (voir sh_containers.lua). Les clients reçoivent le contenu qui les concerne
    (le leur, et celui d'une caisse ou d'un véhicule qu'ils fouillent) et demandent des actions
    (déplacer, déposer, équiper, retirer) que le serveur vérifie avant de les faire.

    Munitions de réserve : ce sont les boîtes de munitions rangées dans les contenants du joueur.
    La réserve du joueur est tenue égale à leur total ; recharger vide les boîtes (les moins
    pleines d'abord), une boîte vide disparaît.
--]]
local I = AdvInv
local C = I.Config

util.AddNetworkString("advinv_sync")
util.AddNetworkString("advinv_act")
util.AddNetworkString("advinv_msg")

local function tell(ply, text)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    net.Start("advinv_msg")
    net.WriteString(text)
    net.Send(ply)
end
I.Tell = tell

---------------------------------------------------------------- contenu

--[[
    Contents of a container. A storage can keep its contents in a keyed store instead
    (sv_storage.lua: crates sharing a name, personal crates, banks): I.StoreKey(holder, who) gives
    the key; who is the player concerned (default: the player whose action is running, I.Actor).
--]]
I.Stores = I.Stores or {}

function I.Get(holder, cont, who)
    local key = I.StoreKey and I.StoreKey(holder, who or I.Actor)
    if key then
        local s = I.Stores[key] or (I.LoadStore and I.LoadStore(key)) or {}
        I.Stores[key] = s
        s[cont] = s[cont] or {}
        return s[cont]
    end
    holder.AdvInvData = holder.AdvInvData or {}
    local items = holder.AdvInvData[cont]
    if not items then
        items = {}
        holder.AdvInvData[cont] = items
    end
    return items
end

function I.Set(holder, cont, items, who)
    local key = I.StoreKey and I.StoreKey(holder, who or I.Actor)
    if key then
        I.Stores[key] = I.Stores[key] or {}
        I.Stores[key][cont] = items or {}
        I.MarkDirty(holder, cont, who)
        return
    end
    holder.AdvInvData = holder.AdvInvData or {}
    holder.AdvInvData[cont] = items or {}
    I.MarkDirty(holder, cont)
end

function I.Used(holder, cont) return I.ItemsLoad(I.Get(holder, cont)) end
function I.Free(holder, cont) return I.MaxLoad(holder, cont) - I.Used(holder, cont) end

I.MAX_ITEMS = 255 -- items in one container (sent with 8 bits)
function I.CanFit(holder, cont, id, c)
    return I.HasContainer(holder, cont) and #I.Get(holder, cont) < I.MAX_ITEMS and I.ItemMass(id, c) <= I.Free(holder, cont)
end

-- Last resort for what must stay with a player (a job's item, one his drop rules keep): his pockets
-- over their load, but never past the 255 items a container shows (else unseen, never taken out);
-- past that, a job's item is gone (the next loadout gives it again), anything else falls at his feet.
function I.ForceStore(ply, item)
    local pockets = I.Get(ply, "Uniform")
    if #pockets < I.MAX_ITEMS then
        pockets[#pockets + 1] = item
        I.MarkDirty(ply, "Uniform")
        return true
    end
    if not item.j then I.SpawnItem(item, I.DropPos(ply)) end
    return false
end

-- Contenants d'un porteur, dans l'ordre où l'on range (comme Arma : tenue, gilet, sac).
function I.ContainersOf(holder)
    if holder:IsPlayer() or I.IsBody(holder) then return I.PLAYER_CONTAINERS end
    return { "Storage" }
end

-- Range un objet dans le premier contenant qui a la place ; renvoie ce contenant, ou nil.
function I.Store(holder, item, order)
    for _, cont in ipairs(order or I.ContainersOf(holder)) do
        if I.CanFit(holder, cont, item.id, item.c) then
            table.insert(I.Get(holder, cont), item)
            I.MarkDirty(holder, cont)
            return cont
        end
    end
end

---------------------------------------------------------------- synchronisation

local dirty, dirtyKeys = {}, {}
function I.MarkDirty(holder, cont, who)
    if not IsValid(holder) then return end
    local key = I.StoreKey and I.StoreKey(holder, who or I.Actor)
    if key then -- every storage showing this store, to each viewer who sees it
        dirtyKeys[key] = dirtyKeys[key] or {}
        dirtyKeys[key][cont] = true
        if I.StoreChanged then I.StoreChanged(key) end
        return
    end
    dirty[holder] = dirty[holder] or {}
    dirty[holder][cont] = true
    if holder.AdvInvUID and I.StorageChanged then I.StorageChanged(holder) end -- permanent storage
end

-- Tous les contenants d'un porteur seront renvoyés (chargement, réapparition).
function I.MarkAllDirty(holder)
    for _, cont in ipairs(I.ContainersOf(holder)) do I.MarkDirty(holder, cont) end
end

local function stillViewing(ply, holder)
    if not holder:IsPlayer() then return true end -- crates, bodies: the viewer timer checks them
    return (ply.AdvInvAdminView == holder and I.IsAdmin(ply)) or (I.IsSearching and I.IsSearching(ply, holder)) or false
end

local function recipients(holder)
    local rf = RecipientFilter()
    if holder:IsPlayer() then rf:AddPlayer(holder) end
    local viewers = holder.AdvInvViewers
    for ply in pairs(viewers or {}) do
        if IsValid(ply) and stillViewing(ply, holder) then rf:AddPlayer(ply)
        else
            viewers[ply] = nil
            -- (told, else his window stayed open: the search's own end found him already gone)
            if IsValid(ply) and I.EndView then I.EndView(holder, ply) end
        end
    end
    return rf
end

-- who: the player whose store is sent (keyed stores: send to that player only).
function I.SendContainer(holder, cont, rf, who)
    if not who and I.IsKeyed and I.IsKeyed(holder) then
        -- a keyed store: each viewer gets their own
        for ply in pairs(holder.AdvInvViewers or {}) do
            if IsValid(ply) then I.SendContainer(holder, cont, ply, ply) end
        end
        return
    end
    net.Start("advinv_sync")
    net.WriteEntity(holder)
    net.WriteUInt(holder:EntIndex(), 14)
    net.WriteUInt(I.ContID[cont], 3)
    I.WriteItems(I.Get(holder, cont, who))
    net.Send(rf or recipients(holder))
end

hook.Add("Think", "AdvInv_Sync", function()
    if next(dirtyKeys) ~= nil then
        local dk = dirtyKeys
        dirtyKeys = {}
        for _, class in ipairs(table.GetKeys(I.StorageClasses)) do
            for _, ent in ipairs(ents.FindByClass(class)) do
                for ply in pairs(ent.AdvInvViewers or {}) do
                    local key = IsValid(ply) and I.StoreKey(ent, ply)
                    if key and dk[key] then
                        for cont in pairs(dk[key]) do I.SendContainer(ent, cont, ply, ply) end
                    end
                end
            end
        end
    end
    if next(dirty) == nil then return end
    local d = dirty
    dirty = {}
    for holder, conts in pairs(d) do
        if IsValid(holder) then
            local rf = recipients(holder)
            for cont in pairs(conts) do I.SendContainer(holder, cont, rf) end
            if holder:IsPlayer() then
                I.SyncAmmo(holder)
                I.UpdateCarriedLoad(holder)
            end
        end
    end
end)

---------------------------------------------------------------- munitions de réserve

local settingAmmo = {}

-- Ammo taken away all at once by other code (DarkRP arrest and job change, admin tools, DarkRP's
-- /drop): the boxes stay in the inventory and the reserve comes back from them. (RemoveAmmo is not
-- guarded: weapons without a magazine and grenades fire through it.)
local guardTick = {}
function I.GuardAmmo(ply) guardTick[ply] = engine.TickCount() + 2 end
local function guarded(ply) return (guardTick[ply] or 0) >= engine.TickCount() end

local function sameAmmo(a, b) return a and b and string.lower(a) == string.lower(b) end

-- Ammo picked up the game's way (advinv_pickup_entities 0, or an ammo entity given straight to the
-- player): its rounds go into the reserve, and the reserve is the boxes: they become boxes, else the
-- next sync would erase them. Only gains of that ammo type, in the next ticks (sv_generic.lua).
local gainAllowed = {}
function I.AllowAmmoGain(ply, ammo)
    if isstring(ammo) and ammo ~= "" then gainAllowed[ply] = { tick = engine.TickCount() + 2, ammo = ammo } end
end

-- Weapon code wrapped to make its own reserve gains boxes (sv_arccw.lua, sv_cw2.lua): while it runs,
-- the gain branch below leaves those gains to it, and afterwards a window opened for the same type
-- (a touched ammo entity) is closed, or the same rounds would become boxes twice.
local converting = {}
function I.BeginGainConversion(ply) converting[ply] = (converting[ply] or 0) + 1 end
function I.EndGainConversion(ply, types)
    converting[ply] = (converting[ply] or 1) > 1 and converting[ply] - 1 or nil
    local g = gainAllowed[ply]
    if g and types then
        for ammo in pairs(types) do
            if sameAmmo(g.ammo, ammo) then gainAllowed[ply] = nil break end
        end
    end
end

-- Réserve du joueur = total des boîtes rangées dans ses contenants.
-- The weapon in hand for the ammo rules: during a switch's tick, the one being switched to (its
-- Deploy runs in that tick, before the active weapon is read again: an ArcCW auto reload or a
-- Sandstorm launcher takes from the reserve right there)
local function held(ply)
    local s = ply.AdvInvSwitchTo
    if s and s.tick == engine.TickCount() and IsValid(s.wep) then return s.wep end
    return ply:GetActiveWeapon()
end
I.HeldWeapon = held

function I.SyncAmmo(ply)
    if not ply:Alive() then return end
    if I.ReconcileGrenades then I.ReconcileGrenades(ply) end -- throws first (sv_grenades.lua)
    local totals = {}
    local grenadeOf = I.GrenadeOfAmmo
    -- the job's boxes of rounds, while job items are bound: in the reserve only with the job's weapon
    -- in hand (else a personal weapon of the same calibre loaded them, and its rounds could leave as
    -- ordinary ones); grenades are items of their own (sv_grenades.lua)
    local jobRounds = not (I.JobItemsBound and I.JobItemsBound()) or (I.IsBoundJobWeapon and I.IsBoundJobWeapon(ply, held(ply)))
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        for _, it in ipairs(I.Get(ply, cont)) do
            local info = I.Info(it.id, it.c)
            if info.isBox and info.ammo then
                local key = string.lower(info.ammo)
                local counted = jobRounds or not it.j or (grenadeOf and grenadeOf(info.ammo))
                totals[key] = (totals[key] or 0) + (counted and (it.r or 0) or 0)
                ply.AdvInvAmmoTypes = ply.AdvInvAmmoTypes or {}
                ply.AdvInvAmmoTypes[key] = info.ammo
            end
        end
    end
    -- (types he never held a box of are left alone: a gamemode's loadout reserve, Sandbox's spawn
    -- ammo, a DarkRP job's SetAmmo stay usable as without the inventory)
    local grenades = I.GrenadeTypes and I.GrenadeTypes() or {}
    if next(grenades) then
        ply.AdvInvAmmoTypes = ply.AdvInvAmmoTypes or {}
        for key, ammo in pairs(grenades) do ply.AdvInvAmmoTypes[key] = ammo end
    end
    local emptyGrenades = {}
    settingAmmo[ply] = true
    for key, ammo in pairs(ply.AdvInvAmmoTypes or {}) do
        if game.GetAmmoID(ammo) ~= -1 then
            local want = totals[key] or 0
            if grenades[key] then
                -- grenades: the one loaded in the weapon is an item too
                if want == 0 then emptyGrenades[key] = true end
                local inside = I.GrenadesLoaded(ply, ammo)
                if inside > want then
                    I.UnloadGrenades(ply, ammo, inside - want)
                    inside = want
                end
                want = want - inside
            end
            if ply:GetAmmoCount(ammo) ~= want then ply:SetAmmo(want, ammo) end
        end
    end
    settingAmmo[ply] = nil
    if I.GrenadesSynced then I.GrenadesSynced(ply, emptyGrenades) end
end

-- Another weapon in hand: the reserve is built again for it at once (the job's boxes count only with
-- the job's weapon, I.SyncAmmo), before its Deploy, and again a tick later (a switch another addon
-- blocked, or delayed by a holster animation).
hook.Add("PlayerSwitchWeapon", "AdvInv_JobRounds", function(ply, _, newWep)
    if not (ply.AdvInvJobSlot and next(ply.AdvInvJobSlot) and I.JobItemsBound and I.JobItemsBound()) then return end
    ply.AdvInvSwitchTo = { wep = newWep, tick = engine.TickCount() }
    I.SyncAmmo(ply)
    timer.Simple(0, function() if IsValid(ply) then I.SyncAmmo(ply) end end)
end)

-- Recharger (ou tout ce qui baisse la réserve) vide les boîtes, les moins pleines d'abord.
hook.Add("PlayerAmmoChanged", "AdvInv_Ammo", function(ply, ammoID, oldCount, newCount)
    if settingAmmo[ply] or guarded(ply) or newCount == oldCount or not ply:Alive() then return end
    local ammo = game.GetAmmoName(ammoID)
    if I.GrenadeOfAmmo and I.GrenadeOfAmmo(ammo) then return end -- grenades: sv_grenades.lua
    if newCount > oldCount then
        if converting[ply] then return end -- (the wrapper makes it boxes)
        local g = gainAllowed[ply]
        if g and g.tick >= engine.TickCount() and sameAmmo(g.ammo, ammo) then
            I.GiveRounds(ply, ammo, newCount - oldCount)
        else
            -- rounds from nowhere (another addon's GiveAmmo, a weapon's default reserve): the next
            -- sync takes them back now, not at some later inventory change (they could be fired or
            -- loaded meanwhile); only for types the boxes rule (else an addon topping a reserve up
            -- every tick would resend his containers every tick, for nothing)
            if ply.AdvInvAmmoTypes and ply.AdvInvAmmoTypes[string.lower(ammo)] then I.MarkDirty(ply, "Uniform") end
        end
        return
    end
    local need = oldCount - newCount
    local boxes = {}
    local preferJob = I.IsBoundJobWeapon and I.IsBoundJobWeapon(ply, held(ply)) or false
    local bound = I.JobItemsBound and I.JobItemsBound()
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        for _, it in ipairs(I.Get(ply, cont)) do
            -- (the job's boxes aren't in the reserve without the job's weapon in hand: I.SyncAmmo)
            if I.Info(it.id, it.c).isBox and sameAmmo(I.Info(it.id, it.c).ammo, ammo) and not (it.j and bound and not preferJob) then
                boxes[#boxes + 1] = { cont = cont, it = it }
            end
        end
    end
    -- the job's weapon takes the job's boxes first
    table.sort(boxes, function(a, b)
        local ja, jb = (a.it.j and true or false) == preferJob, (b.it.j and true or false) == preferJob
        if ja ~= jb then return ja end
        return (a.it.r or 0) < (b.it.r or 0)
    end)
    for _, b in ipairs(boxes) do
        if need <= 0 then break end
        local take = math.min(need, b.it.r or 0)
        b.it.r = (b.it.r or 0) - take
        need = need - take
        I.MarkDirty(ply, b.cont)
    end
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        local items = I.Get(ply, cont)
        for k = #items, 1, -1 do
            if I.Info(items[k].id, items[k].c).isBox and (items[k].r or 0) <= 0 then
                table.remove(items, k)
                I.MarkDirty(ply, cont)
            end
        end
    end
end)

---------------------------------------------------------------- charge portée

-- Encombrement total porté : contenu des contenants + objets équipés.
function I.CarriedLoad(ply)
    local sum = 0
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do sum = sum + I.Used(ply, cont) end
    for cat in pairs(AdvInv.GearCat) do
        local id = ply:GetNW2Int(cat)
        if id > 1 then sum = sum + I.ItemMass(id) end
    end
    for _, cat in ipairs(AdvInv.WeaponCat) do
        local id, c = I.SlotRef(ply, cat)
        if id > 1 then sum = sum + I.ItemMass(id, c) end
    end
    return sum
end

function I.UpdateCarriedLoad(ply)
    ply:SetNWInt("AdvInvLoad", I.CarriedLoad(ply))
end

---------------------------------------------------------------- objets au sol

local function isWeaponCat(cat) return cat and table.HasValue(AdvInv.WeaponCat, cat) end

-- Objet rangé correspondant à une entité au sol (registered item, or a weapon / whitelisted entity:
-- sv_generic.lua).
function I.ItemFromEntity(ent)
    if not IsValid(ent) or ent.AdvInvStored or (ent.IsMarkedForDeletion and ent:IsMarkedForDeletion()) then return end
    if istable(ent.DarkRPItem) and (tonumber(ent.DarkRPItem.max) or 0) > 0 then return end -- DarkRP's limit
    local id = AdvInv.ClassID[ent:GetClass()]
    if not id or id <= 1 or I.IsGeneric(id) then return I.GenericItemFromEntity and I.GenericItemFromEntity(ent) end
    local info = I.Info(id)
    local item = { id = id, r = 0, a = 0 }
    if info.isBox or info.isWeapon then item.r = math.max(math.floor(ent.Rounds or 0), 0) end
    if info.isWeapon and ent.CarryMode then item.m = ent.CarryMode end -- its carry mode goes with it
    item.x = ent.AdvInvExtra -- and its attachments (or the state an addon keeps with it)
    if info.armor then item.a = math.max(math.floor(ent.Armor or info.armor), 0) end
    return item
end

-- Items put on the ground by the inventory (dropped, swapped, a dead player's weapon...) disappear
-- after advinv_ground_item_time seconds (0: never). Picked up, stored or held: no longer counted.
local groundTime = CreateConVar("advinv_ground_item_time", "600", { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Seconds before an item dropped on the ground disappears (0: never)", 0)
I.GroundItems = I.GroundItems or setmetatable({}, { __mode = "k" })
timer.Create("AdvInv_GroundItems", 5, 0, function()
    local life = groundTime:GetFloat()
    local now = CurTime()
    for ent, since in pairs(I.GroundItems) do
        if not IsValid(ent) or ent.AdvInvStored or IsValid(ent:GetOwner()) or IsValid(ent:GetParent()) then
            I.GroundItems[ent] = nil
        elseif life > 0 and now - since >= life then
            I.GroundItems[ent] = nil
            ent:Remove()
        end
    end
end)

-- Fait apparaître un objet au sol ; contents = contenu d'un sac ou d'un gilet.
-- count: identical items making one stack on the ground (NW int "AdvInvCount").
function I.SpawnItem(item, pos, contents, count)
    local ent
    if I.IsGeneric(item.id) then
        ent = I.SpawnGeneric and I.SpawnGeneric(item, pos)
    else
        local class = AdvInv.IDClass[item.id]
        if not class then return end
        ent = ents.Create(class)
        if not IsValid(ent) then return end
        local info = I.Info(item.id)
        if info.isBox or info.isWeapon then ent.Rounds = item.r or 0 end
        if info.isWeapon then ent.CarryMode = item.m end
        ent.AdvInvExtra = item.x -- (attachments, or the state an addon keeps with the item)
        if info.armor then ent.Armor = item.a or 0 end
        if contents and #contents > 0 then ent.AdvInvContents = contents end
        ent:SetPos(pos)
        ent:Spawn()
    end
    if not IsValid(ent) then return end
    I.GroundItems[ent] = CurTime() -- disappears after advinv_ground_item_time
    ent:SetNWInt("AdvInvRounds", item.r or 0) -- shown when looking at it (cl_ground.lua)
    if count and count > 1 then ent:SetNWInt("AdvInvCount", count) end
    if not (contents and #contents > 0) then ent.AdvInvStackKey = I.StackKey(item) end
    return ent
end

-- How many items a ground entity holds (a stack, or DarkRP's spawned_weapon amount).
function I.GroundCount(ent)
    if ent:GetClass() == "spawned_weapon" and ent.Getamount then return math.max(ent:Getamount() or 1, 1) end
    return math.max(ent:GetNWInt("AdvInvCount", 1), 1)
end

-- Takes n items from a ground stack (the entity goes when it is empty).
function I.TakeFromGround(ent, n)
    if not IsValid(ent) or n <= 0 then return end
    local count = I.GroundCount(ent)
    if ent:GetClass() == "spawned_weapon" and ent.Setamount and n < count then
        ent:Setamount(count - n)
        return
    end
    if n >= count then
        ent.AdvInvStored = true
        ent:Remove()
    else
        ent:SetNWInt("AdvInvCount", count - n)
    end
end

-- Drops n identical items at pos: onto an identical stack lying there, else as a new stack
-- (generic weapons are real weapons: one entity each).
function I.DropStack(item, n, pos)
    if n <= 0 then return end
    if item.id == I.GENERIC_WEAPON then
        for _ = 1, n do I.SpawnItem(item, pos) end
        return
    end
    local key = I.StackKey(item)
    for _, e in ipairs(ents.FindInSphere(pos, 48)) do
        if e.AdvInvStackKey == key and not e.AdvInvStored and not IsValid(e:GetOwner())
            and not util.TraceLine({ start = pos, endpos = e:WorldSpaceCenter(), mask = MASK_SOLID_BRUSHONLY }).Hit then
            e:SetNWInt("AdvInvCount", math.max(e:GetNWInt("AdvInvCount", 1), 1) + n)
            if I.GroundItems[e] then I.GroundItems[e] = CurTime() end -- the stack starts again
            return e
        end
    end
    return I.SpawnItem(item, pos, nil, n)
end

-- Point devant le joueur où poser un objet.
function I.DropPos(ply)
    local start = ply:EyePos()
    local tr = util.TraceLine({ start = start, endpos = start + ply:GetAimVector() * 40, filter = ply })
    return tr.HitPos + tr.HitNormal * 6 - Vector(0, 0, 10)
end

---------------------------------------------------------------- équiper / retirer

local function slotID(ply, cat)
    if isWeaponCat(cat) then return ply:GetNWInt(cat) end
    return ply:GetNW2Int(cat)
end
I.SlotID = slotID

local SLOT_NAMES = I.SlotYour -- "your helmet"... in the server's language (sh_lang.lua)

-- Équipe un objet sur le joueur. contents : contenu d'un sac ou d'un gilet ramassé au sol.
-- Renvoie true, ou false et la raison.
function I.Equip(ply, item, contents)
    local info = I.Info(item.id, item.c)
    local cat = info.cat
    if not cat or not (AdvInv.GearCat[cat] or isWeaponCat(cat)) then return false, I.L("msg_not_equipable") end
    if slotID(ply, cat) > 1 then return false, I.L("msg_remove_first", SLOT_NAMES[cat] or cat) end
    -- the playermodel's own headgear, vest or backpack is part of its mesh (sh_modelgear.lua): nothing goes over it
    local builtinMsg = I.GearBuiltInMessages and I.GearBuiltInMessages[cat]
    if builtinMsg and I.HasBuiltInGear(ply, cat) then return false, I.L(builtinMsg) end

    if info.isWeapon then
        local carryOK, carryWhy = I.CarryEquipCheck(ply, cat, item) -- a place to carry it
        if not carryOK then return false, carryWhy end
        local wep = ply:GetWeapon(info.weaponClass)
        if not IsValid(wep) then
            -- arme sans chargeur (lance-roquettes HL2) : aucune munition offerte
            wep = ply:Give(info.weaponClass, true) -- no ammo: the magazine is set below, the reserve is the boxes
        end
        -- also a copy he already held (a job's loadout): the slot was empty, so its launcher round is
        -- not the item's, and taking it off later would make it a box
        if I.EmptyUnderbarrel then I.EmptyUnderbarrel(wep) end
        if IsValid(wep) and wep:GetMaxClip1() > 0 then wep:SetClip1(item.r or 0) end
        if IsValid(wep) and I.ApplyWeaponExtra then I.ApplyWeaponExtra(wep, item.x) end
        ply.AdvInvSlotWep = ply.AdvInvSlotWep or {}
        ply.AdvInvSlotWep[cat] = IsValid(wep) and wep or nil -- the slot's own weapon (I.GiveWeapons)
        ply.AdvInvSlotExtra = ply.AdvInvSlotExtra or {}
        ply.AdvInvSlotExtra[cat] = item.x
        ply.AdvInvJobSlot = ply.AdvInvJobSlot or {}
        ply.AdvInvJobSlot[cat] = item.j or nil -- a job's weapon (sv_darkrp.lua)
        ply:SetNWString(cat .. "Class", I.IsGeneric(item.id) and item.c or "")
        ply:SetNWInt(cat, item.id)
        ply:SetNWInt(cat .. "Rounds", item.r or 0)
        I.MarkDirty(ply, "Uniform") -- réserve recalculée (Give peut en avoir ajouté)
        I.CarryOnEquip(ply, cat, item)
        I.ValidateCarry(ply, true, cat) -- the new weapon gives way to the ones already carried
        return true
    end

    local t = I.EntTable(item.id)
    if t and t.CanBeEquipped and not t:CanBeEquipped(ply) then return false end
    local carryOK, carryWhy = I.CarryGearCheck(ply, item.id, cat) -- a backpack over a rifle carried on the back...
    if not carryOK then return false, carryWhy end
    if cat == "Uniform" then
        local newLoad = info.maxLoad > 0 and info.maxLoad or C.DefaultUniformLoad
        if I.Used(ply, "Uniform") > newLoad then return false, I.L("msg_pockets_too_full") end
    end
    ply:SetNW2Int(cat, item.id)
    if info.armor then ply:SetNWInt(cat .. "Armor", item.a or 0) end -- HelmetArmor, VestArmor...
    -- state an addon keeps with the item (item.x, a string): worn with it, given back when taken off
    ply.AdvInvSlotExtra = ply.AdvInvSlotExtra or {}
    ply.AdvInvSlotExtra[cat] = item.x
    if cat == "Vest" or cat == "Rucksack" then I.Set(ply, cat, contents or {}) end
    I.MarkDirty(ply, "Uniform")
    I.ValidateCarry(ply, true) -- gear may block the zone a carried weapon uses
    hook.Run("AdvInv_GearEquipped", ply, cat, item)
    return true
end

-- Peut-on retirer cet objet équipé ? (la tenue garde ses poches : elles doivent tenir sans elle)
function I.CanTakeOff(ply, cat)
    if slotID(ply, cat) <= 1 then return false end
    if cat == "Uniform" and I.Used(ply, "Uniform") > C.DefaultUniformLoad then
        return false, I.L("msg_empty_pockets")
    end
    return true
end

-- Retire un objet équipé ; renvoie l'objet rangé et, pour un sac ou un gilet, son contenu.
function I.TakeOff(ply, cat)
    local id, c = I.SlotRef(ply, cat)
    if id <= 1 then return end
    local info = I.Info(id, c)
    local item = { id = id, r = 0, a = 0, c = c }
    if isWeaponCat(cat) then
        local wep = info.weaponClass and ply:GetWeapon(info.weaponClass)
        item.r = IsValid(wep) and math.max(wep:Clip1(), 0) or ply:GetNWInt(cat .. "Rounds")
        -- attachments: from the weapon, else those kept when it was taken away (sv_inventory.lua)
        if IsValid(wep) then item.x = I.WeaponExtra(wep) elseif ply.AdvInvSlotExtra then item.x = ply.AdvInvSlotExtra[cat] end
        if ply.AdvInvSlotExtra then ply.AdvInvSlotExtra[cat] = nil end
        if ply.AdvInvJobSlot and ply.AdvInvJobSlot[cat] then
            item.j = true
            ply.AdvInvJobSlot[cat] = nil
        end
        if IsValid(wep) and I.UnloadUnderbarrel then I.UnloadUnderbarrel(ply, wep) end -- (into boxes)
        if IsValid(wep) then ply:StripWeapon(info.weaponClass) end
        if I.CarryConfig(id, c) then item.m = ply:GetNWInt(cat .. "Carry", 0) end -- saved with the item
        ply:SetNWInt(cat .. "Carry", I.CARRY_INDEX.stowed)
        ply:SetNWString(cat .. "Class", "")
        ply:SetNWInt(cat, 1)
        ply:SetNWInt(cat .. "Rounds", 0)
        I.MarkDirty(ply, "Uniform")
        return item
    end
    local contents
    if info.armor then
        item.a = ply:GetNWInt(cat .. "Armor")
        ply:SetNWInt(cat .. "Armor", 0)
    end
    if cat == "Vest" or cat == "Rucksack" then
        contents = I.Get(ply, cat)
        I.Set(ply, cat, {})
    end
    item.x = ply.AdvInvSlotExtra and ply.AdvInvSlotExtra[cat] or nil
    hook.Run("AdvInv_GearTakenOff", ply, cat, item) -- (still worn: may write its state into item.x)
    if ply.AdvInvSlotExtra then ply.AdvInvSlotExtra[cat] = nil end
    ply:SetNW2Int(cat, 1)
    I.MarkDirty(ply, "Uniform")
    return item, contents
end

---------------------------------------------------------------- ramasser (touche Utiliser)

-- Range une entité du sol dans les contenants du joueur (les boîtes de munitions complètent
-- d'abord les boîtes entamées du même type).
function I.PickupEntity(ply, ent)
    local item = I.ItemFromEntity(ent)
    if not item then return false end
    if ent.AdvInvContents and #ent.AdvInvContents > 0 then
        tell(ply, I.L("msg_equip_or_empty"))
        return false
    end
    local info = I.Info(item.id, item.c)
    local n = I.GroundCount(ent)
    if info.isBox and n == 1 and (item.r or 0) > 0 then return I.PickupRounds(ply, ent, item, info) end
    local taken = 0
    for _ = 1, n do
        if not I.Store(ply, table.Copy(item)) then break end
        taken = taken + 1
    end
    I.TakeFromGround(ent, taken)
    if taken < n then tell(ply, I.L("msg_no_room_for", info.name)) end
    return taken > 0
end

-- Ammunition lying around (one box, or another addon's ammo of any amount): the started boxes are
-- topped up, then new boxes of at most a box's rounds. The entity goes; what found no room lies
-- there as one of our boxes (another addon's entity would come back full).
local MAX_NEW_BOXES = 50
function I.PickupRounds(ply, ent, item, info)
    local size = math.max(info.boxRounds or 0, 1)
    local left = math.max(math.floor(item.r or 0), 0)
    local start = left
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        for _, it in ipairs(I.Get(ply, cont)) do
            if left <= 0 then break end
            if it.id == item.id and it.c == item.c and not it.j and (it.r or 0) < size then -- (never into a job's box)
                local add = math.min(size - (it.r or 0), left)
                it.r = (it.r or 0) + add
                left = left - add
                I.MarkDirty(ply, cont)
            end
        end
    end
    for _ = 1, MAX_NEW_BOXES do
        if left <= 0 then break end
        local box = table.Copy(item)
        box.r = math.min(left, size)
        if not I.Store(ply, box) then break end
        left = left - box.r
    end
    if left == start then
        tell(ply, I.L("msg_no_room_for", info.name))
        return false
    end
    local pos = ent:GetPos()
    I.TakeFromGround(ent, 1)
    if left > 0 then
        tell(ply, I.L("msg_no_room_for", info.name))
        local rest = table.Copy(item)
        rest.r = left
        I.SpawnItem(rest, pos)
    end
    return true
end

-- May ply take ent with Use / the pickup key? Within reach, in sight, not arrested, and allowed by
-- prop protection (CPPI) and DarkRP (canDarkRPUse, PlayerUse = false).
function I.CanPickup(ply, ent)
    if ply.isArrested and ply:isArrested() then return false, I.L("msg_arrested") end
    if not I.InReach(ply, ent, math.max(C.UseDistance, 130)) then return false end
    if ent.PlayerUse == false then return false end
    if ent.CPPICanUse and ent:CPPICanUse(ply) == false then return false end
    if DarkRP then
        local can, why = hook.Call("canDarkRPUse", nil, ply, ent, ply)
        if can == false then return false, why end
    end
    if hook.Run("AdvInv_CanPickup", ply, ent) == false then return false end
    return true
end

-- Touche Utiliser sur un objet : l'équiper si l'emplacement est libre, sinon le ranger.
-- Une arme remplace celle de son emplacement (l'ancienne est posée au sol).
function I.Use(ply, ent)
    if not (IsValid(ply) and ply:Alive()) or (ply.AdvInvUseDelay or 0) > CurTime() then return end
    ply.AdvInvUseDelay = CurTime() + 0.4
    local item = I.ItemFromEntity(ent)
    if not item then return end
    local can, cantWhy = I.CanPickup(ply, ent)
    if not can then
        if cantWhy then tell(ply, cantWhy) end
        return
    end
    local info = I.Info(item.id, item.c)
    if info.isWeapon then
        -- checked before the old weapon leaves its slot (it would be on the ground for nothing)
        local carryOK, carryWhy = I.CarryEquipCheck(ply, info.cat, item)
        if not carryOK then
            tell(ply, carryWhy)
            return
        end
        local old
        if slotID(ply, info.cat) > 1 then
            -- the old one goes down where the new one lay, if it may leave the player (DarkRP's drop
            -- rules: job weapons, DisallowDrop, restrictdrop...); else the new one is stored
            if not I.MayLeaveSlot(ply, info.cat) then return I.PickupEntity(ply, ent) end
            old = I.TakeOff(ply, info.cat)
        end
        local pos = ent:GetPos() + Vector(0, 0, 10)
        -- (on the ground it leaves him: an ordinary one, as DarkRP lets it be dropped; back in its
        -- slot it stays what it was)
        if I.Equip(ply, item) then
            I.TakeFromGround(ent, 1)
            if old then old.j = nil I.SpawnItem(old, pos) end
        elseif old and not I.Equip(ply, old) then
            old.j = nil
            I.SpawnItem(old, pos)
        end
        return
    end
    if info.cat and AdvInv.GearCat[info.cat] and slotID(ply, info.cat) <= 1 then
        local ok, why = I.Equip(ply, item, ent.AdvInvContents)
        if ok then
            I.TakeFromGround(ent, 1)
            return
        end
        if why then tell(ply, why) end
    end
    I.PickupEntity(ply, ent)
end

---------------------------------------------------------------- caisses et véhicules

-- Un objet qui touche une caisse ou un véhicule y est rangé s'il a la place.
function I.StoreEntityIn(holder, ent)
    if not IsValid(ent) or ent.AdvInvStored or (ent.AdvInvContents and #ent.AdvInvContents > 0) then return false end
    if (I.GroundItems[ent] or 0) > CurTime() - 1 then return false end -- just dropped
    if holder:GetNWBool("AdvInvPersonal") or holder:GetNWBool("AdvInvLocked") then return false end -- whose? / locked
    local item = I.ItemFromEntity(ent)
    if not item or not I.CanFit(holder, "Storage", item.id, item.c) then return false end
    local n, taken = math.max(ent:GetNWInt("AdvInvCount", 1), 1), 0
    for _ = 1, n do
        if not I.CanFit(holder, "Storage", item.id, item.c) then break end
        table.insert(I.Get(holder, "Storage"), table.Copy(item))
        taken = taken + 1
    end
    I.MarkDirty(holder, "Storage")
    I.TakeFromGround(ent, taken)
    return true
end

hook.Add("simfphysPhysicsCollide", "AdvInv_VehicleStore", function(vehicle, data)
    local ent = data.HitEntity
    if IsValid(ent) and I.ItemFromEntity(ent) then I.StoreEntityIn(vehicle, ent) end
end)

---------------------------------------------------------------- actions des clients

-- Le joueur peut-il fouiller ce porteur ? Lui-même, une caisse / un véhicule à portée, ou le
-- joueur qu'un admin regarde (sv_admin.lua).
function I.CanAccess(ply, holder)
    if not (IsValid(ply) and ply:Alive() and IsValid(holder)) then return false end
    if holder == ply then return true end
    if holder:IsPlayer() and ply.AdvInvAdminView == holder and I.IsAdmin(ply) then return true end
    if holder:IsPlayer() and I.IsSearching and I.IsSearching(ply, holder) then return true end
    if I.IsBody(holder) then -- a dead player's body within reach, not behind a wall
        return I.InReach(ply, holder)
    end
    if I.IsStorage(holder) then
        if holder:GetNWBool("AdvInvLocked") and not (I.CanOpenLocked and I.CanOpenLocked(ply, holder)) then return false end
        if I.VehicleLockedFor(ply, holder) then return false end
        return I.InReach(ply, holder)
    end
    return false
end

-- A vehicle's trunk while the vehicle is locked (DarkRP keys, simfphys): only its owners.
function I.VehicleLockedFor(ply, veh)
    if not (veh:IsVehicle() or veh.IsSimfphyscar or veh:GetClass() == "gmod_sent_vehicle_fphysics_base") then return false end
    local locked = veh.VehicleLocked == true or veh:GetNWBool("VehicleLocked")
        or (veh.GetIsVehicleLocked and veh:GetIsVehicleLocked()) or false
    if not locked then return false end
    if veh.isKeysOwnedBy and veh:isKeysOwnedBy(ply) then return false end
    if veh.CPPIGetOwner and veh:CPPIGetOwner() == ply then return false end
    return true
end

-- Another player's containers: an admin viewing them may take and put; a searcher may only take
-- (advinv_search_take 1).
function I.CanTakeFrom(ply, holder)
    if holder == ply or I.IsStorage(holder) or I.IsBody(holder) then return true end
    if not holder:IsPlayer() then return false end
    if ply.AdvInvAdminView == holder and I.IsAdmin(ply) then return true end
    return I.IsSearching and I.IsSearching(ply, holder) and I.SearchTake:GetBool() or false
end

function I.CanPutInto(ply, holder)
    if holder == ply or I.IsStorage(holder) or I.IsBody(holder) then return true end
    return holder:IsPlayer() and ply.AdvInvAdminView == holder and I.IsAdmin(ply) or false
end

-- A searcher taking from another player: only what DarkRP's weapon checker would take (sv_search.lua).
local function searchMayTake(ply, holder, item)
    if holder == ply or not holder:IsPlayer() or not item or (ply.AdvInvAdminView == holder and I.IsAdmin(ply)) then return true end
    if item.j then return false, I.L("search_cannot_take", I.Info(item.id, item.c).name or "?") end -- (a job's item)
    if not I.SearchMayTake then return true end
    return I.SearchMayTake(holder, item.id, item.c)
end
I.SearchMayTakeItem = searchMayTake -- (every path taking from a searched player: unload too)

function I.Move(ply, from, fromCont, index, to, toCont)
    local items = I.Get(from, fromCont)
    local item = items[index]
    if not item then return false end
    if from == to and fromCont == toCont then return true end
    if not I.HasContainer(to, toCont) then return false, I.L("msg_container_unavailable") end
    -- (I.MAX_ITEMS: the client sees and names the first 255 only)
    if I.ItemMass(item.id, item.c) > I.Free(to, toCont) or #I.Get(to, toCont) >= I.MAX_ITEMS then
        return false, I.L("msg_no_room_in", I.ContainerNames[toCont] or toCont)
    end
    table.remove(items, index)
    if to ~= from then item.j = nil end -- a job's weapon leaving its player is an ordinary one (sv_darkrp.lua)
    table.insert(I.Get(to, toCont), item)
    I.MarkDirty(from, fromCont)
    I.MarkDirty(to, toCont)
    return true
end

local function readCont() return I.IDCont[net.ReadUInt(3)] end
I.ReadCont = readCont

-- An item named by the client: its place in the list and a check of what it is (CRC of its stack key,
-- sh_containers.lua). The list may have moved since the client saw it (another player took an item,
-- a reload emptied a box): the item meant is the one at that place if it is still that one, else the
-- last one of its kind in the container, else none (refused, the client is shown the real state).
function I.ReadItemRef()
    return net.ReadUInt(8), net.ReadUInt(32)
end

function I.ResolveItemRef(holder, cont, index, check)
    local items = I.Get(holder, cont)
    if items[index] and I.ItemCheck(items[index]) == check then return index end
    for k = #items, 1, -1 do
        if I.ItemCheck(items[k]) == check then return k end
    end
end

local handlers = {}
I.ActHandlers = handlers -- other files add their actions (sv_admin.lua...)

-- The client shows a job's item and looted ones of the same kind as one tile (it doesn't know the
-- job flag) and names the tile's first item: for an item leaving, another of the tile without the
-- flag is taken instead (else the whole tile was refused: a looted grenade could never leave).
-- ply: who acts. A searcher may never take a job's item: for him always; for the owner only while job
-- items may not leave (else the job one may go as well, and keeping it would lose the looted one at
-- the next death or job change).
local function leavableInstead(holder, cont, index, ply)
    local items = I.Get(holder, cont)
    local it = items[index]
    if not (it and it.j and (holder ~= ply or (I.JobItemsBound and I.JobItemsBound()))) then return index end
    local key = I.StackKey(it)
    for k = #items, 1, -1 do
        if not items[k].j and I.StackKey(items[k]) == key then return k end
    end
    return index
end

-- Index of another item of the same stack as key in a container (from the end), or nil.
local function findSame(holder, cont, key, job)
    local items = I.Get(holder, cont)
    for k = #items, 1, -1 do
        -- (the job flag too: the rules were checked on the first item only, and a job's grenade
        -- looks like a looted one; it would leave with it and become ordinary)
        if I.StackKey(items[k]) == key and (items[k].j and true or false) == job then return k end
    end
end

-- Moves the item at index, then up to count - 1 identical items, while there is room.
function I.MoveSame(ply, from, fromCont, index, to, toCont, count)
    local item = I.Get(from, fromCont)[index]
    if not item then return false end
    if from == to and fromCont == toCont then return true end
    local key, job = I.StackKey(item), item.j and true or false
    local ok, why = I.Move(ply, from, fromCont, index, to, toCont)
    for _ = 2, count do
        if not ok then break end
        local k = findSame(from, fromCont, key, job)
        if not k then break end
        ok, why = I.Move(ply, from, fromCont, k, to, toCont)
    end
    if ok == false then return false, why end
    return true
end

handlers[I.ACT.MOVE] = function(ply)
    local from, fromCont = net.ReadEntity(), readCont()
    local index, check = I.ReadItemRef()
    local to, toCont = net.ReadEntity(), readCont()
    local count = math.max(net.ReadUInt(8), 1)
    if not (fromCont and toCont and I.CanAccess(ply, from) and I.CanAccess(ply, to)) then return end
    if not (I.CanTakeFrom(ply, from) and I.CanPutInto(ply, to)) then return false end
    index = I.ResolveItemRef(from, fromCont, index, check)
    if not index then return false end
    if to ~= from then
        index = leavableInstead(from, fromCont, index, ply)
        local may, mayWhy = searchMayTake(ply, from, I.Get(from, fromCont)[index])
        if not may then return false, mayWhy end
    end
    if from == ply and to ~= ply then
        local it = I.Get(from, fromCont)[index]
        local may, mayWhy = true, nil
        if it then may, mayWhy = I.MayLeaveItem(ply, it) end
        if not may then return false, mayWhy end
    end
    return I.MoveSame(ply, from, fromCont, index, to, toCont, count)
end

handlers[I.ACT.DROP] = function(ply)
    local holder, cont = net.ReadEntity(), readCont()
    local index, check = I.ReadItemRef()
    local count = math.max(net.ReadUInt(8), 1)
    if not (cont and I.CanAccess(ply, holder)) then return end
    if not I.CanTakeFrom(ply, holder) then return false end
    index = I.ResolveItemRef(holder, cont, index, check)
    if not index then return false end
    index = leavableInstead(holder, cont, index, ply)
    local items = I.Get(holder, cont)
    local item = items[index]
    if not item then return end
    local taken, takenWhy = searchMayTake(ply, holder, item)
    if not taken then return false, takenWhy end
    if holder == ply then
        local may, mayWhy = I.MayLeaveItem(ply, item)
        if not may then return false, mayWhy end
    end
    if item.id == I.GENERIC_WEAPON then count = math.min(count, 5) end -- one real weapon each
    local key, first, n = I.StackKey(item), item, 0
    local job = item.j and true or false
    for _ = 1, count do
        table.remove(items, index)
        n = n + 1
        index = findSame(holder, cont, key, job)
        item = index and items[index]
        if not item then break end
    end
    I.DropStack(first, n, I.DropPos(ply)) -- one stack on the ground
    I.MarkDirty(holder, cont)
    return true
end

handlers[I.ACT.EQUIP] = function(ply)
    local holder, cont = net.ReadEntity(), readCont()
    local index, check = I.ReadItemRef()
    if not (cont and I.CanAccess(ply, holder)) then return end
    if not I.CanTakeFrom(ply, holder) then return false end
    index = I.ResolveItemRef(holder, cont, index, check)
    if not index then return false end
    if holder ~= ply then index = leavableInstead(holder, cont, index, ply) end
    local items = I.Get(holder, cont)
    local item = items[index]
    if not item then return end
    local taken, takenWhy = searchMayTake(ply, holder, item)
    if not taken then return false, takenWhy end
    local cat = I.Info(item.id, item.c).cat
    -- un sac ou un gilet ne s'équipe pas depuis son propre contenant (a uniform does: the pockets are
    -- there without one, and a uniform picked up or looted lands in them)
    if holder == ply and cont == cat and cat ~= "Uniform" then return end
    table.remove(items, index)
    local wasJob = item.j
    if holder ~= ply then item.j = nil end -- (taken from someone else: no longer his job's, as I.Move)
    local ok, why = I.Equip(ply, item)
    if not ok then
        item.j = wasJob
        table.insert(items, index, item)
        return false, why
    end
    I.MarkDirty(holder, cont)
    return true
end

handlers[I.ACT.UNEQUIP] = function(ply)
    local cat = AdvInv.IDCategory[net.ReadUInt(4)]
    local toDrop = net.ReadBool()
    local to, toCont
    if not toDrop then to, toCont = net.ReadEntity(), readCont() end
    if not cat then return end
    local ok, why = I.CanTakeOff(ply, cat)
    if not ok then return false, why end
    local id, c = I.SlotRef(ply, cat)
    if toDrop or (IsValid(to) and to ~= ply) then
        local may, mayWhy = I.MayLeaveSlot(ply, cat) -- (its job flag too)
        if not may then return false, mayWhy end
        may, mayWhy = I.ContentsMayLeave(ply, cat) -- (dropped with what it holds)
        if not may then return false, mayWhy end
    end
    if toDrop then
        local item, contents = I.TakeOff(ply, cat)
        if item then
            -- (its contents leave him with it: a job's item among them is an ordinary one now, as
            -- with I.Move; else the next wearer lost it at his death and never saved it)
            item.j = nil
            for _, it in ipairs(contents or {}) do it.j = nil end
            I.SpawnItem(item, I.DropPos(ply), contents)
        end
        return true
    end
    if not (toCont and I.CanAccess(ply, to)) then return end
    if to ~= ply and not I.CanPutInto(ply, to) then return false end
    if to == ply and toCont == cat then return false, I.L("msg_not_in_itself") end
    if (cat == "Vest" or cat == "Rucksack") and #I.Get(ply, cat) > 0 then
        return false, I.L("msg_empty_it_first")
    end
    if not I.CanFit(to, toCont, id, c) then
        return false, I.L("msg_no_room_in", I.ContainerNames[toCont] or toCont)
    end
    local item = I.TakeOff(ply, cat)
    if item then
        if to ~= ply then item.j = nil end -- a job's weapon leaving its player is an ordinary one
        -- taking it off may have filled the room it was to go to (its launcher's rounds became a box):
        -- then another of his containers, else the ground (a job's weapon never: it stays, over capacity)
        if I.CanFit(to, toCont, item.id, item.c) then
            table.insert(I.Get(to, toCont), item)
            I.MarkDirty(to, toCont)
        elseif not I.Store(ply, item) then
            -- (the ground only for what may leave him: else the pockets, over their load)
            if not item.j and I.MayLeaveItem(ply, item) then I.SpawnItem(item, I.DropPos(ply))
            else I.ForceStore(ply, item) end
        end
    end
    return true
end

-- Splits rounds off an ammo box into a new box in the same container.
handlers[I.ACT.SPLIT] = function(ply)
    local holder, cont = net.ReadEntity(), readCont()
    local index, check = I.ReadItemRef()
    local rounds = net.ReadUInt(I.NET_ROUNDS_BITS)
    if not (cont and I.CanAccess(ply, holder) and I.CanTakeFrom(ply, holder) and I.CanPutInto(ply, holder)) then return end
    index = I.ResolveItemRef(holder, cont, index, check)
    if not index then return false end
    local item = I.Get(holder, cont)[index]
    if not item or not I.Info(item.id, item.c).isBox then return end
    if rounds < 1 or rounds >= (item.r or 0) then return false end
    if not I.CanFit(holder, cont, item.id, item.c) then return false, I.L("msg_no_room_in", I.ContainerNames[cont] or cont) end
    item.r = item.r - rounds
    table.insert(I.Get(holder, cont), { id = item.id, c = item.c, r = rounds, a = 0, j = item.j }) -- (a job's box: both halves)
    I.MarkDirty(holder, cont)
    return true
end

handlers[I.ACT.CARRY] = function(ply)
    local cat = AdvInv.IDCategory[net.ReadUInt(4)]
    local mode = I.CARRY_MODES[net.ReadUInt(I.CARRY_NET_BITS)]
    return I.RequestCarryMode(ply, cat, mode)
end

handlers[I.ACT.OPEN] = function(ply)
    local holder = net.ReadEntity()
    if not ((I.IsStorage(holder) or I.IsBody(holder)) and I.CanAccess(ply, holder)) then return end
    holder.AdvInvViewers = holder.AdvInvViewers or {}
    holder.AdvInvViewers[ply] = true
    for _, cont in ipairs(I.ContainersOf(holder)) do I.SendContainer(holder, cont, ply, ply) end
    return true
end

handlers[I.ACT.CLOSE] = function(ply)
    local holder = net.ReadEntity()
    if IsValid(holder) and holder.AdvInvViewers then holder.AdvInvViewers[ply] = nil end
    return true
end

-- What an arrested player may still do: look, close, change a carry mode; admins act as usual.
local ARRESTED_OK = { [I.ACT.OPEN] = true, [I.ACT.CLOSE] = true, [I.ACT.CARRY] = true, [I.ACT.ADMIN] = true }

-- DarkRP's drop rules for a weapon leaving its player (dropped, put into a crate or a body): job
-- weapons (dropspawnedweapons off), DisallowDrop, restrictdrop. -> true, or false and a reason
function I.MayLeave(ply, id, c)
    if not id or id <= 1 then return true end
    local info = I.Info(id, c)
    -- grenades are ammunition items: the rules of their grenade weapon (a job's weapon_frag...)
    local grenadeClass = info.isBox and I.GrenadeOfAmmo and I.GrenadeOfAmmo(info.ammo)
    if not info.isWeapon and not grenadeClass then return true end
    local class = grenadeClass or (id == I.GENERIC_WEAPON and c) or info.weaponClass
    if not isstring(class) then return true end
    local name = info.name or class
    if hook.Run("AdvInv_CanWeaponLeave", ply, class) == false then return false, I.L("msg_cannot_drop", name) end
    local cfg = DarkRP and GAMEMODE and GAMEMODE.Config
    if not cfg then return true end
    class = string.lower(class)
    if not cfg.dropspawnedweapons and ply.getJobTable then
        local job = ply:getJobTable()
        if job and istable(job.weapons) and table.HasValue(job.weapons, class) then return false, I.L("msg_cannot_drop", name) end
    end
    if cfg.DisallowDrop and cfg.DisallowDrop[class] then return false, I.L("msg_cannot_drop", name) end
    if cfg.restrictdrop then
        for _, v in pairs(CustomShipments or {}) do
            if v.entity == class then return true end
        end
        return false, I.L("msg_cannot_drop", name)
    end
    return true
end

-- Job items are bound to their player (DarkRP: dropspawnedweapons off): they never leave him.
function I.JobItemsBound()
    local cfg = DarkRP and GAMEMODE and GAMEMODE.Config
    return cfg ~= nil and not cfg.dropspawnedweapons
end

-- An item as it is (its job flag too): a job's item stays a job's item whatever his job is now
-- (picked up again after a job change, it would pass the new job's rule).
function I.MayLeaveItem(ply, item)
    if not item then return true end
    local cfg = DarkRP and GAMEMODE and GAMEMODE.Config
    if item.j and cfg and not cfg.dropspawnedweapons then
        local info = I.Info(item.id, item.c)
        return false, I.L("msg_cannot_drop", info.name or info.weaponClass or item.c or "?")
    end
    return I.MayLeave(ply, item.id, item.c)
end

-- An equipped item leaving its slot (dropped, swapped for one on the ground...): the item's rule,
-- job flag included (a job's weapon in its slot is one too).
function I.MayLeaveSlot(ply, cat)
    local id, c = I.SlotRef(ply, cat)
    return I.MayLeaveItem(ply, { id = id, c = c, j = ply.AdvInvJobSlot and ply.AdvInvJobSlot[cat] or nil })
end

-- What a vest or backpack holds leaves with it: each item under its own rule.
function I.ContentsMayLeave(ply, cat)
    if cat ~= "Vest" and cat ~= "Rucksack" then return true end
    for _, it in ipairs(I.Get(ply, cat)) do
        local may, why = I.MayLeaveItem(ply, it)
        if not may then return false, why end
    end
    return true
end

net.Receive("advinv_act", function(_, ply)
    -- au plus 15 actions par seconde et par joueur
    local now = CurTime()
    if (ply.AdvInvActWindow or 0) < now then
        ply.AdvInvActWindow = now + 1
        ply.AdvInvActCount = 0
    end
    ply.AdvInvActCount = (ply.AdvInvActCount or 0) + 1
    if ply.AdvInvActCount > 15 then return end

    local act = net.ReadUInt(I.ACT_BITS)
    local handler = handlers[act]
    if not handler then return end
    if not ply:Alive() and act ~= I.ACT.CLOSE and act ~= I.ACT.SEARCH and act ~= I.ACT.ADMIN then return end
    if ply.isArrested and ply:isArrested() and not ARRESTED_OK[act] then
        tell(ply, I.L("msg_arrested"))
        I.MarkAllDirty(ply)
        return
    end
    I.Actor = ply -- personal storages: whose store (sv_storage.lua)
    local ok, why
    local fine = xpcall(function() ok, why = handler(ply) end, function(e) ErrorNoHalt(debug.traceback(tostring(e)) .. "\n") end)
    I.Actor = nil
    if not fine then ok, why = false, nil end
    if ok == false and why then tell(ply, why) end
    if ok == false then
        -- refusé : le client réaffiche l'état réel
        I.MarkAllDirty(ply)
    end
end)

-- ply no longer sees holder's containers (out of reach or sight, locked, its settings changed, a
-- search over): his window closes, else it would keep showing what it saw last and refuse his actions.
util.AddNetworkString("advinv_view_end")
function I.EndView(holder, ply)
    if holder.AdvInvViewers then holder.AdvInvViewers[ply] = nil end
    if IsValid(ply) and ply:IsPlayer() then
        net.Start("advinv_view_end")
        net.WriteEntity(holder)
        net.Send(ply)
    end
end

-- Les spectateurs d'une caisse s'en vont quand ils s'éloignent.
timer.Create("AdvInv_Viewers", 1, 0, function()
    local list = {}
    for _, class in ipairs(table.GetKeys(I.StorageClasses)) do
        for _, ent in ipairs(ents.FindByClass(class)) do list[#list + 1] = ent end
    end
    for body in pairs(I.Bodies or {}) do list[#list + 1] = body end
    for _, ent in ipairs(list) do
        if IsValid(ent) then
            for ply in pairs(ent.AdvInvViewers or {}) do
                if not I.CanAccess(ply, ent) then I.EndView(ent, ply) end
            end
        end
    end
end)

-- Réapparition : réserve de munitions et contenu renvoyés.
hook.Add("PlayerSpawn", "AdvInv_Resync", function(ply)
    timer.Simple(0, function()
        if IsValid(ply) then I.MarkAllDirty(ply) end
    end)
end)

-- StripAmmo / RemoveAllAmmo by other code: guarded (see I.GuardAmmo), then the reserve comes back
-- from the boxes.
do
    local meta = FindMetaTable("Player")
    for _, name in ipairs({ "StripAmmo", "RemoveAllAmmo" }) do
        local orig = meta["AdvInvOrig" .. name] or meta[name]
        if orig then
            meta["AdvInvOrig" .. name] = orig
            meta[name] = function(ply, ...)
                if IsValid(ply) then
                    I.GuardAmmo(ply)
                    if I.ReconcileGrenades then I.ReconcileGrenades(ply) end
                end
                local r = { orig(ply, ...) }
                if IsValid(ply) then
                    if I.GrenadeBaseline and ply.AdvInvGrenades then I.GrenadeBaseline(ply) end -- not thrown
                    I.MarkDirty(ply, "Uniform")
                end
                return unpack(r)
            end
        end
    end
end
