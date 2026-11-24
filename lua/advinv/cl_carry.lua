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
-- On the back (weapons slung there) only armour counts: a plate carrier or a vest (ENT.Armor > 0)
-- adds C.CarryVestThickness, chest rigs, webbing and belts (no armour: straps) nothing; an item can
-- say how much it adds there with ENT.CarryBackThickness.
local function vestBack(vt)
    if vt.CarryBackThickness then return vt.CarryBackThickness end
    if vt.BlocksCarryZones and vt.BlocksCarryZones.front then return 0 end
    return (vt.Armor or 0) > 0 and C.CarryVestThickness or 0
end
C.CarryGap = C.CarryGap or 0.3
-- modes that rest on the upper back, where a backpack is: the weapon hangs beside the pack (moved
-- sideways, away from the body's middle, until it clears it); C.CarryBesidePack = false: it goes
-- over it instead (pushed out by the pack's thickness)
C.CarryOverPack = C.CarryOverPack or { sling_up = true, sling_down = true }
if C.CarryBesidePack == nil then C.CarryBesidePack = true end
-- beside the pack: part of the weapon's depth that goes forward of the back (0: all of it behind);
-- sideways in line with the shoulder joint (C.CarryBesideShoulder = false: against the pack's side)
C.CarryBesideForward = C.CarryBesideForward or 0.75

I.CarryOffsets = I.CarryOffsets or {}
I.CarryAliases = I.CarryAliases or {}
I.CarryStack = I.CarryStack or {}
I.CarryTemplates = I.CarryTemplates or {}
I.CarryTuned = I.CarryTuned or {}

local BACK_SIDE = { sling_up = true, sling_down = true }

-- (keyed by playermodel path: lowercase, as every lookup is; cl_gear.lua)
AdvInv.LowerKeys(I.CarryOffsets)
AdvInv.LowerKeys(I.CarryAliases)
for k, v in pairs(I.CarryAliases or {}) do
    if isstring(v) then I.CarryAliases[k] = string.lower(v) end
end

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
    -- its anchor (t.anchor): its middle, or its butt (muzzle +X: the butt is its lowest X) for the
    -- modes whose butt has its place, a longer gun going further from it
    local ax = t.anchor == "butt" and mn.x or (mn.x + mx.x) / 2
    local inner = Vector(ax, yAxis:Dot(out) > 0 and lo or hi, (mn.z + mx.z) / 2)
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
-- launcher / primary weapon going over each other when they cross on the back side. out.beside:
-- slot -> half width of the backpack the weapon hangs beside (I.CarryBeside).
function I.CarryPushes(ent, gearOwner, carried)
    local out = {}
    local vestID = IsValid(gearOwner) and gearOwner:GetNW2Int("Vest") or 0
    local vest = vestID > 1
    local vt = vest and I.EntityTable(vestID)
    local back = vt and vestBack(vt) or (vest and C.CarryVestThickness) or 0
    local pack = IsValid(gearOwner) and I.BackpackThickness(gearOwner) or 0
    for cat, w in pairs(carried) do
        local push = 0
        if vest then push = push + (I.CarryZone[w.mode] == "front" and C.CarryVestThickness or back) end
        if pack > 0 and C.CarryOverPack[w.mode] then
            if C.CarryBesidePack then
                out.beside = out.beside or {}
                out.beside[cat] = I.BackpackHalfWidth(gearOwner)
            else
                push = push + pack
            end
        end
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

-- Copy of an angle turned by deg around a world axis.
local function turned(a, axis, deg)
    local t = Angle(a.p, a.y, a.r)
    t:RotateAroundAxis(axis, deg)
    return t
end

--[[
    A weapon slung over the shoulder of a backpack wearer hangs against the side of the pack:
      - its length along the pack's side (its sideways lean taken out, its lean back kept);
      - a quarter turn on itself: its flat side against the pack, its top (the sights) to the back;
      - its inner side against the pack (half its width and the gap from the body's middle, between
        the collarbones), its front edge where the mode put it (against the back).
    -> new world position and angles
--]]
function I.CarryBeside(ent, w, pos, ang, halfWidth)
    local g = halfWidth and halfWidth > 0 and I.WeaponGeometry(w.model)
    local l = ent:LookupBone("ValveBiped.Bip01_L_Clavicle")
    local r = ent:LookupBone("ValveBiped.Bip01_R_Clavicle")
    local ml, mr = l and ent:GetBoneMatrix(l), r and ent:GetBoneMatrix(r)
    if not (g and ml and mr) then return pos, ang end
    local pl, pr = ml:GetTranslation(), mr:GetTranslation()
    local right = pr - pl
    right.z = 0
    if right:LengthSqr() < 0.01 then return pos, ang end
    right:Normalize()
    local back = -Vector(0, 0, 1):Cross(right) -- (forward = up x right)
    local center = (pl + pr) / 2
    local scale = ent:GetModelScale()
    -- its main body (the core band: small parts sticking out may touch the pack)
    local ylo, yhi = g.core.y.lo, g.core.y.hi
    local zlo, zhi = g.core.z.lo, g.core.z.hi
    local function cornersAt(p, a)
        local list, mid = {}, Vector(0, 0, 0)
        for k = 0, 7 do
            local c = Vector(bit.band(k, 1) > 0 and g.maxs.x or g.mins.x, bit.band(k, 2) > 0 and yhi or ylo,
                bit.band(k, 4) > 0 and zhi or zlo)
            list[k + 1] = LocalToWorld(c * scale, angle_zero, p, a)
            mid = mid + list[k + 1] / 8
        end
        return list, mid
    end
    local c0, mid = cornersAt(pos, ang)
    -- the side it hangs on (its middle, not its model's origin: often at the grip)
    local side = (mid - center):Dot(right) >= 0 and 1 or -1
    local front0 = math.huge
    for _, p in ipairs(c0) do front0 = math.min(front0, (p - center):Dot(back)) end
    local midLocal = WorldToLocal(mid, angle_zero, pos, ang)
    -- its length along the pack's side
    local a = Angle(ang.p, ang.y, ang.r)
    local f = a:Forward()
    local target = f - right * f:Dot(right)
    if target:LengthSqr() > 1e-4 then
        target:Normalize()
        local axis = f:Cross(target)
        local s = axis:Length()
        if s > 1e-4 then
            axis:Normalize()
            local deg = math.deg(math.atan2(s, f:Dot(target)))
            local t = turned(a, axis, deg)
            if t:Forward():Dot(target) < 0.999 then t = turned(a, axis, -deg) end
            a = t
        end
    end
    -- a quarter turn on itself: flat side against the pack, top to the back
    local t1, t2 = turned(a, a:Forward(), 90), turned(a, a:Forward(), -90)
    a = t1:Up():Dot(back) >= t2:Up():Dot(back) and t1 or t2
    local p2 = mid - LocalToWorld(midLocal, angle_zero, vector_origin, a) -- (its middle stays put)
    -- against the pack's side; forward: part of its depth (C.CarryBesideForward) in front of where
    -- the mode put its front edge (against the back), beside the body
    local c2 = cornersAt(p2, a)
    local inner, outer, front, rear = math.huge, -math.huge, math.huge, -math.huge
    for _, p in ipairs(c2) do
        local l = side * (p - center):Dot(right)
        inner, outer = math.min(inner, l), math.max(outer, l)
        local d = (p - center):Dot(back)
        front, rear = math.min(front, d), math.max(rear, d)
    end
    local want = front0 - (rear - front) * (C.CarryBesideForward or 0)
    -- sideways: in line with the shoulder joint (the sling hangs from it), else against the pack's side
    local shift = halfWidth * scale + C.CarryGap - inner
    local arm = ent:LookupBone(side > 0 and "ValveBiped.Bip01_R_UpperArm" or "ValveBiped.Bip01_L_UpperArm")
    local am = C.CarryBesideShoulder ~= false and arm and ent:GetBoneMatrix(arm)
    if am then shift = side * (am:GetTranslation() - center):Dot(right) - (inner + outer) / 2 end
    p2 = p2 + right * (side * shift) + back * (want - front)
    return p2, a
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
