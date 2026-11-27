--[[
    JMod (Workshop 1919689921, global JMod), when installed (items: sh_jmod.lua).

    Weapons and munitions:
      - its guns are ArcCW weapons: inventory weapons like any (sh_generic.lua, sv_arccw.lua); its
        tools (hands, toolbox, medkit, bucket, designator, axe, pickaxe, shovel, spade) stay ordinary
        weapons (sh_generic.lua);
      - the munitions it gives (ammo and munition crates, ammo boxes, an armour's stored rounds) go
        into ammo boxes: the reserve is the boxes (sv_containers.lua), its gains would be erased.

    Armour (its pieces are items: sh_jmod.lua):
      - an item put in its slot is put on in JMod (its durability, charges and colour kept with the
        item: item.x); taken off, JMod takes it off and the item keeps its state;
      - JMod's ways of putting one on (Alt + Use on its entity, its commands) put the item in its
        slot (else in the inventory); Use picks its entity up into the inventory; JMod's ways of
        taking one off (its armour window, a piece taking the place) put the item in the inventory;
        destroyed by JMod (durability gone), the item is gone (what a vest or backpack held stays);
      - one weight: the item's encombrement (JMod's slowdown for it is taken away).

    Resources: bags in the inventory (one kind of bag per resource), the same amounts as JMod's
    inventory of resources: what JMod adds or takes there (its grab key, crafting, its window) is
    added to or taken from the bags, what the bags gain or lose is JMod's too. They don't count in
    JMod's own capacity (the bags take room in the inventory). No room for gained resources: a JMod
    box of them at his feet. At death the bags stay on the body like the rest.

    Its own inventory (the grab key: its grenades and items) stays its own. Its corpse
    (JMod.Config.QoL.JModCorpseStayTime > 0) would be a second body: the inventory's body takes its
    place, and what JMod would have put in it goes into that body, opened with JMod's grab key.
--]]
local I = AdvInv
local JB = I.JModBridge

local function JM() return istable(JMod) and JMod or nil end

local busy = 0 -- our own calls into JMod: its wrapped functions do what JMod does
local function quiet(f, ...)
    busy = busy + 1
    local r = { pcall(f, ...) }
    busy = busy - 1
    if not r[1] then ErrorNoHalt("[AdvInv] JMod: " .. tostring(r[2]) .. "\n") return end
    return unpack(r, 2)
end

---------------------------------------------------------------- munitions

local function wrapGiveAmmo(J)
    local give = J.GiveAmmo
    if not isfunction(give) or give == J.AdvInvGiveAmmo then return end
    local wrapped = function(ply, ...)
        if not (IsValid(ply) and ply:IsPlayer()) then return give(ply, ...) end
        local types = game.GetAmmoTypes()
        local before = {}
        for id in pairs(types) do before[id] = ply:GetAmmoCount(id) end
        I.BeginGainConversion(ply)
        local r = { pcall(give, ply, ...) }
        local gainedTypes
        if IsValid(ply) then
            for id, name in pairs(types) do
                local gained = ply:GetAmmoCount(id) - (before[id] or 0)
                if gained > 0 then
                    I.GiveRounds(ply, name, gained)
                    gainedTypes = gainedTypes or {}
                    gainedTypes[name] = true
                end
            end
        end
        I.EndGainConversion(ply, gainedTypes)
        if not r[1] then error(r[2], 0) end
        return unpack(r, 2)
    end
    J.GiveAmmo = wrapped
    J.AdvInvGiveAmmo = wrapped
end

---------------------------------------------------------------- armour

local rawEquip, rawRemove

local function readState(x)
    local t = isstring(x) and x ~= "" and util.JSONToTable(x)
    return istable(t) and t or {}
end
local function writeState(s) return util.TableToJSON(s) end

-- a JMod armour entity's state
local function entState(ent)
    local s = {}
    if isnumber(ent.Durability) then s.d = ent.Durability end
    if istable(ent.ArmorCharges) then s.c = table.Copy(ent.ArmorCharges) end
    if isstring(ent.EZID) then s.i = ent.EZID end
    local col = ent:GetColor()
    s.k = { col.r, col.g, col.b }
    return s
end

