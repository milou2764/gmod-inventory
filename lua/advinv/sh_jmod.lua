--[[
    JMod (Workshop 1919689921, global JMod) and the armour packs made for it (EFT Equipment Props +
    JMOD Armor, 2804625575): only when JMod is installed, nothing is registered without it.

    Its armour becomes inventory gear (sv_jmod.lua wears it through JMod):
      - one item per piece of JMod.ArmorTable (made when the game starts: the packs' own pieces too),
        worn in the slot of the body part it covers first: head -> helmet, chest or abdomen -> vest,
        back -> backpack, mouth and nose -> gas mask, eyes -> NVG, ears -> radio. Pieces for the
        limbs, suits (a playermodel of their own) and pieces drawn as part of the body stay JMod's;
      - protection, durability, charges (battery, filter), effects (night vision...) are JMod's; its
        storage is the item's capacity (x4); its encombrement is the slot's usual one;
      - drawn by the inventory: its fit for the playermodel (cl_fits_jmod*.lua, when computed), else
        where JMod places it (its bone and offsets, its own per-playermodel offsets too).
    Its resources become inventory items too: bags of each kind (wood, steel, fuel...), synchronised
    with JMod's inventory (sv_jmod.lua).
--]]
local I = AdvInv
local JB = I.JModBridge or {}
I.JModBridge = JB
JB.ByName = JB.ByName or {}   -- JMod armour name -> item class
JB.ByClass = JB.ByClass or {} -- item class -> JMod armour name
JB.ByEnt = JB.ByEnt or {}     -- JMod's armour entity class -> item class
JB.ResClass = JB.ResClass or {} -- JMod resource type -> item class
JB.ResOfAmmo = JB.ResOfAmmo or {} -- ammo type of the bags -> JMod resource type
JB.Bones = JB.Bones or { ["ValveBiped.Bip01_Head1"] = true, ["ValveBiped.Bip01_Neck1"] = true } -- the pieces' bones

JB.LOAD_PER_STORAGE = 4 -- inventory capacity of one unit of JMod storage
JB.BAG_SIZE = 100       -- resources in a bag (a JMod box holds 100)

-- a piece goes in the first slot whose body part it covers
-- (the EFT pack's own parts: a chest rig, glasses, a headset; its helmet accessories, scarves and
-- armbands stay JMod's)
local ORDER = {
    { "head", "Helmet" }, { "chest", "Vest" }, { "abdomen", "Vest" }, { "back", "Rucksack" },
    { "mouthnose", "Gasmask" }, { "eyes", "NVGs" }, { "ears", "Radio" },
    { "acc_chestrig", "Vest" }, { "acc_eyes", "NVGs" }, { "acc_ears", "Radio" },
}
-- encombrement by slot, as the other compatible gear (JMod's weights are on other scales: the EFT
-- pack's in kilograms, JMod's own up to 80)
local MASS = { Helmet = 13, Vest = 45, Rucksack = 20, Gasmask = 5, NVGs = 4, Radio = 3 }
function JB.CategoryOf(info)
    if not (istable(info) and istable(info.slots)) then return end
    for _, p in ipairs(ORDER) do
        if info.slots[p[1]] ~= nil then return p[2] end
    end
end

local function slug(s) return (string.lower(s):gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")) end

local function classFor(prefix, name)
    local s = slug(name)
    if s == "" then s = util.CRC(name) end
    local class = prefix .. s
    if #class > 60 then class = prefix .. string.sub(s, 1, 40) .. "_" .. util.CRC(name) end
    local taken = JB.ByClass[class]
    if taken and taken ~= name then class = class .. "_" .. util.CRC(name) end
    return class
end

-- Where JMod draws a piece (cl_armor.lua: offsets along the bone's right, forward and up, then
-- turns about those axes), as an inventory fit on the same bone.
function JB.AttachFromJMod(info)
    local p = isvector(info.pos) and info.pos or Vector(0, 0, 0)
    local a = isangle(info.ang) and info.ang or Angle(0, 0, 0)
    local ang = Angle(0, 0, 0)
    ang:RotateAroundAxis(Vector(0, -1, 0), a.p) -- (the bone's right)
    ang:RotateAroundAxis(Vector(0, 0, 1), a.y)  -- (up)
    ang:RotateAroundAxis(Vector(1, 0, 0), a.r)  -- (forward)
    local s = isvector(info.siz) and info.siz or Vector(1, 1, 1)
    return {
        bone = isstring(info.bon) and info.bon or "ValveBiped.Bip01_Head1",
        pos = Vector(p.y, -p.x, p.z), ang = ang, scale = (s.x + s.y + s.z) / 3,
    }
end

local EFT = { "Inventory: JMod EFT", "Inventaire : JMod EFT" }
local JMOD = { "Inventory: JMod", "Inventaire : JMod" }

local function registerArmor(name, info, eft)
    local cat = JB.CategoryOf(info)
    if not cat or info.plymdl or info.merge or not isstring(info.mdl) or info.mdl == "" then return end
    local class = classFor("advinv_jmod_", name)
    local storage = tonumber(info.storage) or 0
    local ENT = { Type = "anim" }
    ENT.Base = ({ Helmet = "advinv_base_helmet", Rucksack = "advinv_base_rucksack", Vest = "advinv_base_pocketvest" })[cat]
        or "advinv_base_gear"
    if cat == "Vest" and storage <= 0 then ENT.Base = "advinv_base_vest" end
    ENT.PrintName = isstring(info.PrintName) and info.PrintName or name
    local c = eft and EFT or JMOD
    ENT.Category = I.T(c[1], c[2])
    ENT.Author = eft and "EFT Equipment Props + JMOD Armor (Workshop 2804625575)" or "JMod (Workshop 1919689921)"
    ENT.Spawnable = false -- (JMod's own entities are in the spawn menu: picked up, they become this item)
    ENT.AdvInvCategory = cat
    ENT.Model = info.mdl
    ENT.Mass = MASS[cat] or 5
    ENT.Armor = 0 -- (JMod protects)
    if cat ~= "Helmet" then ENT.MaxLoad = storage > 0 and math.Round(storage * JB.LOAD_PER_STORAGE) or 0 end
    ENT.Attach = JB.AttachFromJMod(info)
    JB.Bones[ENT.Attach.bone] = true
    ENT.AdvInvJModName = name
    -- a piece another worn piece covers the same body part of: JMod would take that one off
    ENT.CanBeEquipped = function(_, ply) return JB.CanWear == nil or JB.CanWear(ply, name, cat) end
    -- pushed up or flipped away (JMod's toggle): drawn by JMod, in its toggled place
    ENT.HideWhenWorn = function(owner) return JB.Toggled(owner, name) end
    -- placed on another playermodel where it is on the reference one, after its head or chest
    ENT.AdaptAttach = function(pm, default) return JB.Adapt and JB.Adapt(cat, pm, default) end
    -- JMod's colour of the piece (chosen when it was put on)
    ENT.WornColor = function(owner)
        local _, e = JB.WornEntry(owner, name)
        return e and istable(e.col) and e.col or nil
    end
    scripted_ents.Register(ENT, class)
    I.Items[class] = true
    JB.ByName[name], JB.ByClass[class] = class, name
    if isstring(info.ent) then JB.ByEnt[info.ent] = class end
end

local function registerResource(typ, entClass)
    local ammo = "advinv_jmod_" .. slug(typ)
    local class = "advinv_jmod_res_" .. slug(typ)
    local stored = scripted_ents.GetStored(entClass)
    local t = stored and stored.t or {}
    -- (a box of its own kind, not a game ammo type: nothing to fire, and the game's ammo types are
    -- limited in number, JMod and weapon packs use many)
    local nice = string.gsub(" " .. typ, "%W%l", string.upper):sub(2)
    local ENT = { Type = "anim", Base = "advinv_base_ammobox" }
    ENT.PrintName = nice
    ENT.Category = I.T(JMOD[1], JMOD[2])
    ENT.Author = "JMod (Workshop 1919689921)"
    ENT.Spawnable = false
    ENT.Model = isstring(t.Model) and t.Model or "models/props_junk/cardboard_box004a.mdl"
    ENT.Ammo = ammo
    ENT.Rounds = JB.BAG_SIZE
    ENT.Capacity = JB.BAG_SIZE
    ENT.Mass = 10 -- (JMod: a box of 100 weighs 10)
    ENT.AdvInvJModResource = typ
    scripted_ents.Register(ENT, class)
    I.Items[class] = true
    JB.ResClass[typ] = class
    JB.ResOfAmmo[ammo] = typ
end

-- (JMod's own Initialize hooks merge the packs' tables: read them all, whichever ran first)
function JB.Register()
    local J = JMod
    if not istable(J) then return end
    I.JModActive = true
    -- (its flintlock pistol has no hold type of its own: its gun base's rifle one, and menu slot 3)
    I.WeaponCategory = I.WeaponCategory or {}
    I.WeaponCategory.wep_jack_gmod_flintlockpistol = I.WeaponCategory.wep_jack_gmod_flintlockpistol or "SecondaryWep"
    local eftNames = istable(J.EFTArmorTable) and J.EFTArmorTable or {}
    for _, tbl in ipairs({ J.ArmorTable, J.EFTArmorTable, J.AdditionalArmorTable }) do
        if istable(tbl) then
            for name, info in pairs(tbl) do
                if isstring(name) and not JB.ByName[name] then registerArmor(name, info, eftNames[name] ~= nil) end
            end
        end
    end
    if istable(J.EZ_RESOURCE_ENTITIES) then
        for typ, entClass in pairs(J.EZ_RESOURCE_ENTITIES) do
            if isstring(typ) and isstring(entClass) and not JB.ResClass[typ] then registerResource(typ, entClass) end
        end
    end
end
hook.Add("Initialize", "AdvInv_JMod", JB.Register)

function JB.CategoryOfClass(class)
    local t = scripted_ents.GetStored(class)
    return t and t.t and t.t.AdvInvCategory
end

-- The JMod piece worn as ply's item of that name (its entry in ply.EZarmor.items), if any.
function JB.WornEntry(ply, name)
    local items = ply.EZarmor and ply.EZarmor.items
    if not istable(items) then return end
    for id, e in pairs(items) do
        if istable(e) and e.name == name then return id, e end
    end
end

-- Pushed up / flipped away (JMod's toggle on a piece that has one)?
function JB.Toggled(ply, name)
    if not (IsValid(ply) and istable(JMod) and istable(JMod.ArmorTable)) then return false end
    local info = JMod.ArmorTable[name]
    if not (info and info.tgl) then return false end
    local _, e = JB.WornEntry(ply, name)
    return e and e.tgl and true or false
end

-- Is this JMod piece worn through the inventory (its item in its slot)?
function JB.WornAsItem(ply, name)
    local class = JB.ByName[name]
    local cat = class and JB.CategoryOfClass(class)
    return cat and ply:GetNW2Int(cat) == I.ClassID[class] or false
end

if CLIENT then
    --[[
        Its pieces on every playermodel: JMod places them for the reference body (male_07) with one
        offset from a bone. On another playermodel the piece keeps its place relative to the head
        (pieces on the head) or to the chest (vests, backpacks), measured on both meshes in their
        reference pose: the centre and the size (width + length) of the head, or of the chest 4 to
        14 units under the neck; the piece grows or shrinks with them (a backpack a little only).
    --]]
    local REF = "models/player/group01/male_07.mdl"
    local HEAD, NECK = "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Neck1"
    local SPINES = { "ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine4" }
    local measured = {}

    local function pct(sorted, q)
        local n = #sorted
        return sorted[math.Clamp(math.floor(q * (n - 1) + 1.5), 1, n)]
    end

    local SKULL = 4 -- the top units of the head a piece on the head is placed after

    -- centre and width + length of points (model space, z up), between two percentiles
    local function spread(pts, lo, hi)
        local xs, ys, zs = {}, {}, {}
        for i, p in ipairs(pts) do xs[i], ys[i], zs[i] = p.x, p.y, p.z end
        table.sort(xs) table.sort(ys) table.sort(zs)
        local x0, x1, y0, y1 = pct(xs, lo), pct(xs, hi), pct(ys, lo), pct(ys, hi)
        return Vector((x0 + x1) / 2, (y0 + y1) / 2, (pct(zs, lo) + pct(zs, hi)) / 2), (x1 - x0) + (y1 - y0)
    end

    -- A playermodel in its reference pose: its bones (name -> matrix), its head and chest (centre,
    -- size). false: it can't be read (once per playermodel: a heavy call, not made while drawing).
    function JB.Measure(mdl)
        local m = measured[mdl]
        if m ~= nil then return m end
        measured[mdl] = false
        local ok, meshes, bind = pcall(util.GetModelMeshes, mdl, 0, 0)
        if not (ok and istable(meshes) and istable(bind)) then return false end
        local tmp = ClientsideModel(mdl, RENDERGROUP_OTHER)
        if not IsValid(tmp) then return false end
        local res = false
        pcall(function()
            local base = bind[0] and 0 or 1
            local head, neck = tmp:LookupBone(HEAD), tmp:LookupBone(NECK)
            if not (head and neck) then return end
            -- (the bind matrices place the bones one way or the other: the head above the neck)
            local boneM
            for _, inverse in ipairs({ true, false }) do
                local function f(i)
                    local b = bind[i + base]
                    if not (b and b.matrix) then return end
                    return inverse and b.matrix:GetInverse() or b.matrix
                end
                local h, n = f(head), f(neck)
                if h and n and h:GetTranslation().z > n:GetTranslation().z and n:GetTranslation().z > 10 then boneM = f break end
            end
            if not boneM then return end
            -- (by name: a model just made gives no bone names yet, LookupBone works)
            local mats = {}
            for name in pairs(JB.Bones) do
                local i = tmp:LookupBone(name)
                if i then mats[name] = boneM(i) end
            end
            local spine = {}
            for _, n in ipairs(SPINES) do
                local i = tmp:LookupBone(n)
                if i then spine[i] = true end
            end
            local neckZ = mats[NECK]:GetTranslation().z
            local headPts, chestPts = {}, {}
            for _, msh in ipairs(meshes) do
                for _, v in ipairs(msh.triangles or {}) do
                    local best, bw = nil, -1
                    for _, w in ipairs(v.weights or {}) do
                        if w.weight > bw then best, bw = w.bone, w.weight end
                    end
                    if best == head then
                        headPts[#headPts + 1] = v.pos
                    elseif best and spine[best] and v.pos.z <= neckZ - 4 and v.pos.z >= neckZ - 14 then
                        chestPts[#chestPts + 1] = v.pos
                    end
                end
            end
            if #headPts < 20 or #chestPts < 50 then return end
            -- the skull: the top of the head (not the face, the jaw, hair hanging at the back)
            local zs = {}
            for i, p in ipairs(headPts) do zs[i] = p.z end
            table.sort(zs)
            local top = pct(zs, .98)
            local skull = {}
            for _, p in ipairs(headPts) do
                if p.z >= top - SKULL and p.z <= top then skull[#skull + 1] = p end
            end
            if #skull < 10 then return end
            local hc, hk = spread(skull, .02, .98)
            hc.z = top
            local cc, ck = spread(chestPts, .03, .97)
            res = { mats = mats, head = { c = hc, k = hk }, chest = { c = cc, k = ck } }
        end)
        tmp:Remove()
        measured[mdl] = res
        return res
    end

    -- The inventory's own items fitted to (nearly) every playermodel, by hand or by its fitting
    -- tools: a JMod piece follows the one of its slot from the reference body to the playermodel
    -- (its place, its size). Approved helmets snug on each head, masks on each face, a vest and a
    -- backpack on each chest and back: better than any measure of the mesh.
    local REFITEM = {
        Helmet = "advinv_barney_helmet", Radio = "advinv_barney_helmet",
        Gasmask = "advinv_cp_mask", NVGs = "advinv_cp_mask",
        Vest = "advinv_c_eft_6b23", Rucksack = "advinv_jetpack",
    }
    for _, c in pairs(REFITEM) do
        local t = scripted_ents.GetStored(c)
        local a = t and t.t and t.t.Attach
        if a and a.bone then JB.Bones[a.bone] = true end
    end
    JB.Bones["ValveBiped.Bip01_Spine2"] = true
    JB.Bones["ValveBiped.Bip01_Spine4"] = true

    local function fitOf(class, pm)
        local t = AdvInv.ClassTable(class)
        local base = t and t.Attach
        if not (base and base.bone) then return end
        local f = AdvInv.Fits and AdvInv.Fits[pm] and AdvInv.Fits[pm][class]
        if f then return base.bone, f[1], f[2], f[3] or 1 end
        if pm == REF then return base.bone, base.pos or vector_origin, base.ang or angle_zero, base.scale or 1 end
    end

    local function TR(pos, ang)
        local m = Matrix()
        m:SetTranslation(pos)
        m:SetAngles(ang)
        return m
    end

    local function byReference(cat, pm, default, t, r)
        local refc = REFITEM[cat]
        if not refc then return end
        local bt, pt, at, st = fitOf(refc, pm)
        local br, pr, ar, sr = fitOf(refc, REF)
        if not (bt and br) then return end
        local Mt, Mr = t.mats[bt], r.mats[br]
        local Mtp, Mrp = t.mats[default.bone], r.mats[default.bone]
        if not (Mt and Mr and Mtp and Mrp and sr > 0) then return end
        local k = st / sr
        -- the piece in the frame of the reference item on the reference body, carried into that
        -- item's frame on this playermodel (distances times the item's change of size)
        local rel = (Mr * TR(pr, ar)):GetInverseTR() * (Mrp * TR(default.pos or vector_origin, default.ang or angle_zero))
        rel:SetTranslation(rel:GetTranslation() * k)
        local L = Mtp:GetInverseTR() * (Mt * TR(pt, at)) * rel
        return { bone = default.bone, pos = L:GetTranslation(), ang = L:GetAngles(), scale = (default.scale or 1) * k }
    end

    -- A piece placed by JMod (default: on the reference body), adapted to playermodel pm: after the
    -- inventory's item of its slot fitted to that playermodel, else after its head or chest measured
    -- on its mesh (kept close: hair, a hood or kit in the mesh make it look bigger than it is).
    function JB.Adapt(cat, pm, default)
        if not (default and isstring(default.bone) and pm ~= "" and pm ~= REF) then return end
        local t, r = JB.Measure(pm), JB.Measure(REF)
        if not (t and r) then return end
        local a = byReference(cat, pm, default, t, r)
        if a then return a end
        local key = (cat == "Vest" or cat == "Rucksack") and "chest" or "head"
        local Bt, Br = t.mats[default.bone], r.mats[default.bone]
        if not (Bt and Br and r[key].k > 0) then return end
        local ratio = math.Clamp(t[key].k / r[key].k, .92, 1.1)
        local grow = cat == "Rucksack" and math.Clamp(ratio, .95, 1.05) or ratio
        local cr = Br:GetInverse() * r[key].c -- (the head's or the chest's centre, in the bone's frame)
        local ct = Bt:GetInverse() * t[key].c
        local shift = ct - cr
        local most = key == "head" and 1.5 or 2
        if shift:Length() > most then shift = shift:GetNormalized() * most end
        local pos = (default.pos or vector_origin)
        return {
            bone = default.bone, pos = cr + shift + (pos - cr) * ratio, ang = default.ang,
            scale = (default.scale or 1) * grow,
        }
    end

    -- JMod doesn't draw a piece the inventory draws (unless pushed up: then only JMod draws it)
    hook.Add("JMod_ArmorModelDraw", "AdvInv_JMod", function(ply, mdl, data, info)
        if not (istable(data) and data.name and JB.ByName[data.name]) then return end
        if not JB.WornAsItem(ply, data.name) then return end
        if data.tgl and info and info.tgl ~= nil and JMod.ArmorTable[data.name] and JMod.ArmorTable[data.name].tgl then return end
        return true
    end)

    -- JMod's per-playermodel offsets (its LuaConfig.ArmorOffsets) as fits, where none was computed
    hook.Add("AdvInv_ItemsInitialized", "AdvInv_JModFits", function()
        local offs = istable(JMod) and JMod.LuaConfig and JMod.LuaConfig.ArmorOffsets
        if not istable(offs) then return end
        AdvInv.Fits = AdvInv.Fits or {}
        for mdl, list in pairs(offs) do
            local key = string.lower(mdl)
            for name, o in pairs(list) do
                local class = JB.ByName[name]
                local base = class and JMod.ArmorTable[name]
                if base and istable(o) then
                    AdvInv.Fits[key] = AdvInv.Fits[key] or {}
                    if not AdvInv.Fits[key][class] then
                        local a = JB.AttachFromJMod({ pos = o.pos or base.pos, ang = o.ang or base.ang, siz = o.siz or base.siz, bon = base.bon })
                        AdvInv.Fits[key][class] = { a.pos, a.ang, a.scale }
                    end
                end
            end
        end
    end)
end
