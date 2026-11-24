--[[
    Weapons, client side.

    - I.WeaponGeometry(model): exact bounds of a weapon world model as the game draws it at rest
      (barrel along +X, top along +Z), measured on its mesh. The model's own box (hull) is often
      twice too tall, so it is only a fallback.
    - "AdvInvWeaponIcon" panel: the weapon seen from the side, horizontal, fitted to its box.
    - Equipped weapons that are not in the player's hands are drawn on the body: long guns where
      their carry mode puts them (sh_carry.lua, cl_carry.lua), sidearm in a holster on the right
      thigh, other weapons of the long-gun slots across the back. They are drawn with the player
      (PostPlayerDraw), so they disappear whenever the player is not drawn (invisible, out of
      view), and also when the player is dead, in a vehicle, or is the local player in first person.
--]]
local I = AdvInv
local C = I.Config

-- Where weapons go on the body. pos = point of the body surface the weapon rests on and out =
-- direction away from the body, in the bone's frame; ang = weapon orientation in that frame.
-- Computed from the reference pose of Kleiner and male_07 (back: 40° from vertical).
C.WeaponMounts = C.WeaponMounts or {
    PrimaryWep = { bone = "ValveBiped.Bip01_Spine2", pos = Vector(6.52, -3.44, 0), out = Vector(0.015, -1, 0), ang = Angle(-40, 0.9, -180) },
    RocketLauncher = { bone = "ValveBiped.Bip01_Spine2", pos = Vector(6.52, -3.44, 0), out = Vector(0.015, -1, 0), ang = Angle(40, 0.9, 0) },
    SecondaryWep = { bone = "ValveBiped.Bip01_R_Thigh", pos = Vector(7.99, -0.89, -4.15), out = Vector(0.005, 0, -1), ang = Angle(-0.3, -3, 90) },
}
C.WeaponMountGap = C.WeaponMountGap or 0.3     -- room between a weapon and what is under it
C.VestBackThickness = C.VestBackThickness or 2  -- a worn vest adds this much on the back
if C.ShowMountedWeapons == nil then C.ShowMountedWeapons = true end

---------------------------------------------------------------- geometry

local boundsCache, geomCache = {}, {}

