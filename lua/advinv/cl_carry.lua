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
-- On the back (weapons slung there) what the vest's model has there: ENT.CarryBackThickness, else
-- its measured thickness (AdvInv.VestBackThickness, cl_vest_back.lua made by tools/vest_back.py:
-- 0 for chest rigs, the panel of a plate carrier or a soft vest), else a guess: a chest rig
-- (front only) nothing, armour C.CarryVestThickness, webbing and belts (no armour: straps) nothing.
local function vestBack(vt, class)
    if vt.CarryBackThickness then return vt.CarryBackThickness end
    local measured = I.VestBackThickness and class and I.VestBackThickness[class]
    if measured then return measured end
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
-- weapons without offsets: the gun the mode templates were fitted with (tools/fit_carry.py), and
-- the modes where a longer gun hangs from where that gun's butt is instead of being centred
C.CarryTemplateGun = C.CarryTemplateGun or "models/weapons/w_irifle.mdl"
C.CarryLongHang = C.CarryLongHang or { front_hang = true }
-- weapons without offsets stand off the body that much more in these modes (their magazine, scope or
-- grip, sticking out toward the chest, sink in otherwise: measured on the M9K, TFA and ARC9 packs)
C.CarryTemplateGap = C.CarryTemplateGap or { front_hang = 1.2, sling_up = 0.5, sling_down = 1.2 }

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

-- The mode's template on a playermodel's offset set: the template fits the default body; on another
-- set it moves as the template gun (C.CarryTemplateClass) moves from the default set to that one
-- (a bulkier chest, a deeper back: tuned per set), else it is the default body's.
C.CarryTemplateClass = C.CarryTemplateClass or "weapon_ar2"
local function row(e)
    if not e then return end
    return e.bone or e[1], e.pos or e[2], e.ang or e[3], e.out or e[4]
end
local setTemplates = {}
local function templateFor(mode, setName)
    local t = I.CarryTemplates[mode]
    if not t or not setName or setName == "default" then return t end
    local key = mode .. "|" .. setName
    local c = setTemplates[key]
    if c ~= nil then return c or t end
    setTemplates[key] = false
    local d = I.CarryOffsets.default and I.CarryOffsets.default[C.CarryTemplateClass]
    local s = I.CarryOffsets[setName] and I.CarryOffsets[setName][C.CarryTemplateClass]
    local bd, pd, ad = row(d and d[mode])
    local bs, ps, as, os = row(s and s[mode])
    if not (bd and bs and bd == bs and bd == t.bone and pd and ps and ad and as) then return t end
    -- delta = set row * default row^-1, in the bone's frame
    local Md, Ms = Matrix(), Matrix()
    Md:SetTranslation(pd) Md:SetAngles(ad)
    Ms:SetTranslation(ps) Ms:SetAngles(as)
    local Mt = Matrix()
    Mt:SetTranslation(t.pos) Mt:SetAngles(t.ang)
    local M = Ms * Md:GetInverseTR() * Mt
    local R = Matrix()
    R:SetAngles((Ms * Md:GetInverseTR()):GetAngles())
    c = { bone = t.bone, pos = M:GetTranslation(), ang = M:GetAngles(), out = (os and os:GetNormalized()) or (R * t.out),
        anchor = t.anchor }
    setTemplates[key] = c
    return c
end

