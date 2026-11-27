--[[
    Carry modes, client side: where a carried long gun is drawn (rules in sh_carry.lua).

    Offsets (cl_carry_data.lua, made by tools/fit_carry.py): playermodel -> offset set (models with
    the same proportions share one, I.CarryAliases) -> weapon class -> mode ->
    { bone, position, angles, outward direction }. Looked up in this order:
        1. values tuned in game this session (advinv_carry_tune, I.CarryTuned[set][class][mode])
        2. I.CarryOffsets[playermodel path] (a server can add a set for one model under its path)
        3. I.CarryOffsets[alias set of the playermodel], else the "default" set
        4. a weapon without offsets (another addon's): the mode's template, fitted to its shape,
           then rested on the wearer's own torso (I.CarryRestOnBody, measured in the background)
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
-- weapons without offsets: an extra gap off the body per mode (none: they rest on the measured body)
C.CarryTemplateGap = C.CarryTemplateGap or {}
-- weapons without offsets rest on the wearer's torso itself (I.CarryRestOnBody): pulled in by that
-- much at most when the template leaves them off it (pushed out by up to 8 when in it); the body is
-- measured C.CarryRestBudget seconds a frame (below)
C.CarryRestPull = C.CarryRestPull or 4
if C.CarryRestOnBody == nil then C.CarryRestOnBody = true end -- false: where the template puts them
local restOnBody -- (below)

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
    local t = templateEntry(mode, path, name)
    if t and restOnBody and C.CarryRestOnBody then t = restOnBody(ent, mode, path, t, name) or t end
    return t, name
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

--[[
    A weapon without offsets rests on its wearer's torso: the template puts it where the template gun
    lies on that set's body; moved along its outward direction until it is C.CarryGap off the torso
    under it (its spine, pelvis, neck and collarbones: the arms move; the thighs only stop it being
    pulled in, they move when walking), as the playermodel is
    drawn (its bodygroups, its parts the inventory hides) over its idle loop. Pulled in by up to
    C.CarryRestPull only when most of the weapon lies over that body (what hangs past it may meet
    something not measured), pushed out by up to 8. Another addon's long gun, a magazine or a scope
    toward the body, a body with its kit in its mesh (a bedroll, a haversack): neither in it nor off it.
    The body is measured in the background, a few milliseconds a frame (C.CarryRestBudget), one at a
    time; until then the weapon is where the template puts it.
--]]
local TORSO = { "ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Spine2",
    "ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_Neck1", "ValveBiped.Bip01_L_Clavicle", "ValveBiped.Bip01_R_Clavicle",
    "ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_R_Thigh" }
C.CarryRestBudget = C.CarryRestBudget or 0.002
local fieldCache = {} -- body key|direction -> { a, b, h } (a height field), or false
local jobs, queue = {}, {} -- field key -> { co, tmp }; field keys in order
local sliceEnd = 0
local function tick()
    if SysTime() > sliceEnd then coroutine.yield() end
end

-- (in a job) the torso's surface in boneName's frame, over the idle loop
local function measureTorso(mdl, bodyValue, hidden, boneName, job)
    local meshes, bind = util.GetModelMeshes(mdl, 0, bodyValue or 0)
    if not (istable(meshes) and istable(bind)) then return end
    tick()
    local tmp = ClientsideModel(mdl, RENDERGROUP_OTHER)
    if not IsValid(tmp) then return end
    job.tmp = tmp
    tmp:SetNoDraw(true)
    tmp:SetPos(vector_origin)
    tmp:SetAngles(angle_zero)
    local seq = tmp:LookupSequence("idle_all_01")
    tmp:ResetSequence(seq and seq >= 0 and seq or 0)
    local bi = tmp:LookupBone(boneName)
    if not bi then return end
    local keep, thigh = {}, {}
    for _, n in ipairs(TORSO) do
        local i = tmp:LookupBone(n)
        if i then keep[i] = true end
    end
    for _, n in ipairs({ "ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_R_Thigh" }) do
        local i = tmp:LookupBone(n)
        if i then thigh[i] = true end
    end
    local base = bind[0] and 0 or 1
    local hmin, hmax = tmp:GetModelBounds()
    local tol = Vector(3, 3, 3)
    -- the torso's triangles (two corners on its bones), their corners with their bone weights; which
    -- of them are the thighs'
    local verts, isThigh = {}, {}
    local function dominant(v)
        local ws = v.weights
        if not ws or #ws == 0 then ws = { { bone = 0, weight = 1 } } end
        local best, bw = nil, -1
        for _, w in ipairs(ws) do
            if w.weight > bw then best, bw = w.bone, w.weight end
        end
        return best, ws
    end
    for _, msh in ipairs(meshes) do
        local tri = not hidden[string.lower(msh.material or "")] and msh.triangles or {}
        for i = 1, #tri - 2, 3 do
            local n, nt, corner = 0, 0, {}
            for j = 0, 2 do
                local best, ws = dominant(tri[i + j])
                if keep[best] then n = n + 1 end
                if thigh[best] then nt = nt + 1 end
                corner[j + 1] = { tri[i + j].pos, ws }
            end
            if n >= 2 then
                for j = 1, 3 do verts[#verts + 1] = corner[j] end
                isThigh[#isThigh + 1] = nt >= 2
            end
            if i % 600 == 1 then tick() end
        end
    end
    if #verts <= 150 then return end
    -- skinned at a moment of the idle loop (its breathing moves the back), added to acc (body and
    -- thighs: flat x, y, z arrays in the bone's frame); false when the bind matrices taken that way
    -- don't put the mesh inside the model's hull
    local function skinAt(cycle, invert, acc)
        if not IsValid(tmp) then return end
        tmp:SetCycle(cycle)
        tmp:InvalidateBoneCache()
        tmp:SetupBones()
        local B = tmp:GetBoneMatrix(bi)
        if not B then return end
        local Binv = B:GetInverse()
        local K = {} -- (all taken now: the model may be set up again while this waits)
        for i = 0, tmp:GetBoneCount() - 1 do
            local bm, bp = tmp:GetBoneMatrix(i), bind[i + base]
            if bm and bp and bp.matrix then K[i] = bm * (invert and bp.matrix:GetInverse() or bp.matrix) end
        end
        local out = {}
        for n, vw in ipairs(verts) do
            local q = Vector(0, 0, 0)
            for _, w in ipairs(vw[2]) do
                local k = K[w.bone]
                if not k then return end
                q = q + (k * vw[1]) * w.weight
            end
            out[n] = q
            if n % 400 == 0 then tick() end
        end
        for i = 1, #out, math.max(1, math.floor(#out / 50)) do
            if not out[i]:WithinAABox(hmin - tol, hmax + tol) then return false end
        end
        -- the triangles filled in (a cell of the height field is a unit across: corners alone
        -- leave most of it empty, and a flat triangle over a hollow stands out past them)
        for i = 1, #out - 2, 3 do
            local T = isThigh[(i + 2) / 3] and acc.thigh or acc.body
            local X, Y, Z = T.x, T.y, T.z
            local n = #X
            local A, Bv, Cv = Binv * out[i], Binv * out[i + 1], Binv * out[i + 2]
            local ax, ay, az = A.x, A.y, A.z
            local ux, uy, uz = Bv.x - ax, Bv.y - ay, Bv.z - az
            local vx, vy, vz = Cv.x - ax, Cv.y - ay, Cv.z - az
            local len = math.sqrt(math.max(ux * ux + uy * uy + uz * uz, vx * vx + vy * vy + vz * vz))
            local steps = math.Clamp(math.ceil(len / 0.7), 1, 12)
            for s1 = 0, steps do
                for s2 = 0, steps - s1 do
                    local f1, f2 = s1 / steps, s2 / steps
                    n = n + 1
                    X[n], Y[n], Z[n] = ax + ux * f1 + vx * f2, ay + uy * f1 + vy * f2, az + uz * f1 + vz * f2
                end
            end
            if i % 300 == 1 then tick() end
        end
        return true
    end
    local acc = { body = { x = {}, y = {}, z = {} }, thigh = { x = {}, y = {}, z = {} } }
    local invert
    for _, inv in ipairs({ false, true }) do
        if skinAt(0, inv, acc) then
            invert = inv
            break
        end
    end
    if invert == nil then return end
    for _, cyc in ipairs({ 0.25, 0.5, 0.75 }) do skinAt(cyc, invert, acc) end
    return acc
end

local function runJobs()
    local key = queue[1]
    if not key then
        hook.Remove("Think", "AdvInv_CarryRest")
        return
    end
    local job = jobs[key]
    sliceEnd = SysTime() + C.CarryRestBudget
    local ok, res = coroutine.resume(job.co)
    if not ok or coroutine.status(job.co) == "dead" then
        if IsValid(job.tmp) then job.tmp:Remove() end
        if not ok then ErrorNoHalt("[AdvInv] carry rest: " .. tostring(res) .. "\n") end
        fieldCache[key] = ok and res or false
        jobs[key] = nil
        table.remove(queue, 1)
    end
end

-- the torso's height field along dir (in boneName's frame) as the body is drawn (look: its drawn
-- look's key, body value and hidden materials); nil while it is being measured, false if it can't be
local function fieldKey(tk, dir)
    return ("%s|%.2f %.2f %.2f"):format(tk, dir.x, dir.y, dir.z)
end
-- (directions rounded: one field serves the sets whose templates point the same way)
local function roundDir(v)
    local d = v:GetNormalized()
    d = Vector(math.Round(d.x, 2), math.Round(d.y, 2), math.Round(d.z, 2))
    d:Normalize()
    return d
end

-- (in a job) the highest point of the body, and of the thighs, along dir per cell across it
local function buildField(pts, dir)
    local a, b = basisOf(dir)
    local ax, ay, az, bx, by, bz, dx, dy, dz = a.x, a.y, a.z, b.x, b.y, b.z, dir.x, dir.y, dir.z
    local floor = math.floor
    local function heights(P)
        local X, Y, Z = P.x, P.y, P.z
        local h = {}
        for i = 1, #X do
            local x, y, z = X[i], Y[i], Z[i]
            local k = floor((x * ax + y * ay + z * az) / CELL) * 4096 + floor((x * bx + y * by + z * bz) / CELL)
            local up = x * dx + y * dy + z * dz
            local top = h[k]
            if not top or up > top then h[k] = up end
            if i % 4000 == 0 then tick() end
        end
        return h
    end
    return { a = a, b = b, h = heights(pts.body), ht = heights(pts.thigh) }
end

-- the torso's height field along dir (in boneName's frame) as the body is drawn (look: its drawn
-- look's key, body value and hidden materials); nil while it is being measured, false if it can't
-- be. The fields of the set's other modes on the same bone are made with it: the body's points
-- (a few megabytes) are not kept.
local function torsoField(mdl, look, boneName, dir, setName)
    local tk = mdl .. "|" .. boneName .. "|" .. look[1]
    local key = fieldKey(tk, dir)
    local f = fieldCache[key]
    if f ~= nil then return f end
    if jobs[key] then return end
    local bodyValue, hidden = look[2], look[3]
    local job = {}
    job.co = coroutine.create(function()
        if fieldCache[key] ~= nil then return fieldCache[key] end -- (made with another mode's)
        local pts = measureTorso(mdl, bodyValue, hidden, boneName, job)
        if IsValid(job.tmp) then job.tmp:Remove() end
        if not pts then return false end
        for mode in pairs(I.CarryTemplates) do
            local t = templateFor(mode, setName)
            if t and t.bone == boneName and t.out then
                local d = roundDir(t.out)
                local k = fieldKey(tk, d)
                if k ~= key and fieldCache[k] == nil then fieldCache[k] = buildField(pts, d) end
            end
        end
        return buildField(pts, dir)
    end)
    jobs[key] = job
    queue[#queue + 1] = key
    hook.Add("Think", "AdvInv_CarryRest", runJobs)
end

local restCache = {}
local drawnLook = setmetatable({}, { __mode = "k" }) -- ent -> { key, body value, hidden, until, model }
restOnBody = function(ent, mode, path, e, setName)
    if not e.out then return end
    local mdl = string.lower(ent:GetModel() or "")
    local look, now = drawnLook[ent], RealTime()
    if not look or now > look[4] or look[5] ~= mdl then
        local vk, bodyValue, hidden = vestKey(ent)
        look = { vk, bodyValue, hidden, now + 0.5, mdl }
        drawnLook[ent] = look
    end
    local key = mdl .. "|" .. mode .. "|" .. path .. "|" .. (setName or "") .. "|" .. look[1]
    local r = restCache[key]
    if r ~= nil then return r or nil end
    local dir = roundDir(e.out)
    local f = torsoField(mdl, look, e.bone, dir, setName)
    if f == nil then return end -- (being measured)
    restCache[key] = false
    local wp = f and weaponPoints(path)
    if not wp then return end
    local a, b, h, ht = f.a, f.b, f.h, f.ht
    local need, thighNeed, over_ = nil, nil, 0
    for _, p in ipairs(wp) do
        local q = LocalToWorld(p, angle_zero, e.pos, e.ang)
        local k = math.floor(q:Dot(a) / CELL) * 4096 + math.floor(q:Dot(b) / CELL)
        local top, topT, up = h[k], ht[k], nil
        if top or topT then
            over_ = over_ + 1
            up = q:Dot(dir)
        end
        if top and (not need or top - up > need) then need = top - up end
        if topT and (not thighNeed or topT - up > thighNeed) then thighNeed = topT - up end
    end
    if not need then return end -- (it doesn't pass over the torso: as the template has it)
    local pull = over_ >= #wp * 0.6 and C.CarryRestPull or 0
    local move = math.Clamp(need + C.CarryGap, -pull, MAX_PUSH)
    -- the thighs (they move when walking) only stop it being pulled in, never push it out
    if thighNeed then move = math.max(move, math.min(thighNeed + C.CarryGap, 0)) end
    r = { bone = e.bone, pos = e.pos + dir * move, ang = e.ang, out = e.out, geom = e.geom, rest = move }
    restCache[key] = r
    return r
end
I.CarryRestOnBody = restOnBody

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