-- Hull of a model (cached; a temporary model is created once per path).
local function modelBounds(path)
    local b = boundsCache[path]
    if b == false then return end -- (a model that can't be created: not tried again every frame)
    if b then return b[1], b[2] end
    local ent = ClientsideModel(path, RENDERGROUP_OTHER)
    if not IsValid(ent) then
        boundsCache[path] = false
        return
    end
    local mn, mx = ent:GetModelBounds()
    ent:Remove()
    boundsCache[path] = { mn, mx }
    return mn, mx
end

-- Bounds of the mesh posed by the current bones of ent. bind.matrix is used as given, or inverted
-- (the API does not say which way it goes): the right one is the one that fits in the hull.
-- Band holding the middle 90 % of the surface along one axis (a few parts sticking out, like a
-- side handle, do not count): { lo, hi } from triangle centres weighted by area.
local function coreBand(samples)
    if #samples == 0 then return end
    table.sort(samples, function(a, b) return a[1] < b[1] end)
    local total = 0
    for _, s in ipairs(samples) do total = total + s[2] end
    local lo, hi, acc = samples[1][1], samples[#samples][1], 0
    local gotLo = false
    for _, s in ipairs(samples) do
        acc = acc + s[2]
        if not gotLo and acc >= total * 0.05 then lo, gotLo = s[1], true end
        if acc >= total * 0.95 then hi = s[1] break end
    end
    return { lo = lo, hi = hi }
end

local function meshBounds(ent, path, hmin, hmax)
    local ok, meshes, bind = pcall(util.GetModelMeshes, path, 0, 0)
    if not ok or not istable(meshes) or not istable(bind) then return end
    local base = bind[0] and 0 or 1
    local function attempt(invert)
        local K = {}
        local function skin(v)
            local p = Vector(0, 0, 0)
            local weights = v.weights
            if not weights or #weights == 0 then weights = { { bone = 0, weight = 1 } } end
            for _, w in ipairs(weights) do
                local k = K[w.bone]
                if not k then
                    local bm, bp = ent:GetBoneMatrix(w.bone), bind[w.bone + base]
                    if not (bm and bp and bp.matrix) then return end
                    k = bm * (invert and bp.matrix:GetInverse() or bp.matrix)
                    K[w.bone] = k
                end
                p = p + (k * v.pos) * w.weight
            end
            return p
        end
        local mn = Vector(math.huge, math.huge, math.huge)
        local mx = Vector(-math.huge, -math.huge, -math.huge)
        local ys, zs = {}, {}
        for _, m in ipairs(meshes) do
            local tri = m.triangles or {}
            for i = 1, #tri - 2, 3 do
                local a, b, c = skin(tri[i]), skin(tri[i + 1]), skin(tri[i + 2])
                if not (a and b and c) then return end
                for _, p in ipairs({ a, b, c }) do
                    mn.x, mn.y, mn.z = math.min(mn.x, p.x), math.min(mn.y, p.y), math.min(mn.z, p.z)
                    mx.x, mx.y, mx.z = math.max(mx.x, p.x), math.max(mx.y, p.y), math.max(mx.z, p.z)
                end
                local area = (b - a):Cross(c - a):Length() / 2
                ys[#ys + 1] = { (a.y + b.y + c.y) / 3, area }
                zs[#zs + 1] = { (a.z + b.z + c.z) / 3, area }
            end
        end
        if mn.x > mx.x then return end
        local tol = Vector(2, 2, 2)
        if mn:WithinAABox(hmin - tol, hmax + tol) and mx:WithinAABox(hmin - tol, hmax + tol) then
            return mn, mx, { y = coreBand(ys), z = coreBand(zs) }
        end
    end
    local mn, mx, core = attempt(false)
    if not mn then mn, mx, core = attempt(true) end
    return mn, mx, core
end

-- { mins, maxs, core, muzzleBack } of a weapon world model at rest (barrel along X, top +Z);
-- core.y / core.z: band holding most of its surface across (what rests against the body);
-- muzzleBack: its muzzle is on the -X end.
function I.WeaponGeometry(path)
    local cached = geomCache[path]
    if cached ~= nil then return cached or nil end
    local ent = ClientsideModel(path, RENDERGROUP_OTHER)
    if not IsValid(ent) then
        geomCache[path] = false
        return
    end
    ent:SetNoDraw(true)
    ent:SetPos(vector_origin)
    ent:SetAngles(angle_zero)
    ent:ResetSequence(0)
    ent:SetCycle(0)
    ent:InvalidateBoneCache()
    ent:SetupBones()
    local hmin, hmax = ent:GetModelBounds()
    local mn, mx, core = meshBounds(ent, path, hmin, hmax)
    local g = { mins = mn or hmin, maxs = mx or hmax, exact = mn ~= nil }
    g.core = core or { y = { lo = g.mins.y, hi = g.maxs.y }, z = { lo = g.mins.z, hi = g.maxs.z } }
    -- some models point their muzzle to -X (HL2 pistol, AR2, shotgun, RPG): read it on the model
    local mz = ent:LookupAttachment("muzzle")
    local at = mz and mz > 0 and ent:GetAttachment(mz)
    g.muzzleBack = at ~= nil and at ~= false and at.Pos.x < (g.mins.x + g.maxs.x) * 0.5
    local b0 = ent:GetBoneMatrix(0) -- its root bone at rest: carries the model when it is bonemerged
    g.restBone0 = b0 and Matrix(b0) or nil
    ent:Remove()
    geomCache[path] = g
    return g
end

-- The 8 corners, in the world, of a weapon model mounted by bonemerge (held in the hands): its
-- rest geometry carried by its root bone. nil if unknown.
function I.WeaponCorners(m)
    local path = IsValid(m) and m:GetModel()
    local g = path and I.WeaponGeometry(path)
    if not (g and g.restBone0) then return end
    m:SetupBones()
    local b0 = m:GetBoneMatrix(0)
    if not b0 then return end
    local T = b0 * g.restBone0:GetInverse()
    if not T then return end
    local out = {}
    for k = 0, 7 do
        out[#out + 1] = T * Vector(bit.band(k, 1) > 0 and g.maxs.x or g.mins.x,
            bit.band(k, 2) > 0 and g.maxs.y or g.mins.y, bit.band(k, 4) > 0 and g.maxs.z or g.mins.z)
    end
    return out
end

-- Length / height of a weapon (wide tiles for long guns).
function I.WeaponAspect(path)
    local g = I.WeaponGeometry(path)
    if not g then return 1 end
    return (g.maxs.x - g.mins.x) / math.max(g.maxs.z - g.mins.z, 0.1)
end

---------------------------------------------------------------- inventory icon

local ICON = {}

function ICON:SetWeaponModel(path, skin)
    self:SetModel(path)
    if IsValid(self.Entity) then
        self.Entity:SetSkin(skin or 0)
        self.Entity:ResetSequence(0)
        self.Entity:SetCycle(0)
    end
    self.geom = I.WeaponGeometry(path)
end

function ICON:LayoutEntity() end
function ICON:RunAnimation() end

-- Side view (muzzle to the right), orthographic, the gun filling the box.
function ICON:Paint(w, h)
    local ent, g = self.Entity, self.geom
    if not (IsValid(ent) and g) then return end
    local center = (g.mins + g.maxs) * 0.5
    local len = math.max(g.maxs.x - g.mins.x, 0.1)
    local tall = math.max(g.maxs.z - g.mins.z, 0.1)
    local scale = math.min(w * 0.88 / len, h * 0.8 / tall) -- pixels per unit
    local hw, hh = w / scale / 2, h / scale / 2

    -- visible part of the panel (it can be in a scrolled list)
    local x, y = self:LocalToScreen(0, 0)
    local l, t, r, b = x, y, x + w, y + h
    local p = self
    while p:GetParent() ~= nil do
        p = p:GetParent()
        local px, py = p:LocalToScreen(0, 0)
        l, t = math.max(l, px), math.max(t, py)
        r, b = math.min(r, px + p:GetWide()), math.min(b, py + p:GetTall())
    end
    if r <= l or b <= t then return end

    -- seen from the side that puts the muzzle on the right
    local side = g.muzzleBack and -1 or 1
    cam.Start({
        type = "3D", x = x, y = y, w = w, h = h,
        origin = center - Vector(0, 100 * side, 0), angles = Angle(0, 90 * side, 0),
        ortho = { left = -hw, right = hw, top = -hh, bottom = hh },
        znear = 1, zfar = 300,
    })
    render.SetScissorRect(l, t, r, b, true)
    render.SuppressEngineLighting(true)
    render.SetLightingOrigin(center)
    render.ResetModelLighting(0.35, 0.35, 0.38)
    render.SetModelLighting(BOX_TOP, 1, 1, 1)
    render.SetModelLighting(side == 1 and BOX_LEFT or BOX_RIGHT, 0.85, 0.85, 0.85) -- the side facing the camera
    render.SetColorModulation(1, 1, 1)
    render.SetBlend(1)
    ent:DrawModel()
    render.SuppressEngineLighting(false)
    render.SetScissorRect(0, 0, 0, 0, false)
    cam.End3D()
end

vgui.Register("AdvInvWeaponIcon", ICON, "DModelPanel")

---------------------------------------------------------------- weapons on the body

-- Models drawn on bodies: AdvInv.mountedWeps[entity][slot] = { path, model }. Removed with their
-- entity, when a player dies, and when this file is reloaded (lua refresh).
if AdvInv.mountedWeps then
    for _, store in pairs(AdvInv.mountedWeps) do
        for _, e in pairs(store) do
            if IsValid(e.model) then e.model:Remove() end
        end
    end
end
AdvInv.mountedWeps = {}

local ORDER = { "PrimaryWep", "RocketLauncher", "SecondaryWep" }

-- Mount of a weapon slot on a playermodel: its fit (cl_fits_data.lua), else Config.WeaponMounts.
-- Used by the sidearm, and by long guns that have no carry modes (sh_carry.lua).
local mountCache = {}
function I.WeaponMountFor(cat, playermodel)
    local default = C.WeaponMounts[cat]
    local fits = I.Fits and I.Fits[string.lower(playermodel or "")]
    local f = fits and fits[cat]
    if not (f and default) then return default end
    local key = cat .. "|" .. playermodel
    local m = mountCache[key]
    if not m then
        m = { bone = default.bone, pos = f[1], out = f[2], ang = f[3] }
        mountCache[key] = m
    end
    return m
end

local function clearStore(store)
    for k, e in pairs(store) do
        if IsValid(e.model) then e.model:Remove() end
        store[k] = nil
    end
end

local function storeFor(ent)
    local store = AdvInv.mountedWeps[ent]
    if store then return store end
    store = {}
    AdvInv.mountedWeps[ent] = store
    ent:CallOnRemove("AdvInv_MountedWeapons", function()
        clearStore(store)
        AdvInv.mountedWeps[ent] = nil
    end)
    return store
end

local function mountedModel(store, slot, path)
    local e = store[slot]
    if e and e.path == path and IsValid(e.model) then return e.model end
    if e and IsValid(e.model) then e.model:Remove() end
    store[slot] = nil
    local m = ClientsideModel(path, RENDERGROUP_OPAQUE)
    if not IsValid(m) then return end
    m:SetNoDraw(true)
    m:ResetSequence(0)
    m:SetCycle(0)
    store[slot] = { path = path, model = m }
    return m
end

-- Size the worn backpack is drawn at on owner: its fit on owner's playermodel, else its default.
local function packScale(owner, sack)
    local class = AdvInv.IDClass[owner:GetNW2Int("Rucksack")]
    local per = AdvInv.Fits and AdvInv.Fits[string.lower(owner:GetModel() or "")]
    local fit = per and class and per[class]
    return (fit and fit[3]) or (sack.Attach and sack.Attach.scale) or 1
end

-- Thickness of the worn backpack (its thinnest dimension), 0 without one.
function I.BackpackThickness(owner)
    if not IsValid(owner) or owner:GetNW2Int("Rucksack") <= 1 then return 0 end
    local sack = AdvInv.EntityTable(owner:GetNW2Int("Rucksack"))
    if not (sack and sack.Model) then return 0 end
    -- gear drawn from a playermodel (sh_modelgear_items.lua): its model is the whole playermodel, the
    -- pack's own depth comes with it
    if sack.BackDepth then return sack.BackDepth * packScale(owner, sack) end
    local mn, mx = modelBounds(sack.Model)
    if not mn then return 0 end
    local d = mx - mn
    return math.min(d.x, d.y, d.z) * packScale(owner, sack)
end

-- Half width of the worn backpack behind the back (a rifle slung over the shoulder hangs beside it),
-- 0 without one. A prop backpack: half its middle dimension (thinnest: depth, largest: height).
function I.BackpackHalfWidth(owner)
    if not IsValid(owner) or owner:GetNW2Int("Rucksack") <= 1 then return 0 end
    local sack = AdvInv.EntityTable(owner:GetNW2Int("Rucksack"))
    if not (sack and sack.Model) then return 0 end
    local scale = packScale(owner, sack)
    if sack.BackHalfWidth then return sack.BackHalfWidth * scale end
    local mn, mx = modelBounds(sack.Model)
    if not mn then return 0 end
    local d = { mx.x - mn.x, mx.y - mn.y, mx.z - mn.z }
    table.sort(d)
    return d[2] / 2 * scale
end

-- Room taken on the back by the worn backpack and vest.
local function backLayer(owner)
    local extra = I.BackpackThickness(owner)
    if owner:GetNW2Int("Vest") > 1 then extra = extra + C.VestBackThickness end
    return extra
end

local function heldClass(owner)
    local wep = owner.GetActiveWeapon and owner:GetActiveWeapon()
    return IsValid(wep) and wep:GetClass() or nil
end

local function drawAt(m, ent, pos, ang)
    local scale = ent:GetModelScale()
    if m:GetModelScale() ~= scale then m:SetModelScale(scale, 0) end
    m:SetRenderOrigin(pos)
    m:SetRenderAngles(ang)
    m:InvalidateBoneCache()
    m:SetupBones()
    m:DrawModel()
end

-- Old-style mount (sidearm on the thigh, long guns without carry modes across the back).
local function drawMounted(ent, owner, store, w, back, primaryThickness)
    local mount = I.WeaponMountFor(w.cat, ent:GetModel())
    local bone = mount and ent:LookupBone(mount.bone)
    local matrix = bone and ent:GetBoneMatrix(bone)
    local g = I.WeaponGeometry(w.model)
    if not (matrix and g) then return 0 end
    local m = mountedModel(store, w.cat, w.model)
    if not IsValid(m) then return 0 end
    local extra = 0
    if w.cat ~= "SecondaryWep" then
        extra = (back or 0) + (w.cat == "RocketLauncher" and primaryThickness or 0)
    end
    -- the thinner side rests on the body (a crossbow lies on its limbs)
    local cy, cz = g.core.y, g.core.z
    local flatZ = (cy.hi - cy.lo) > (cz.hi - cz.lo)
    local wang = Angle(mount.ang.p, mount.ang.y, mount.ang.r)
    -- mounts expect the muzzle on +X: turn the others around
    if g.muzzleBack then wang:RotateAroundAxis(wang:Up(), 180) end
    local center = (g.mins + g.maxs) * 0.5
    local half
    if flatZ then
        wang:RotateAroundAxis(wang:Forward(), 90)
        center.z = (cz.lo + cz.hi) * 0.5
        half = (cz.hi - cz.lo) * 0.5
    else
        center.y = (cy.lo + cy.hi) * 0.5
        half = (cy.hi - cy.lo) * 0.5
    end
    center:Rotate(wang)
    local scale = ent:GetModelScale()
    local localPos = (mount.pos + mount.out:GetNormalized() * (half + extra + C.WeaponMountGap) - center) * scale
    local pos, ang = LocalToWorld(localPos, wang, matrix:GetTranslation(), matrix:GetAngles())
    drawAt(m, ent, pos, ang)
    return 2 * half + C.WeaponMountGap
end

--[[
    Draws a list of weapons on ent (a player, a ragdoll-free preview model...):
        list = { { cat = slot, class = weapon class, model = world model, mode = carry mode or nil }, ... }
    gearOwner: whose worn vest / backpack push the weapons out (nil: none). Long guns with a carry
    mode go where the mode puts them (cl_carry.lua; "stowed": not drawn); the others use the
    mounts above.
--]]
function I.DrawWeaponList(ent, gearOwner, list)
    if not IsValid(ent) then return end
    local store = storeFor(ent)
    local used = {}
    local carried = {}
    for _, w in ipairs(list) do
        if w.mode then carried[w.cat] = w end
    end
    local pushes = next(carried) and I.CarryPushes(ent, gearOwner, carried) or {}
    local back, primaryThickness = nil, 0
    for _, w in ipairs(list) do
        if w.mode then
            if w.mode ~= "stowed" then
                local pos, ang = I.CarryTransform(ent, w, pushes[w.cat] or 0)
                if pos and pushes.beside and pushes.beside[w.cat] then
                    pos, ang = I.CarryBeside(ent, w, pos, ang, pushes.beside[w.cat]) -- against the backpack's side
                end
                if pos then
                    local m = mountedModel(store, w.cat, w.model)
                    if IsValid(m) then
                        drawAt(m, ent, pos, ang)
                        used[w.cat] = true
                    end
                end
            end
        else
            if w.cat ~= "SecondaryWep" and IsValid(gearOwner) then back = back or backLayer(gearOwner) end
            local thick = drawMounted(ent, gearOwner, store, w, back, primaryThickness)
            if thick > 0 then used[w.cat] = true end
            if w.cat == "PrimaryWep" then primaryThickness = thick end
        end
    end
    -- free the models of slots that are no longer drawn
    for slot, e in pairs(store) do
        if not used[slot] then
            if IsValid(e.model) then e.model:Remove() end
            store[slot] = nil
        end
    end
end

-- The equipped weapons of owner as a list for I.DrawWeaponList. isHidden(cat, info) -> true to
-- leave one out (it is in the hands).
function I.EquippedWeaponList(owner, isHidden)
    local list = {}
    for _, cat in ipairs(ORDER) do
        local id, c = I.SlotRef(owner, cat)
        local t = id > 1 and I.DefTable(id, c) or nil
        if t and t.Model then
            local info = I.Info(id, c)
            if not (isHidden and isHidden(cat, info)) then
                list[#list + 1] = {
                    cat = cat, class = info.weaponClass, model = t.Model,
                    mode = I.CarryConfig(id, c) and I.CarryMode(owner, cat) or nil,
                }
            end
        end
    end
    return list
end

--[[
    Draws the weapons equipped by owner (a player) on ent: the player itself, or the inventory
    preview's model. isHidden(cat, info) -> true to leave a weapon out (it is in the hands).
--]]
function I.DrawMountedWeapons(ent, owner, isHidden)
    if not C.ShowMountedWeapons or not (IsValid(ent) and IsValid(owner)) then return end
    I.DrawWeaponList(ent, owner, I.EquippedWeaponList(owner, isHidden))
end

local function heldInHands(owner)
    local held = heldClass(owner)
    return function(_, info) return held ~= nil and info.weaponClass == held end
end

-- Drawn with the player: hidden with the player (out of view, invisible), and also when dead, in
-- a vehicle, and for the local player in first person.
hook.Add("PostPlayerDraw", "AdvInv_MountedWeapons", function(ply)
    if not ply:Alive() or ply:InVehicle() or AdvInv.OwnerHidden(ply) then return end
    if ply == LocalPlayer() and not ply:ShouldDrawLocalPlayer() then return end
    I.DrawMountedWeapons(ply, ply, heldInHands(ply))
end)

-- Models of dead players, and of entities that are gone, are freed.
timer.Create("AdvInv_MountedWeaponsCleanup", 2, 0, function()
    for ent, store in pairs(AdvInv.mountedWeps) do
        if not IsValid(ent) then
            clearStore(store)
            AdvInv.mountedWeps[ent] = nil
        elseif ent:IsPlayer() and (not ent:Alive() or ent:InVehicle()) then
            clearStore(store)
        end
    end
end)

gameevent.Listen("player_disconnect")
hook.Add("player_disconnect", "AdvInv_MountedWeapons", function(data)
    for ent, store in pairs(AdvInv.mountedWeps) do
        if not IsValid(ent) or (ent:IsPlayer() and ent:UserID() == data.userid) then
            clearStore(store)
            AdvInv.mountedWeps[ent] = nil
        end
    end
end)

I.HeldInHands = heldInHands