-- Template placement of a weapon that has no offsets: the mode's rules on the playermodel's set,
-- fitted to the weapon's shape (it rests on its thinner side, muzzle as the mode wants).
local templateCache = {}
local function templateEntry(mode, path, setName)
    local key = mode .. "|" .. path .. "|" .. (setName or "default")
    local t = templateFor(mode, setName)
    local g = t and I.WeaponGeometry(path)
    local e = templateCache[key]
    -- (built on the weapon's current shape: a shape measured again is a new table)
    if e == false or (e and e.geom == g) then return e or nil end
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
    local face, zmid = yAxis:Dot(out) > 0 and lo or hi, (mn.z + mx.z) / 2
    local inner = Vector(ax, face, zmid)
    local gap = C.CarryGap + (C.CarryTemplateGap[mode] or 0)
    local pos = t.pos + out * gap - R * inner
    -- a gun longer than the one the templates were fitted with, in the modes that would centre it
    -- (C.CarryLongHang: the front carry): its butt where that gun's butt is, turned toward the
    -- vertical so it spans no wider; the extra length hangs down (centred, a 130 cm rifle stuck out
    -- past the shoulder)
    local ref = C.CarryLongHang[mode] and t.anchor ~= "butt" and I.WeaponGeometry(C.CarryTemplateGun)
    local refLen, len = ref and (ref.maxs.x - ref.mins.x), mx.x - mn.x
    if refLen and len > refLen + 0.5 then
        local d = t.ang:Forward() -- muzzle direction (bone frame: the template's angles)
        local up = Vector(1, 0, 0) -- the spine bone's length axis
        up = (up - out * up:Dot(out)):GetNormalized()
        local side = out:Cross(up)
        local s, u, n = d:Dot(side), d:Dot(up), d:Dot(out)
        local s2 = s * refLen / len
        local u2 = (u < 0 and -1 or 1) * math.sqrt(math.max(0, 1 - s2 * s2 - n * n))
        local d2 = (side * s2 + up * u2 + out * n):GetNormalized()
        local a = Angle(t.ang.p, t.ang.y, t.ang.r)
        local axis = d:Cross(d2)
        if axis:Length() > 1e-5 then
            local deg = math.deg(math.atan2(axis:Length(), d:Dot(d2)))
            axis:Normalize()
            local a1 = Angle(a.p, a.y, a.r)
            a1:RotateAroundAxis(axis, deg)
            if a1:Forward():Dot(d2) < 0.999 then
                a1 = Angle(a.p, a.y, a.r)
                a1:RotateAroundAxis(axis, -deg)
            end
            a = a1
        end
        R = Matrix()
        R:SetAngles(a)
        local butt = t.pos + out * gap - d * (refLen / 2)
        pos = butt - R * Vector(mn.x, face, zmid)
    end
    local M = R * Q
    e = { bone = t.bone, pos = pos, ang = I.GeomToModelAngles(g, M:GetAngles()), out = out, geom = g }
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
    return templateEntry(mode, path, name), name
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
    local back = vt and vestBack(vt, I.IDClass and I.IDClass[vestID]) or (vest and C.CarryVestThickness) or 0
    local pack = IsValid(gearOwner) and I.BackpackThickness(gearOwner) or 0
    for cat, w in pairs(carried) do
        local push = 0
        if vest then
            local v = I.CarryZone[w.mode] == "front" and C.CarryVestThickness or back
            push = push + v
            -- (what the vest adds: replaced by the room the drawn vest really takes, I.CarryVestClearance)
            out.vest = out.vest or {}
            out.vest[cat] = v
        end
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

--[[
    How far a carried weapon must go out to clear the vest really drawn on its wearer (the fixed
    thickness above guessed it: a slim body's vest left rifles hanging off its back, a thick vest
    swallowed them). The vest's surface (its mesh, the parts its model hides left out) and the
    weapon's (its mesh at rest) are compared along the weapon's outward direction, cell by cell
    across it: the push puts the weapon's inner side C.CarryGap above the vest's outer side where
    they overlap, 0 where the weapon doesn't pass over the vest. nil when it can't be measured (the
    fixed thickness is kept): a bonemerged vest, a model that can't be read. Worked out again when
    something changes, else every C.CarryVestClearanceEvery seconds (the pose moves the torso).
--]]
C.CarryVestClearanceEvery = C.CarryVestClearanceEvery or 0.5
local CELL = 1 -- size of a cell across the weapon (units)
local MAX_PUSH = 8
local VEST_POINTS, WEP_POINTS = 6000, 500

-- Points spread over a model's visible surface, in its own space at rest (sequence 0): its mesh
-- skinned by a temporary copy's bones (the bind matrices taken whichever way fits in its hull),
-- triangles of hidden materials (submaterial "nodraw") left out, big triangles filled in.
local function surfacePoints(model, bodyValue, hidden, budget)
    local ok, meshes, bind = pcall(util.GetModelMeshes, model, 0, bodyValue or 0)
    if not ok or not istable(meshes) or not istable(bind) then return end
    local tmp = ClientsideModel(model, RENDERGROUP_OTHER)
    if not IsValid(tmp) then return end
    local pts
    local okRun = pcall(function()
        tmp:SetNoDraw(true)
        tmp:SetPos(vector_origin)
        tmp:SetAngles(angle_zero)
        tmp:ResetSequence(0)
        tmp:SetCycle(0)
        tmp:InvalidateBoneCache()
        tmp:SetupBones()
        local hmin, hmax = tmp:GetModelBounds()
        local base = bind[0] and 0 or 1
        for _, invert in ipairs({ false, true }) do
            local K, bad = {}, false
            local function skin(v)
                local p = Vector(0, 0, 0)
                local weights = v.weights
                if not weights or #weights == 0 then weights = { { bone = 0, weight = 1 } } end
                for _, w in ipairs(weights) do
                    local k = K[w.bone]
                    if not k then
                        local bm, bp = tmp:GetBoneMatrix(w.bone), bind[w.bone + base]
                        if not (bm and bp and bp.matrix) then bad = true return p end
                        k = bm * (invert and bp.matrix:GetInverse() or bp.matrix)
                        K[w.bone] = k
                    end
                    p = p + (k * v.pos) * w.weight
                end
                return p
            end
            local tris, area = {}, 0
            for _, m in ipairs(meshes) do
                if not hidden[string.lower(m.material or "")] then
                    local tri = m.triangles or {}
                    for i = 1, #tri - 2, 3 do
                        local a, b, c = skin(tri[i]), skin(tri[i + 1]), skin(tri[i + 2])
                        if bad then break end
                        local s = (b - a):Cross(c - a):Length() / 2
                        tris[#tris + 1] = { a, b, c, s }
                        area = area + s
                    end
                end
                if bad then break end
            end
            if not bad and #tris > 0 then
                -- inside the hull (with some room): the right way round
                local tol, fits = Vector(3, 3, 3), true
                for i = 1, #tris, math.max(1, math.floor(#tris / 50)) do
                    if not tris[i][1]:WithinAABox(hmin - tol, hmax + tol) then fits = false break end
                end
                if fits then
                    pts = {}
                    local per = budget / math.max(area, 1e-3) -- points per square unit
                    local acc = 0
                    for _, t in ipairs(tris) do
                        acc = acc + t[4] * per
                        local n = math.floor(acc)
                        acc = acc - n
                        if n >= 1 then pts[#pts + 1] = (t[1] + t[2] + t[3]) / 3 end
                        for k = 2, n do -- more inside a big triangle
                            local r1, r2 = (k * 0.618) % 1, (k * 0.382 + 0.5) % 1
                            if r1 + r2 > 1 then r1, r2 = 1 - r1, 1 - r2 end
                            pts[#pts + 1] = t[1] + (t[2] - t[1]) * r1 + (t[3] - t[1]) * r2
                        end
                    end
                    for _, t in ipairs(tris) do -- and the corners
                        if #pts >= budget * 1.5 then break end
                        pts[#pts + 1] = t[1]
                    end
                    return
                end
            end
        end
    end)
    tmp:Remove()
    return okRun and pts or nil
end

local vestCache, wepCache = {}, {}

local function vestKey(g)
    local v, mul = 0, 1
    for _, bg in ipairs(g:GetBodyGroups() or {}) do
        v = v + g:GetBodygroup(bg.id) * mul
        mul = mul * math.max(bg.num or 1, 1)
    end
    local hidden, hk = {}, {}
    local mats = g:GetMaterials() or {}
    for i, m in ipairs(mats) do
        local sub = g:GetSubMaterial(i - 1)
        if sub and sub ~= "" and string.lower(sub) == I.NODRAW_MATERIAL then
            hidden[string.lower(m)] = true
            hk[#hk + 1] = i
        end
    end
    return g:GetModel() .. "|" .. v .. "|" .. table.concat(hk, ","), v, hidden
end

-- the vest's points and its heightfields (per outward direction, in its space scaled by s)
local function vestData(g)
    local key, bodyValue, hidden = vestKey(g)
    local d = vestCache[key]
    if d == nil then
        local pts = surfacePoints(g:GetModel(), bodyValue, hidden, VEST_POINTS)
        d = pts and { pts = pts, fields = {} } or false
        vestCache[key] = d
    end
    return d or nil
end

local function basisOf(dir)
    local a = dir:Cross(Vector(0, 0, 1))
    if a:LengthSqr() < 1e-4 then a = dir:Cross(Vector(1, 0, 0)) end
    a:Normalize()
    local b = dir:Cross(a)
    b:Normalize()
    return a, b
end

-- highest point of the vest along dir per cell across it (dir in the vest's space, scale s)
local function heightField(d, dir, s)
    local fk = ("%.2f %.2f %.2f %.2f"):format(dir.x, dir.y, dir.z, s)
    local f = d.fields[fk]
    if f then return f end
    local a, b = basisOf(dir)
    f = { a = a, b = b, h = {} }
    local h = f.h
    for _, p in ipairs(d.pts) do
        local q = p * s
        local k = math.floor(q:Dot(a) / CELL) * 4096 + math.floor(q:Dot(b) / CELL)
        local z = q:Dot(dir)
        if not h[k] or z > h[k] then h[k] = z end
    end
    d.fields[fk] = f
    return f
end

local function weaponPoints(path)
    local p = wepCache[path]
    if p == nil then
        p = surfacePoints(path, 0, {}, WEP_POINTS) or false
        wepCache[path] = p
    end
    return p or nil
end

local clearCache = setmetatable({}, { __mode = "k" })

-- -> units to push w (on ent, already pushed by otherPush) out to clear gearOwner's vest, or nil
function I.CarryVestClearance(ent, gearOwner, w, otherPush)
    if not (IsValid(ent) and IsValid(gearOwner)) then return end
    local uid = gearOwner.UserID and gearOwner:UserID() or gearOwner
    local g = AdvInv.mountedGear[uid] and AdvInv.mountedGear[uid].Vest
    if not (IsValid(g) and g.advinvAttach) then return end -- (a bonemerged vest bends: not measured)
    local sig = table.concat({ g:GetModel(), w.model or "", w.class or "", w.mode or "", ent:GetModel(),
        ("%.2f %.2f"):format(otherPush or 0, g:GetModelScale()) }, "|")
    local per = clearCache[ent]
    if not per then per = {} clearCache[ent] = per end
    local c = per[w.cat]
    local now = RealTime()
    if c and c.sig == sig and now < c.expires then return c.val end
    local val
    local ok = pcall(function()
        local d = vestData(g)
        local wp = d and weaponPoints(w.model)
        local e = wp and I.CarryEntry(ent, w.class, w.mode, w.model)
        if not (e and e.out) then return end
        local bone = ent:LookupBone(e.bone)
        local bm = bone and ent:GetBoneMatrix(bone)
        if not bm then return end
        local pos, ang = I.CarryTransform(ent, w, otherPush or 0)
        local gpos, gang = AdvInv.GearPlacement(g, gearOwner)
        if not (pos and gpos) then return end
        -- the outward direction and the weapon, in the vest's space (its scale kept: world units)
        local outW = LocalToWorld(e.out, angle_zero, vector_origin, bm:GetAngles())
        local dir = WorldToLocal(outW, angle_zero, vector_origin, gang)
        dir:Normalize()
        dir = Vector(math.Round(dir.x, 2), math.Round(dir.y, 2), math.Round(dir.z, 2))
        dir:Normalize()
        local f = heightField(d, dir, g:GetModelScale())
        local ws = ent:GetModelScale()
        local need
        for _, p in ipairs(wp) do
            local q = WorldToLocal(LocalToWorld(p * ws, angle_zero, pos, ang), angle_zero, gpos, gang)
            local k = math.floor(q:Dot(f.a) / CELL) * 4096 + math.floor(q:Dot(f.b) / CELL)
            local top = f.h[k]
            if top then
                local over = top - q:Dot(dir)
                if not need or over > need then need = over end
            end
        end
        val = math.Clamp((need or -math.huge) + C.CarryGap, 0, MAX_PUSH)
    end)
    if not ok then val = nil end
    per[w.cat] = { sig = sig, expires = now + C.CarryVestClearanceEvery, val = val }
    return val
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
-- How far the drawn backpack reaches on one side of the back (from center along side * right), within
-- a height band (zlo, zhi: world heights from center) and a depth band (dlo, dhi: along back from
-- center): its mesh, not its hull (a hull's middle dimension put rifles 1-2 units off the pack's side,
-- or, the shoulder line inside a wide pack, into it). nil when it can't be measured. Cached per
-- weapon slot for C.CarryVestClearanceEvery seconds.
local packCache, besideCache = {}, setmetatable({}, { __mode = "k" })
local PACK_POINTS = 1500
local function packReach(ent, gearOwner, cat, side, center, right, back, zlo, zhi, dlo, dhi)
    if not (IsValid(ent) and IsValid(gearOwner)) then return end
    local uid = gearOwner.UserID and gearOwner:UserID() or gearOwner
    local g = AdvInv.mountedGear[uid] and AdvInv.mountedGear[uid].Rucksack
    if not (IsValid(g) and g.advinvAttach) then return end
    local sig = ("%s|%d|%.1f %.1f %.1f %.1f"):format(g:GetModel(), side, zlo, zhi, dlo, dhi)
    local per = besideCache[ent]
    if not per then per = {} besideCache[ent] = per end
    local c = per[cat]
    local now = RealTime()
    if c and c.sig == sig and now < c.expires then return c.val end
    local val
    pcall(function()
        local key, bodyValue, hidden = vestKey(g)
        local pts = packCache[key]
        if pts == nil then
            pts = surfacePoints(g:GetModel(), bodyValue, hidden, PACK_POINTS) or false
            packCache[key] = pts
        end
        if not pts then return end
        local gpos, gang = AdvInv.GearPlacement(g, gearOwner)
        if not gpos then return end
        local s = g:GetModelScale()
        local cL = WorldToLocal(center, angle_zero, gpos, gang)
        local rL = WorldToLocal(right, angle_zero, vector_origin, gang)
        local bL = WorldToLocal(back, angle_zero, vector_origin, gang)
        local uL = WorldToLocal(Vector(0, 0, 1), angle_zero, vector_origin, gang)
        local best
        for _, p in ipairs(pts) do
            local d = p * s - cL
            local h, dep = d:Dot(uL), d:Dot(bL)
            if h >= zlo and h <= zhi and dep >= dlo and dep <= dhi then
                local l = side * d:Dot(rL)
                if not best or l > best then best = l end
            end
        end
        val = best
    end)
    per[cat] = { sig = sig, expires = now + C.CarryVestClearanceEvery, val = val }
    return val
end

function I.CarryBeside(ent, w, pos, ang, halfWidth, gearOwner)
    -- a standing (or crouched) player only: world up and the floor under his feet mean nothing for a
    -- body lying on the ground (its rifle was turned upright and swung out of it)
    if I.IsBody and I.IsBody(ent) then return pos, ang end
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
    ang = I.ModelToGeomAngles(g, ang) -- (its barrel along its X: see I.WeaponGeometry)
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
    -- sideways: in line with the shoulder joint (the sling hangs from it), else against the pack's
    -- side; never inside the pack (a pack wider than the shoulders swallowed the weapon)
    local packSide = halfWidth * scale + C.CarryGap - inner
    if gearOwner then
        -- the drawn pack's side where the weapon will hang (its heights; its depths once moved)
        local zlo, zhi = math.huge, -math.huge
        for _, p in ipairs(c2) do
            local h = p.z - center.z
            zlo, zhi = math.min(zlo, h), math.max(zhi, h)
        end
        local reach = packReach(ent, gearOwner, w.cat, side, center, right, back, zlo, zhi, want - 1, want + (rear - front) + 1)
        if reach then packSide = reach + C.CarryGap - inner end
    end
    local shift = packSide
    local arm = ent:LookupBone(side > 0 and "ValveBiped.Bip01_R_UpperArm" or "ValveBiped.Bip01_L_UpperArm")
    local am = C.CarryBesideShoulder ~= false and arm and ent:GetBoneMatrix(arm)
    if am then shift = math.max(side * (am:GetTranslation() - center):Dot(right) - (inner + outer) / 2, packSide) end
    p2 = p2 + right * (side * shift) + back * (want - front)
    local p3, a3 = I.CarryBesideCrouch(ent, g, p2, a, right, back, am, cornersAt)
    return p3, I.GeomToModelAngles(g, a3)
end

--[[
    A weapon slung beside a pack whose lower end would reach the ground or, crouched, sit in front
    of the hip: hung as a sling holds it, its lower end swung back. Without this it kept the
    torso's forward lean and, crouched, a long rifle stood on its butt in front of the knees.
    Standing, its lower end is above the ground: nothing changes (the hip test is only for a
    crouching player).
      1. straight down from the point level with the shoulder joint (gravity: the torso's lean
         taken out);
      2. its lower end swung back around its upper end, which stays up by the shoulder, until it
         clears the ground and, crouched, is no further forward of the hip than
         C.CarryBesideHipFront (at most C.CarryBesideMaxSwing degrees).
--]]
C.CarryGroundGap = C.CarryGroundGap or 1
C.CarryBesideHipFront = C.CarryBesideHipFront or 5
C.CarryBesideMaxSwing = C.CarryBesideMaxSwing or 70
function I.CarryBesideCrouch(ent, g, p, a, right, back, am, cornersAt)
    local scale = ent:GetModelScale()
    local floor = ent:GetPos().z + C.CarryGroundGap
    local pel = ent:IsPlayer() and ent:Crouching() and ent:LookupBone("ValveBiped.Bip01_Pelvis")
    local pm = pel and ent:GetBoneMatrix(pel)
    local hip = pm and pm:GetTranslation()
    local half = (g.maxs.x - g.mins.x) * scale / 2
    -- its lower end (on its axis) and its lowest corner
    local function lowEnd(pp, aa)
        local _, m = cornersAt(pp, aa)
        local f = aa:Forward()
        local e1, e2 = m + f * half, m - f * half
        return e1.z < e2.z and e1 or e2
    end
    local function lowest(pp, aa)
        local z = math.huge
        for _, c in ipairs((cornersAt(pp, aa))) do z = math.min(z, c.z) end
        return z
    end
    local function fine(pp, aa)
        if lowest(pp, aa) < floor then return false end
        return not hip or (lowEnd(pp, aa) - hip):Dot(back) >= -C.CarryBesideHipFront - 0.01
    end
    if fine(p, a) then return p, a end
    -- the point it hangs from: on its axis, level with the shoulder joint
    local _, m0 = cornersAt(p, a)
    local f0 = a:Forward()
    local sp = am and am:GetTranslation() or (m0 + f0 * half)
    local pivot = m0 + f0 * (sp - m0):Dot(f0)
    local lp = WorldToLocal(pivot, angle_zero, p, a)
    local function around(base, deg)
        local na = turned(base, right, deg)
        return pivot - LocalToWorld(lp, angle_zero, vector_origin, na), na
    end
    -- 1. straight down: the turn about the body's right axis that makes its axis vertical
    local up = f0.z >= 0 and f0 or -f0
    local deg = math.deg(math.atan2(up:Cross(Vector(0, 0, 1)):Length(), up.z))
    local best, bestZ = a, -1
    for _, s in ipairs({ deg, -deg }) do
        local _, na = around(a, s)
        local u = na:Forward()
        if math.abs(u.z) > bestZ then best, bestZ = na, math.abs(u.z) end
    end
    -- 2. its lower end swung back around its upper end (which stays up by the shoulder: turned
    -- around the shoulder point, its upper part went forward across the chest)
    local vp, va = around(best, 0)
    local _, mv = cornersAt(vp, va)
    local fv = va:Forward()
    local top = (mv + fv * half).z > (mv - fv * half).z and mv + fv * half or mv - fv * half
    local tl = WorldToLocal(top, angle_zero, vp, va)
    local function swung(d)
        local na = turned(va, right, d)
        return top - LocalToWorld(tl, angle_zero, vector_origin, na), na
    end
    pivot = top
    -- which way takes its lower end back, then the smallest swing that is fine
    local function lowBack(d)
        local np, na = swung(d)
        return (lowEnd(np, na) - pivot):Dot(back)
    end
    local sgn = lowBack(5) >= lowBack(-5) and 1 or -1
    local lo, hi = 0, C.CarryBesideMaxSwing
    if fine(swung(0)) then
        hi = 0
    elseif fine(swung(sgn * hi)) then
        for _ = 1, 12 do
            local mid = (lo + hi) / 2
            if fine(swung(sgn * mid)) then hi = mid else lo = mid end
        end
    end
    return swung(sgn * hi)
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