-- ply's item in slot cat, if a JMod piece: its name, its state, and the piece JMod has on him
-- (id, entry; nil when JMod doesn't wear it)
local function slotPiece(ply, cat)
    local class = AdvInv.IDClass[ply:GetNW2Int(cat)]
    local name = class and JB.ByClass[class]
    if not name then return end
    local s = readState(ply.AdvInvSlotExtra and ply.AdvInvSlotExtra[cat])
    local items = ply.EZarmor and ply.EZarmor.items
    if isstring(s.i) and istable(items) and istable(items[s.i]) and items[s.i].name == name then
        return name, s, s.i, items[s.i]
    end
    return name, s
end

local function setExtra(ply, cat, s)
    ply.AdvInvSlotExtra = ply.AdvInvSlotExtra or {}
    ply.AdvInvSlotExtra[cat] = writeState(s)
end

local function stateOfEntry(id, e)
    return {
        i = id, d = e.dur, c = istable(e.chrg) and table.Copy(e.chrg) or nil,
        k = istable(e.col) and { e.col.r, e.col.g, e.col.b } or nil,
    }
end

-- JMod puts on the piece of ply's slot cat (with the item's state)
local function wear(ply, cat)
    local J = JM()
    if not (J and rawEquip and ply:Alive()) then return end
    local name, s, id = slotPiece(ply, cat)
    if not name or id then return end
    ply.EZarmor = ply.EZarmor or table.Copy(J.DEFAULT_ARMOR)
    ply.EZarmor.items = ply.EZarmor.items or {}
    local before = {}
    for k in pairs(ply.EZarmor.items) do before[k] = true end
    quiet(rawEquip, ply, name)
    local newID
    for k, e in pairs(ply.EZarmor.items) do
        if not before[k] and istable(e) and e.name == name then newID = k end
    end
    if not newID then return end
    local e = ply.EZarmor.items[newID]
    if isnumber(s.d) then e.dur = s.d end
    if istable(s.c) then e.chrg = table.Copy(s.c) end
    if istable(s.k) then e.col = Color(s.k[1] or 128, s.k[2] or 128, s.k[3] or 128) end
    if isstring(s.i) and s.i ~= newID and not ply.EZarmor.items[s.i] then
        ply.EZarmor.items[newID] = nil
        e.id = s.i
        ply.EZarmor.items[s.i] = e
        newID = s.i
    end
    s.i = newID
    setExtra(ply, cat, s)
    if isfunction(J.CalcSpeed) then J.CalcSpeed(ply) end
    if isfunction(J.EZarmorSync) then J.EZarmorSync(ply) end
end

-- An entity JMod made for a piece we keep as an item: gone (JMod's own inventory stowed in a JMod
-- backpack: JMod puts it on the ground). Not in this tick: its own setup reaches it 0.01 s after.
local function vanish(ent)
    if not IsValid(ent) or ent.AdvInvJModGone then return end
    ent.AdvInvJModGone = true
    ent.ammoStored = nil
    ent:SetNoDraw(true)
    ent:SetNotSolid(true)
    ent:SetMoveType(MOVETYPE_NONE)
    timer.Simple(0.1, function() if IsValid(ent) then ent:Remove() end end)
end

