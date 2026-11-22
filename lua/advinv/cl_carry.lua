--[[
    Carry modes, client side: where a carried long gun is drawn (rules in sh_carry.lua).

    Offsets (cl_carry_data.lua, made by tools/fit_carry.py): playermodel -> offset set (models with
    the same proportions share one, I.CarryAliases) -> weapon class -> mode ->
    { bone, position, angles, outward direction }. Looked up in this order:
        1. values tuned in game this session (advinv_carry_tune, I.CarryTuned[set][class][mode])
        2. I.CarryOffsets[playermodel path] (a server can add a set for one model under its path)
        3. I.CarryOffsets[alias set of the playermodel], else the "default" set
        4. a weapon without offsets (another addon's): the mode's template, fitted to its shape
    Pushed along the outward direction by worn gear (vest, backpack for the shoulder modes) and,
    when two guns are carried on the back side and cross, one over the other (I.CarryStack).
--]]
local I = AdvInv
local C = I.Config

C.CarryVestThickness = C.CarryVestThickness or 2 -- a worn vest adds this much around the torso
C.CarryGap = C.CarryGap or 0.3
-- modes that rest on the upper back, where a backpack is: they go over it
C.CarryOverPack = C.CarryOverPack or { sling_up = true, sling_down = true }

I.CarryOffsets = I.CarryOffsets or {}
I.CarryAliases = I.CarryAliases or {}
I.CarryStack = I.CarryStack or {}
I.CarryTemplates = I.CarryTemplates or {}
I.CarryTuned = I.CarryTuned or {}

local BACK_SIDE = { sling_up = true, sling_down = true, cross_body = true, back_carry = true }

-- Offset set of a playermodel: (set table, set name).
local setCache, cacheData = {}, nil
function I.CarrySetFor(playermodel)
    if cacheData ~= I.CarryOffsets then -- data reloaded (lua refresh): set names may have changed
        setCache, cacheData = {}, I.CarryOffsets
    end
    local key = string.lower(playermodel or "")
    local name = setCache[key]
    if not name then
        if I.CarryOffsets[key] then
            name = key
        else
            name = I.CarryAliases[key]
            if not (name and I.CarryOffsets[name]) then name = "default" end
        end
        setCache[key] = name
    end
    return I.CarryOffsets[name] or {}, name
end

-- Template placement of a weapon that has no offsets: the mode's rules on the default body,
-- fitted to the weapon's shape (it rests on its thinner side, muzzle as the mode wants).
local templateCache = {}
local function templateEntry(mode, path)
    local key = mode .. "|" .. path
    if templateCache[key] ~= nil then return templateCache[key] or nil end
    local t = I.CarryTemplates[mode]
    local g = t and I.WeaponGeometry(path)
    if not g then
        templateCache[key] = false
        return
    end
    -- model -> canonical frame (muzzle +X, resting side Y): like tools/fit_carry.py Weapon.Q
    local Q = Matrix()
    if g.muzzleBack then Q = Matrix({ { -1, 0, 0, 0 }, { 0, -1, 0, 0 }, { 0, 0, 1, 0 }, { 0, 0, 0, 1 } }) end
    local cy, cz = g.core.y, g.core.z
    if (cy.hi - cy.lo) > (cz.hi - cz.lo) then
        Q = Matrix({ { 1, 0, 0, 0 }, { 0, 0, -1, 0 }, { 0, 1, 0, 0 }, { 0, 0, 0, 1 } }) * Q
    end
    -- canonical bounds
    local mn = Vector(math.huge, math.huge, math.huge)
    local mx = Vector(-math.huge, -math.huge, -math.huge)
    for _, x in ipairs({ g.mins.x, g.maxs.x }) do
        for _, y in ipairs({ g.mins.y, g.maxs.y }) do
            for _, z in ipairs({ g.mins.z, g.maxs.z }) do
                local p = Q * Vector(x, y, z)
                mn.x, mn.y, mn.z = math.min(mn.x, p.x), math.min(mn.y, p.y), math.min(mn.z, p.z)
                mx.x, mx.y, mx.z = math.max(mx.x, p.x), math.max(mx.y, p.y), math.max(mx.z, p.z)
            end
        end
    end
    local R = Matrix()
    R:SetAngles(t.ang)
    local out = t.out:GetNormalized()
    -- the main body's band across canonical Y rests on the body (parts sticking out may sink in)
    local lo, hi
    if (cy.hi - cy.lo) > (cz.hi - cz.lo) then
        lo, hi = -cz.hi, -cz.lo
    elseif g.muzzleBack then
        lo, hi = -cy.hi, -cy.lo
    else
        lo, hi = cy.lo, cy.hi
    end
    -- canonical Y in the bone frame: which of its faces looks at the body
    local yAxis = R * Vector(0, 1, 0)
    local inner = Vector((mn.x + mx.x) / 2, yAxis:Dot(out) > 0 and lo or hi, (mn.z + mx.z) / 2)
    local pos = t.pos + out * C.CarryGap - R * inner
    local M = R * Q
    local e = { bone = t.bone, pos = pos, ang = M:GetAngles(), out = out }
    templateCache[key] = e
    return e
end

-- Placement entry { bone, pos, ang, out } of a weapon class / world model in a mode on ent.
function I.CarryEntry(ent, class, mode, path)
    local set, name = I.CarrySetFor(ent:GetModel())
    local tuned = I.CarryTuned[name] and I.CarryTuned[name][class]
    if tuned and tuned[mode] then return tuned[mode], name end
    local w = class and set[class]
    local e = w and w[mode]
    if e then
        if not e.bone then -- data rows are { bone, pos, ang, out }: name the fields once
            e.bone, e.pos, e.ang, e.out = e[1], e[2], e[3], (e[4] or Vector(0, 1, 0)):GetNormalized()
        end
        return e, name
    end
    if not path then return nil, name end
    return templateEntry(mode, path), name
end

local function hasOffsets(ent, class, mode)
    local set = I.CarrySetFor(ent:GetModel())
    return class and set[class] and set[class][mode] ~= nil
end

-- Pushes along the outward direction of each carried weapon (slot -> units): worn gear, and the
-- launcher / primary weapon going over each other when they cross on the back side.
function I.CarryPushes(ent, gearOwner, carried)
    local out = {}
    local vest = IsValid(gearOwner) and gearOwner:GetNW2Int("Vest") > 1
    local pack = IsValid(gearOwner) and I.BackpackThickness(gearOwner) or 0
    for cat, w in pairs(carried) do
        local push = 0
        if vest then push = push + C.CarryVestThickness end
        if pack > 0 and C.CarryOverPack[w.mode] then push = push + pack end
        out[cat] = push
    end
    local l, p = carried.RocketLauncher, carried.PrimaryWep
    if l and p and BACK_SIDE[l.mode] and BACK_SIDE[p.mode] and I.CarryZone[l.mode] ~= I.CarryZone[p.mode] then
        if hasOffsets(ent, l.class, l.mode) and hasOffsets(ent, p.class, p.mode) then
            local _, name = I.CarrySetFor(ent:GetModel())
            local v = I.CarryStack[name] and I.CarryStack[name][("%s %s|%s %s"):format(l.class, l.mode, p.class, p.mode)]
            if v and v > 0 then out.RocketLauncher = out.RocketLauncher + v end
            if v and v < 0 then out.PrimaryWep = out.PrimaryWep - v end
        else
            -- weapons without computed pairs: the launcher goes over the primary weapon
            local g = I.WeaponGeometry(p.model)
            if g then
                local cy, cz = g.core.y, g.core.z
                out.RocketLauncher = out.RocketLauncher + math.min(cy.hi - cy.lo, cz.hi - cz.lo) + C.CarryGap
            end
        end
    end
    return out
end

-- World position and angles of a carried weapon w = { cat, class, model, mode } on ent, pushed out
-- by push units; nil if it cannot be placed (no entry, or the playermodel lacks the bone).
function I.CarryTransform(ent, w, push)
    local e = I.CarryEntry(ent, w.class, w.mode, w.model)
    if not e then return end
    local bone = ent:LookupBone(e.bone)
    local matrix = bone and ent:GetBoneMatrix(bone)
    if not matrix then return end
    local localPos = e.pos
    if push and push ~= 0 then localPos = localPos + e.out * push end
    return LocalToWorld(localPos * ent:GetModelScale(), e.ang, matrix:GetTranslation(), matrix:GetAngles())
end

---------------------------------------------------------------- menu

-- Fills a DermaMenu with the "Carry mode" submenu of the long gun in slot cat (nothing for other
-- weapons). Modes that cannot be chosen are greyed out with the reason.
function I.AddCarryMenu(menu, cat)
    local ply = LocalPlayer()
    if not table.HasValue(I.CARRY_CATS, cat) then return end
    local conf = I.CarryConfig(I.SlotRef(ply, cat))
    if not conf then return end
    local sub, parent = menu:AddSubMenu(I.L("carry_menu"))
    parent:SetIcon("icon16/arrow_rotate_clockwise.png")
    local current = I.CarryMode(ply, cat)
    for _, mode in ipairs(conf.modes) do
        local ok, why = true, nil
        if mode ~= current then ok, why = I.CarryAllowed(ply, cat, mode) end
        local label = I.L("carry_" .. mode)
        if not ok and why then label = label .. "  (" .. why .. ")" end
        local opt = sub:AddOption(label, function()
            if not ok or mode == current then return end
            I.Act(I.ACT.CARRY, function()
                net.WriteUInt(AdvInv.CategoryID[cat], 4)
                net.WriteUInt(I.CARRY_INDEX[mode], I.CARRY_NET_BITS)
            end)
        end)
        if mode == current then opt:SetIcon("icon16/tick.png") end
        if not ok then
            opt:SetEnabled(false)
            opt:SetTextColor(Color(150, 150, 150))
            if why then opt:SetTooltip(why) end
        end
    end
end
