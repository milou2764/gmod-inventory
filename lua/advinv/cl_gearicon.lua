--[[
    "AdvInvGearIcon": a worn prop (helmet, vest, backpack...) shown as it is worn: placed on an
    invisible reference body with its fit, seen from the front three-quarters (backpacks from the
    back), framed on its mesh. The engine's spawn icons frame a model by the box it declares, which
    many Workshop props get wrong (a huge box: a speck in the slot; an offset origin: off the slot).
    Used for the items of compatible addons (ENT.AdvInvCompat) and items with ENT.IconAsWorn = true.
--]]
local I = AdvInv

local REF_BODY = "models/player/group01/male_07.mdl"
local VIEWS = { -- direction from the item to the camera, in the body's frame (it faces +X)
    Rucksack = Angle(-14, 145, 0),
    default = Angle(-10, 35, 0),
}

local body
local function refBody()
    if IsValid(body) then return body end
    body = ClientsideModel(REF_BODY, RENDERGROUP_OPAQUE)
    if not IsValid(body) then return end
    body:SetNoDraw(true)
    body:SetPos(vector_origin)
    body:SetAngles(angle_zero)
    body:ResetSequence(body:LookupSequence("idle_all_01") or 0)
    body:SetCycle(0)
    body.advinvPreview = true
    body:SetupBones()
    return body
end