-- JMod takes a piece off ply, as JMod does, but:
--   - without its ammo limit (a piece that carries ammo): the reserve is the boxes, JMod would take
--     the rounds above its limit out of them (and at a death, the body already has those boxes);
--   - whatever goes wrong in it (another addon's hook), the piece is off and no entity of it is left.
local function jmodRemove(ply, id, broken)
    local J = JM()
    if not (J and rawRemove) then return end
    local e = ply.EZarmor and ply.EZarmor.items and ply.EZarmor.items[id]
    local specs = istable(e) and J.ArmorTable and J.ArmorTable[e.name]
    local mult = specs and specs.ammoCarryMult
    if specs then specs.ammoCarryMult = nil end
    local ent = quiet(rawRemove, ply, id, broken)
    if specs then specs.ammoCarryMult = mult end
    if ply.EZarmor and ply.EZarmor.items and ply.EZarmor.items[id] then
        ply.EZarmor.items[id] = nil
        if isfunction(J.CalcSpeed) then pcall(J.CalcSpeed, ply) end
        if isfunction(J.EZarmorSync) then pcall(J.EZarmorSync, ply) end
    end
    vanish(ent)
    if specs and isstring(specs.ent) then
        for _, x in ipairs(ents.FindByClass(specs.ent)) do
            if x.EZID == id then vanish(x) end
        end
    end
end

-- JMod takes off the piece of ply's slot cat: its state into item.x
local function takeOff(ply, cat, item)
    local name, s, id, e = slotPiece(ply, cat)
    if not name then return end
    if e then
        s = stateOfEntry(id, e)
        jmodRemove(ply, id)
    end
    item.x = writeState(s)
end

-- The live state (durability, charges) into the items, for a save or a death.
function JB.RefreshState(ply)
    for cat in pairs(I.GearCat) do
        local name, _, id, e = slotPiece(ply, cat)
        if name and e then setExtra(ply, cat, stateOfEntry(id, e)) end
    end
end

-- Another worn piece covers a body part this one covers: JMod would take it off. Refused.
function JB.CanWear(ply, name, cat)
    local J = JM()
    local info = J and J.ArmorTable and J.ArmorTable[name]
    if not (info and istable(info.slots)) then return true end
    for c in pairs(I.GearCat) do
        if c ~= cat then
            local other = slotPiece(ply, c)
            local oinfo = other and J.ArmorTable[other]
            if oinfo and istable(oinfo.slots) then
                for part in pairs(info.slots) do
                    if oinfo.slots[part] ~= nil then
                        local class = JB.ByName[other]
                        I.Tell(ply, I.L("jmod_covers", I.Info(I.ClassID[class] or 0).name or other))
                        return false
                    end
                end
            end
        end
    end
    return true
end

local function slotOfID(ply, id)
    for cat in pairs(I.GearCat) do
        local name, s = slotPiece(ply, cat)
        if name and s.i == id then return cat end
    end
end

-- The items' pieces are worn in JMod (after a respawn that kept them, a save loaded...). Pieces JMod
-- wears that are no item (given by code: a job's armour) stay JMod's own, as it made them.
function JB.Reconcile(ply)
    local J = JM()
    if not (J and IsValid(ply) and ply:Alive()) then return end
    for cat in pairs(I.GearCat) do
        local name, _, id = slotPiece(ply, cat)
        if name and not id then wear(ply, cat) end
    end
    JB.RefreshState(ply)
end

hook.Add("AdvInv_GearEquipped", "AdvInv_JMod", function(ply, cat) wear(ply, cat) end)
-- The inventory is emptied (another character loaded, a reset, a job's inventory forgotten): its
-- pieces leave JMod too, without a trace (else they'd come back as items into the next inventory).
hook.Add("AdvInv_SlotsReset", "AdvInv_JMod", function(ply)
    for cat in pairs(I.GearCat) do
        local name, _, id = slotPiece(ply, cat)
        if name and id then jmodRemove(ply, id) end
    end
end)

-- what a destroyed vest or backpack held: where it fits, else on the ground (a job's item: in the
-- pockets, never on the ground, as the inventory keeps them)
local function keepContents(ply, contents)
    for _, it in ipairs(contents or {}) do
        if not I.Store(ply, it) then
            local pockets = I.Get(ply, "Uniform")
            if it.j and #pockets < I.MAX_ITEMS then
                pockets[#pockets + 1] = it
                I.MarkDirty(ply, "Uniform")
            elseif not it.j then
                I.SpawnItem(it, I.DropPos(ply))
            end
        end
    end
end
hook.Add("AdvInv_GearTakenOff", "AdvInv_JMod", function(ply, cat, item)
    if ply.AdvInvJModBroken then return end -- (destroyed by JMod: nothing left to take off)
    takeOff(ply, cat, item)
end)

local function wrapArmor(J)
    -- (JMod's own functions kept on J: a reload of this file wraps them again, not its old wrappers)
    if J.EZ_Equip_Armor ~= J.AdvInvEquip then J.AdvInvRawEquip = J.EZ_Equip_Armor end
    rawEquip = J.AdvInvRawEquip
    if J.RemoveArmorByID ~= J.AdvInvRemove then J.AdvInvRawRemove = J.RemoveArmorByID end
    rawRemove = J.AdvInvRawRemove
    -- JMod puts a piece on from its entity (Alt + Use): the item goes in its slot (else into the
    -- inventory). Put on by name (code: a job's armour, its admin commands): JMod's own, as without
    -- the inventory (it is gone at death, never an item).
    J.EZ_Equip_Armor = function(ply, nameOrEnt, ...)
        if busy > 0 or not (IsValid(ply) and ply:IsPlayer()) then return rawEquip(ply, nameOrEnt, ...) end
        local ent = isentity(nameOrEnt) and IsValid(nameOrEnt) and nameOrEnt or nil
        local class = ent and ent.ArmorName and JB.ByName[ent.ArmorName]
        local id = class and I.ClassID[class]
        if not id then return rawEquip(ply, nameOrEnt, ...) end
        local name = ent.ArmorName
        local item = { id = id, r = 0, a = 0, x = writeState(entState(ent)) }
        if not I.Equip(ply, item) then
            if not I.Store(ply, item) then
                I.Tell(ply, I.L("msg_no_room_for", I.Info(id).name or name))
                return
            end
            I.Tell(ply, I.L("jmod_stored", I.Info(id).name or name))
        end
        -- what it carried, given to him as JMod does: its own inventory (what JMod refuses stays in
        -- it and is put down with it), its rounds
        if istable(ent.JModInv) and isfunction(J.AddToInventory) then
            ent.KeepJModInv = true
            for _, v in ipairs(table.Copy(ent.JModInv.items or {})) do J.AddToInventory(ply, v.ent) end
            for k, v in pairs(table.Copy(ent.JModInv.EZresources or {})) do
                J.AddToInventory(ply, { k, v })
                ent.JModInv.EZresources[k] = nil
            end
            ent.KeepJModInv = false
        end
        if istable(ent.ammoStored) then
            for k, v in pairs(ent.ammoStored) do J.GiveAmmo(ply, k, v) end
            ent.ammoStored = nil
        end
        ent:Remove()
    end
    J.AdvInvEquip = J.EZ_Equip_Armor
    J.RemoveArmorByID = function(ply, ID, broken, ...)
        if busy > 0 or not (IsValid(ply) and ply:IsPlayer()) then return rawRemove(ply, ID, broken, ...) end
        local cat = slotOfID(ply, ID)
        if not cat then return rawRemove(ply, ID, broken, ...) end
        if broken then
            -- destroyed: the item is gone, what it held is kept
            jmodRemove(ply, ID, true)
            ply.AdvInvJModBroken = true
            local _, contents = I.TakeOff(ply, cat)
            ply.AdvInvJModBroken = nil
            keepContents(ply, contents)
            return
        end
        -- taken off through JMod (its window, a piece taking the place): into the inventory; a vest or
        -- a backpack still holding things goes down with them, as the inventory drops it (its job
        -- flag and what it holds may forbid it: then it stays on)
        local full = (cat == "Vest" or cat == "Rucksack") and #I.Get(ply, cat) > 0
        if full then
            local may, why = I.MayLeaveSlot(ply, cat)
            if may then may, why = I.ContentsMayLeave(ply, cat) end
            if not may then
                if why then I.Tell(ply, why) end
                return
            end
        end
        local item, contents = I.TakeOff(ply, cat)
        if not item then return end
        if not full and I.Store(ply, item) then return end
        if not full and item.j then -- (a job's piece with no room: in the pockets, never on the ground)
            local pockets = I.Get(ply, "Uniform")
            if #pockets < I.MAX_ITEMS then
                pockets[#pockets + 1] = item
                I.MarkDirty(ply, "Uniform")
            end
            return
        end
        item.j = nil
        for _, it in ipairs(contents or {}) do it.j = nil end
        I.SpawnItem(item, I.DropPos(ply), contents)
    end
    J.AdvInvRemove = J.RemoveArmorByID
    -- Use on a JMod armour entity: picked up into the inventory, with its state
    I.EntityItemHandlers = I.EntityItemHandlers or {}
    for entClass, class in pairs(JB.ByEnt) do
        I.EntityItemHandlers[entClass] = function(ent)
            local id = I.ClassID[class]
            if id then return { id = id, r = 0, a = 0, x = writeState(entState(ent)) } end
        end
    end
end

-- one weight: the inventory's (the item's encombrement), not JMod's too
hook.Add("JMod_CalcArmorSpeed", "AdvInv_JMod", function(ply)
    local J = JM()
    local A = ply.EZarmor
    if not (J and istable(A) and J.ArmorTable) then return end
    local w = 0
    for cat in pairs(I.GearCat) do
        local name, _, id = slotPiece(ply, cat)
        local info = id and J.ArmorTable[name]
        if info then w = w + (tonumber(info.wgt) or 0) end
    end
    if w <= 0 then return end
    local total = math.max((A.totalWeight or 0) - w, 0)
    local mult = J.Config and J.Config.Armor and tonumber(J.Config.Armor.WeightMult) or 1
    A.speedfrac = math.Clamp(1 - (.8 * total / 250 * mult), .05, 1)
end)

---------------------------------------------------------------- resources

local snap = setmetatable({}, { __mode = "k" }) -- ply -> { type -> amount both sides had }
local idToType

local function bagTypes()
    if idToType then return idToType end
    idToType = {}
    for typ, class in pairs(JB.ResClass) do
        local id = I.ClassID[class]
        if id then idToType[id] = typ end
    end
    return idToType
end
hook.Add("AdvInv_ItemsInitialized", "AdvInv_JModRes", function() idToType = nil end)

local function bagCounts(ply)
    local byID, n = bagTypes(), {}
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        for _, it in ipairs(I.Get(ply, cont)) do
            local typ = byID[it.id]
            if typ then n[typ] = (n[typ] or 0) + (it.r or 0) end
        end
    end
    return n
end

local function takeBags(ply, typ, n)
    local id = I.ClassID[JB.ResClass[typ]]
    local bags = {}
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        for _, it in ipairs(I.Get(ply, cont)) do
            if it.id == id then bags[#bags + 1] = { cont, it } end
        end
    end
    table.sort(bags, function(a, b) return (a[2].r or 0) < (b[2].r or 0) end)
    local dirty = {}
    for _, b in ipairs(bags) do
        if n <= 0 then break end
        local t = math.min(n, b[2].r or 0)
        b[2].r = (b[2].r or 0) - t
        n = n - t
        dirty[b[1]] = true
    end
    for cont in pairs(dirty) do
        local list = I.Get(ply, cont)
        for k = #list, 1, -1 do
            if list[k].id == id and (list[k].r or 0) <= 0 then table.remove(list, k) end
        end
        I.MarkDirty(ply, cont)
    end
end

-- JMod boxes of a resource at pos (what the inventory had no room for)
local function spawnBoxes(J, typ, n, pos)
    local cls = J.EZ_RESOURCE_ENTITIES and J.EZ_RESOURCE_ENTITIES[typ]
    if not cls then return end
    local mult = J.Config and J.Config.ResourceEconomy and tonumber(J.Config.ResourceEconomy.MaxResourceMult) or 1
    local per, k = math.max(math.floor(100 * mult), 1), 0
    while n > 0 do
        local amt = math.min(per, n)
        n = n - amt
        local box = ents.Create(cls)
        if not IsValid(box) then return end
        box:SetPos(pos + Vector(0, 0, 12 * k))
        box:Spawn()
        box:Activate()
        if box.SetEZsupplies then box:SetEZsupplies(box.EZsupplies or typ, amt) end
        k = k + 1
    end
end

-- -> what went into bags
local function giveBags(ply, typ, n)
    local class = JB.ResClass[typ]
    local t = class and scripted_ents.GetStored(class)
    local ammo = t and t.t and t.t.Ammo
    if not ammo then return 0 end
    local left = I.GiveRounds(ply, ammo, n, false, true) or 0
    if left > 0 then
        spawnBoxes(JM(), typ, left, I.DropPos(ply))
        I.Tell(ply, I.L("jmod_no_room", left, I.Info(I.ClassID[class]).name or typ))
    end
    return n - left
end

local function sendInv(ply)
    local J = JM()
    local idx = J and J.NETWORK_INDEX and J.NETWORK_INDEX.ITEM_INVENTORY and J.NETWORK_INDEX.ITEM_INVENTORY.UPDATE
    if not (idx and istable(ply.JModInv)) then return end
    net.Start("JMod_ItemInventory")
    net.WriteEntity(ply)
    net.WriteInt(idx, 8)
    net.WriteTable(ply.JModInv)
    net.Send(ply)
end

-- JMod's resources and the bags agree: each side's change since they last agreed is applied to both.
local syncing = false
local paused = setmetatable({}, { __mode = "k" }) -- (JMod recounting his inventory: its copy is set aside)
function JB.SyncResources(ply)
    local J = JM()
    if syncing or paused[ply] or not (J and IsValid(ply) and ply.AdvInvJModResReady and ply:Alive()) then return end
    syncing = true
    ply.JModInv = ply.JModInv or table.Copy(J.DEFAULT_INVENTORY)
    ply.JModInv.EZresources = ply.JModInv.EZresources or {}
    local res = ply.JModInv.EZresources
    local s = snap[ply] or {}
    local bags = bagCounts(ply)
    local types = {}
    for t in pairs(res) do types[t] = true end
    for t in pairs(bags) do types[t] = true end
    for t in pairs(s) do types[t] = true end
    local changedJ = false
    for typ in pairs(types) do
        if JB.ResClass[typ] then
            local was, j, a = s[typ] or 0, math.max(math.floor(tonumber(res[typ]) or 0), 0), bags[typ] or 0
            local want = math.max(j + a - was, 0)
            if want > a then
                want = a + giveBags(ply, typ, want - a)
            elseif want < a then
                takeBags(ply, typ, a - want)
            end
            if want ~= j then
                res[typ] = want > 0 and want or nil
                changedJ = true
            end
            s[typ] = want > 0 and want or nil
        end
    end
    snap[ply] = s
    syncing = false
    if changedJ then sendInv(ply) end
end

-- start (spawn): JMod's resources are the bags (what JMod got since the spawn: into bags)
local function startResources(ply)
    local J = JM()
    if not (J and IsValid(ply) and ply:Alive()) then return end
    if ply.AdvInvJModResReady then return JB.SyncResources(ply) end -- (a spawn without a death)
    ply.JModInv = ply.JModInv or table.Copy(J.DEFAULT_INVENTORY)
    for typ, amt in pairs(table.Copy(ply.JModInv.EZresources or {})) do
        amt = math.floor(tonumber(amt) or 0)
        if JB.ResClass[typ] and amt > 0 then giveBags(ply, typ, amt) end
    end
    local bags = bagCounts(ply)
    ply.JModInv.EZresources = table.Copy(bags)
    snap[ply] = table.Copy(bags)
    ply.AdvInvJModResReady = true
    sendInv(ply)
end

local function wrapResources(J)
    local function wrap(key, after)
        local raw = J[key]
        if not isfunction(raw) or J["AdvInv" .. key] == raw then return end
        local f = function(...)
            local r = { raw(...) }
            after(...)
            return unpack(r)
        end
        J[key] = f
        J["AdvInv" .. key] = f
    end
    local function syncHolder(invEnt) if IsValid(invEnt) and invEnt:IsPlayer() then JB.SyncResources(invEnt) end end
    wrap("AddToInventory", syncHolder)
    wrap("RemoveFromInventory", syncHolder)
    wrap("ConsumeResourcesInRange", function()
        for _, p in ipairs(player.GetAll()) do JB.SyncResources(p) end
    end)
    -- its capacity counts JMod's own items only: the resources are in the bags
    local rawUpdate = J.UpdateInv
    if isfunction(rawUpdate) and J.AdvInvUpdateInv ~= rawUpdate then
        J.UpdateInv = function(invEnt, ...)
            if not (IsValid(invEnt) and invEnt:IsPlayer() and invEnt.AdvInvJModResReady) then return rawUpdate(invEnt, ...) end
            JB.SyncResources(invEnt)
            local inv = invEnt.JModInv
            local res = istable(inv) and inv.EZresources or {}
            if istable(inv) then inv.EZresources = {} end
            paused[invEnt] = true
            local r = { pcall(rawUpdate, invEnt, ...) }
            paused[invEnt] = nil
            if istable(invEnt.JModInv) then invEnt.JModInv.EZresources = res end
            if not r[1] then error(r[2], 0) end
            table.remove(r, 1)
            sendInv(invEnt)
            return unpack(r)
        end
        J.AdvInvUpdateInv = J.UpdateInv
    end
    -- the bags changed (sv_containers.lua counts the reserve after each change): JMod's too
    local sync = I.SyncAmmo
    if I.AdvInvJModSyncAmmo ~= sync then
        I.SyncAmmo = function(ply, ...)
            local r = { sync(ply, ...) }
            JB.SyncResources(ply)
            return unpack(r)
        end
        I.AdvInvJModSyncAmmo = I.SyncAmmo
    end
end

---------------------------------------------------------------- install

local function install()
    local J = JM()
    if not (J and JB) then return end
    I.JModActive = true
    wrapGiveAmmo(J)
    wrapArmor(J)
    wrapResources(J)
    -- a save: the pieces' live state with the items
    local ser = I.Serialize
    if isfunction(ser) and I.AdvInvJModSerialize ~= ser then
        I.Serialize = function(ply, ...)
            if IsValid(ply) then JB.RefreshState(ply) end
            return ser(ply, ...)
        end
        I.AdvInvJModSerialize = I.Serialize
    end
    I.Log.d("JMod", "JMod: its armour, resources and munitions go through the inventory")
end
hook.Add("InitPostEntity", "AdvInv_JMod", install)
if JM() and JB then install() end -- (a reload)

hook.Add("PlayerSpawn", "AdvInv_JMod", function(ply)
    if not I.JModActive then return end
    timer.Simple(1, function()
        if not (IsValid(ply) and ply:Alive()) then return end
        startResources(ply)
        JB.Reconcile(ply)
    end)
end)

-- Death: what the bags hold is the inventory's to leave on the body (or keep): JMod's copy is
-- emptied before its own death hooks (a drop or its corpse would make them twice)
local function died(ply)
    if not I.JModActive then return end
    JB.RefreshState(ply)
    ply.AdvInvJModResReady = nil
    snap[ply] = nil
    if istable(ply.JModInv) then ply.JModInv.EZresources = {} end
end
hook.Add("DoPlayerDeath", "AdvInv_JMod", died)
-- (a silent death, a DarkRP job change: no body, the inventory stays his; JMod forgets the pieces)
hook.Add("PlayerSilentDeath", "AdvInv_JMod", died)

timer.Create("AdvInv_JMod", 2, 0, function()
    if not I.JModActive then return end
    for _, ply in ipairs(player.GetAll()) do
        if ply:Alive() then
            JB.Reconcile(ply)
            JB.SyncResources(ply)
        end
    end
end)

-- Its corpse: ours instead, with its inventory in it.
local corpseHeld -- JMod's settings while we hold its corpses off (until the next tick)
hook.Add("AdvInv_DeathBody", "AdvInv_JMod", function(ply, body)
    local J = JM()
    local qol = J and J.Config and J.Config.QoL
    if not (qol and IsValid(body)) then return end
    local stay = corpseHeld and corpseHeld.stay or tonumber(qol.JModCorpseStayTime) or 0
    if stay <= 0 then return end
    -- (its PlayerDeath hook runs after this one, in the same tick: no corpse of its own this time;
    -- another death in the same tick finds the settings already held)
    if not corpseHeld then
        corpseHeld = { stay = qol.JModCorpseStayTime, drop = qol.JModInvDropOnDeath }
        qol.JModCorpseStayTime, qol.JModInvDropOnDeath = 0, false
        timer.Simple(0, function()
            qol.JModCorpseStayTime, qol.JModInvDropOnDeath = corpseHeld.stay, corpseHeld.drop
            corpseHeld = nil
        end)
    end
    local inv = ply.JModInv
    if not (inv and isfunction(J.AddToInventory) and isfunction(J.RemoveFromInventory)) then return end
    if not next(inv.items or {}) then return end
    -- (its corpse gets the player's capacity, as JMod does)
    body.EZstorageSpace = isfunction(J.GetStorageCapacity) and J.GetStorageCapacity(ply) or 10
    body.KeepJModInv = true
    for _, v in ipairs(table.Copy(inv.items or {})) do
        local removed = J.RemoveFromInventory(ply, v.ent, body:GetPos(), false, true)
        if IsValid(removed) then J.AddToInventory(body, removed) end
    end
end)