-- Points of a model's mesh in its own space (sampled), cached by path.
local meshCache = {}
local function meshPoints(path)
    local pts = meshCache[path]
    if pts ~= nil then return pts or nil end
    local ok, meshes = pcall(util.GetModelMeshes, path, 0, 0)
    pts = {}
    if ok and istable(meshes) then
        local count = 0
        for _, m in ipairs(meshes) do count = count + #(m.triangles or {}) end
        local step = math.max(1, math.floor(count / 3000))
        local i = 0
        for _, m in ipairs(meshes) do
            for _, v in ipairs(m.triangles or {}) do
                i = i + 1
                if i % step == 0 and v.pos then pts[#pts + 1] = v.pos end
            end
        end
    end
    meshCache[path] = #pts > 0 and pts or false
    return meshCache[path] or nil
end

-- Box of a model's mesh in its own space (mins, maxs), or nil: some props declare a far bigger box.
local boxCache = {}
function I.MeshBox(path)
    local b = boxCache[path]
    if b ~= nil then if b then return b[1], b[2] end return end
    local pts = meshPoints(path)
    if not pts then boxCache[path] = false return end
    local mn, mx = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
    for _, p in ipairs(pts) do
        mn = Vector(math.min(mn.x, p.x), math.min(mn.y, p.y), math.min(mn.z, p.z))
        mx = Vector(math.max(mx.x, p.x), math.max(mx.y, p.y), math.max(mx.z, p.z))
    end
    boxCache[path] = { mn, mx }
    return mn, mx
end

-- One worn copy per class, placed on the reference body, with its frame for each view.
local worn = {}
local function wornModel(class)
    local w = worn[class]
    if w ~= nil then return w or nil end
    local t = I.ClassTable and I.ClassTable(class)
    local b = refBody()
    if not (t and t.Model and b and file.Exists(t.Model, "GAME")) then
        worn[class] = false
        I.WornIconWhy = class .. ": " .. (not b and "no reference body" or "no model")
        return
    end
    local m = ClientsideModel(t.Model, RENDERGROUP_OPAQUE)
    if not IsValid(m) then worn[class] = false I.WornIconWhy = class .. ": model not created" return end
    m:SetNoDraw(true)
    I.SetupItemModel(m, t) -- gear drawn from a playermodel: its stored look, the rest hidden
    I.MountGearModel(m, b, t.Attach, t.BodyFit, class)
    m.RenderOverride = nil -- drawn by the icon itself
    if m.advinvAttach then I.PlaceGearModel(m, b) end
    w = { model = m, cat = t.AdvInvCategory, pieces = t.ModelPieces, t = t }
    -- world points of the mesh (props follow a bone: the render origin and angles placed above); gear
    -- drawn from a playermodel: its hull around its centre (the playermodel's own mesh is all of it)
    local pts = meshPoints(t.Model)
    if t.PhysHull and t.ModelOrigin then
        pts = {}
        for _, p in ipairs(t.PhysHull) do pts[#pts + 1] = p + t.ModelOrigin end
    end
    local origin, ang, scale = m:GetRenderOrigin() or m:GetPos(), m:GetRenderAngles() or m:GetAngles(), m:GetModelScale()
    local world = {}
    if pts and m.advinvAttach then
        for _, p in ipairs(pts) do world[#world + 1] = LocalToWorld(p * scale, angle_zero, origin, ang) end
    else -- rigged (bonemerged) or no mesh: its box
        local mn, mx = m:GetRenderBounds()
        for k = 0, 7 do
            world[#world + 1] = LocalToWorld(Vector(bit.band(k, 1) > 0 and mx.x or mn.x, bit.band(k, 2) > 0 and mx.y or mn.y,
                bit.band(k, 4) > 0 and mx.z or mn.z), angle_zero, origin, ang)
        end
    end
    -- the view and the frame around the projected points
    local dir = (VIEWS[w.cat] or VIEWS.default):Forward()
    local camAng = (-dir):Angle()
    local right, up = camAng:Right(), camAng:Up()
    local center = Vector(0, 0, 0)
    for _, p in ipairs(world) do center = center + p end
    center = center / math.max(#world, 1)
    local l, r, b2, t2 = math.huge, -math.huge, math.huge, -math.huge
    for _, p in ipairs(world) do
        local d = p - center
        local x, y = d:Dot(right), d:Dot(up)
        l, r, b2, t2 = math.min(l, x), math.max(r, x), math.min(b2, y), math.max(t2, y)
    end
    if l > r then worn[class] = false m:Remove() I.WornIconWhy = class .. ": no points" return end
    w.center = center + right * ((l + r) / 2) + up * ((b2 + t2) / 2)
    w.halfW, w.halfH = math.max((r - l) / 2, 0.5), math.max((t2 - b2) / 2, 0.5)
    w.camAng, w.dir = camAng, dir
    worn[class] = w
    return w
end

I.WornIconFrame = wornModel -- (debugging)

local ICON = {}

function ICON:Init()
    self:SetText("")
end

function ICON:SetItemClass(class)
    self.itemClass = class
end

function ICON:Paint(w, h)
    local g = self.itemClass and wornModel(self.itemClass)
    if not g or not IsValid(g.model) then return end
    local scale = math.min(w * 0.86 / (g.halfW * 2), h * 0.86 / (g.halfH * 2)) -- pixels per unit
    local hw, hh = w / scale / 2, h / scale / 2
    local x, y = self:LocalToScreen(0, 0)
    local l, t, r, b = x, y, x + w, y + h
    local p = self
    while p:GetParent() ~= nil do -- visible part (in a scrolled list)
        p = p:GetParent()
        local px, py = p:LocalToScreen(0, 0)
        l, t = math.max(l, px), math.max(t, py)
        r, b = math.min(r, px + p:GetWide()), math.min(b, py + p:GetTall())
    end
    if r <= l or b <= t then return end
    if g.model.advinvAttach and IsValid(body) then I.PlaceGearModel(g.model, body) end
    cam.Start({
        type = "3D", x = x, y = y, w = w, h = h,
        origin = g.center + g.dir * 200, angles = g.camAng,
        ortho = { left = -hw, right = hw, top = -hh, bottom = hh },
        znear = 1, zfar = 500,
    })
    render.SetScissorRect(l, t, r, b, true)
    render.SuppressEngineLighting(true)
    render.SetLightingOrigin(g.center)
    render.ResetModelLighting(0.4, 0.4, 0.42)
    render.SetModelLighting(BOX_TOP, 1, 1, 1)
    render.SetModelLighting(BOX_FRONT, 0.8, 0.8, 0.8)
    render.SetModelLighting(BOX_BACK, 0.8, 0.8, 0.8)
    render.SetColorModulation(1, 1, 1)
    render.SetBlend(1)
    if g.pieces then I.DrawModelPieces(g.model, g.pieces) else g.model:DrawModel() end
    if g.t and g.t.ModelSharedLooks then I.DrawSharedParts(g.model, g.t, false) end
    render.SuppressEngineLighting(false)
    render.SetScissorRect(0, 0, 0, 0, false)
    cam.End3D()
end

vgui.Register("AdvInvGearIcon", ICON, "DButton")

-- Should this item's icon be drawn as worn?
function I.UsesGearIcon(class)
    local t = class and I.ClassTable and I.ClassTable(class)
    return t ~= nil and (t.AdvInvCompat ~= nil or t.IconAsWorn == true) and t.AdvInvCategory ~= nil
        and not (I.WeaponCat and table.HasValue(I.WeaponCat, t.AdvInvCategory))
end
