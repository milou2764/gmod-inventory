-- Panneaux génériques de l'inventaire
-- (AdvInvAdjustableModelPanel pour la création de personnage, AdvInvBinder pour les touches).

-- Échelle de l'interface : les positions sont données pour un écran de 1920 x 1080 ; on prend
-- le plus petit des deux rapports pour que tout tienne à l'écran, quel que soit son format.
function AdvInv.ScreenScale()
    return math.min(ScrW() / 1920, ScrH() / 1080)
end

function AdvInv.S(v)
    return math.Round(v * AdvInv.ScreenScale())
end

local AdvInvSpawnIcon = {}

function AdvInvSpawnIcon:SetSize(width, height)
    baseclass.Get("Panel").SetSize(self, width * AdvInv.ScreenScale(), height * AdvInv.ScreenScale())
end

function AdvInvSpawnIcon:SetPos(x, y)
    baseclass.Get("Panel").SetPos(self, x * AdvInv.ScreenScale(), y * AdvInv.ScreenScale())
end

vgui.Register("AdvInvSpawnIcon", AdvInvSpawnIcon, "SpawnIcon")

local AdvInvAdjustableModelPanel = {}
AdvInvAdjustableModelPanel.SetSize = AdvInvSpawnIcon.SetSize
AdvInvAdjustableModelPanel.SetPos = AdvInvSpawnIcon.SetPos

function AdvInvAdjustableModelPanel:Init()
    self.mx = 0
    self.my = 0
    self.aLookAngle = Angle(0.000, 213.889, 0.000)
    self.vCamPos = Vector(33.666279, 23.161373, 37.288376)
end

function AdvInvAdjustableModelPanel:LayoutEntity(ent)
    if self.advinvAutoFit then self:FitCamera(ent) end
end

--[[
    Keeps the whole character inside the window (advinvAutoFit): his bones (padded for the mesh),
    the gear he wears and what self.advinvFitExtra(add) adds (the weapon in his hands), whatever the
    pose and the side he is seen from. The camera looks at the middle of all that and stands back as
    far as needed, never closer than advinvFitMinDist. The horizontal field of view is GetFOV().
--]]
local FIT_PAD = 4        -- the mesh goes a little beyond the bones (hands, feet)
local FIT_PAD_HEAD = 10  -- the top of the head is well above the head bone
local FIT_FILL = 0.95    -- part of the window the character may fill

local FIT_GEAR_MARGIN = 22 -- worn gear goes at most this far beyond the body (some props declare huge boxes)

local function boxCorners(m, add, lo, hi)
    -- a prop following a bone: its mesh's box where it is drawn (cl_gear.lua places it); gear drawn from
    -- a playermodel (sh_modelgear_items.lua): the box of that gear as worn, not the whole playermodel's
    local mn, mx
    local t = m.advinvClass and AdvInv.ClassTable(m.advinvClass)
    if m.advinvAttach and t and t.WornBox then
        mn, mx = t.WornBox[1], t.WornBox[2]
    elseif m.advinvAttach and AdvInv.MeshBox then
        mn, mx = AdvInv.MeshBox(m:GetModel())
    end
    local origin, ang, scale = m:GetPos(), m:GetAngles(), 1
    if mn then
        origin, ang, scale = m:GetRenderOrigin() or origin, m:GetRenderAngles() or ang, m:GetModelScale()
    else
        mn, mx = m:GetRenderBounds()
    end
    for k = 0, 7 do
        local p = LocalToWorld(Vector(bit.band(k, 1) > 0 and mx.x or mn.x, bit.band(k, 2) > 0 and mx.y or mn.y,
            bit.band(k, 4) > 0 and mx.z or mn.z) * scale, angle_zero, origin, ang)
        if lo then
            p = Vector(math.Clamp(p.x, lo.x, hi.x), math.Clamp(p.y, lo.y, hi.y), math.Clamp(p.z, lo.z, hi.z))
        end
        add(p, 0)
    end
end

function AdvInvAdjustableModelPanel:FitCamera(ent)
    local w, h = self:GetSize()
    if w < 2 or h < 2 or not IsValid(ent) then return end
    local pts, pads = {}, {}
    local function add(p, pad)
        pts[#pts + 1] = p
        pads[#pts] = pad or 0
    end
    ent:SetupBones()
    local head = ent:LookupBone("ValveBiped.Bip01_Head1")
    for i = 0, ent:GetBoneCount() - 1 do
        local m = ent:GetBoneMatrix(i)
        -- turntable: forearms and hands left out (holding a weapon they reach far forward, and the
        -- distance must hold on every side: they may go past the edges)
        local skip = false
        if self.advinvTurntable then
            local n = ent:GetBoneName(i) or ""
            skip = n:find("Forearm", 1, true) or n:find("Hand", 1, true) or n:find("Finger", 1, true)
                or n:find("Wrist", 1, true) or n:find("Ulna", 1, true) or n:find("Elbow", 1, true)
                or n:find("Anim_Attachment", 1, true)
        end
        if m and not skip then add(m:GetTranslation(), i == head and FIT_PAD_HEAD or FIT_PAD) end
    end
    local lo, hi = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
    for _, p in ipairs(pts) do
        lo = Vector(math.min(lo.x, p.x), math.min(lo.y, p.y), math.min(lo.z, p.z))
        hi = Vector(math.max(hi.x, p.x), math.max(hi.y, p.y), math.max(hi.z, p.z))
    end
    local margin = Vector(FIT_GEAR_MARGIN, FIT_GEAR_MARGIN, FIT_GEAR_MARGIN)
    for _, c in pairs(ent:GetChildren()) do
        if IsValid(c) and not c.advinvHiddenNoBone and c ~= self.advinvHeldModel and not c:IsEffectActive(EF_BONEMERGE) then
            boxCorners(c, add, #pts > 0 and lo - margin or nil, hi + margin)
        end
    end
    -- turntable: the character alone is framed, the same with or without a weapon in his hands (a long
    -- gun would hold the camera back on every side: it may go past the edges)
    if self.advinvTurntable then
        if #pts == 0 then return end
        return self:FitTurntable(ent, pts, pads)
    end
    if self.advinvFitExtra then self.advinvFitExtra(add) end
    if #pts == 0 then return end

    local look = Angle(0, self.aLookAngle and self.aLookAngle.y or 0, 0)
    local fwd, right = look:Forward(), look:Right()
    local rmin, rmax, zmin, zmax = math.huge, -math.huge, math.huge, -math.huge
    for i, p in ipairs(pts) do
        local r = p:Dot(right)
        rmin, rmax = math.min(rmin, r - pads[i]), math.max(rmax, r + pads[i])
        zmin, zmax = math.min(zmin, p.z - pads[i]), math.max(zmax, p.z + pads[i])
    end
    local center = right * ((rmin + rmax) / 2)
    center.z = (zmin + zmax) / 2
    local th = math.tan(math.rad((self:GetFOV() or 70) / 2)) * FIT_FILL
    local tv = th * h / w
    local dist = self.advinvFitMinDist or 0
    for i, p in ipairs(pts) do
        local d = p - center
        local across = math.max((math.abs(d:Dot(right)) + pads[i]) / th, (math.abs(d.z) + pads[i]) / tv)
        dist = math.max(dist, across - d:Dot(fwd))
    end
    self.vCamPos = center - fwd * dist
    self.aLookAngle = look
end

--[[
    Turntable (advinvTurntable): the camera stays in front and the character turns when dragged. The
    distance holds whatever side he shows: each point counts at its distance from his vertical axis, as
    if it could be on any side. advinvFitUpper: from his belt up (all the gear is there): only what is
    above the belt counts, the top of his head stays near the top of the window and the rest of the
    window's height goes below (a tall window shows more than the upper body when the width sets the
    distance). advinvFitBottom: part of the window's height covered at the bottom (the wallet bar).
--]]
local UPPER_BELOW = 4 -- below the pelvis bone: the belt and what hangs on it
local TOP_NEAR = 8    -- the points this close to the top: how far they come towards the camera

function AdvInvAdjustableModelPanel:FitTurntable(ent, pts, pads)
    local w, h = self:GetSize()
    local axis = ent:GetPos()
    local floor
    if self.advinvFitUpper then
        local pelvis = ent:LookupBone("ValveBiped.Bip01_Pelvis")
        local m = pelvis and ent:GetBoneMatrix(pelvis)
        if m then floor = m:GetTranslation().z - UPPER_BELOW end
    end
    local keep, zmin, zmax = {}, math.huge, -math.huge
    for i, p in ipairs(pts) do
        if not floor or p.z - pads[i] >= floor then -- (below the belt: may be cut by the window's bottom)
            keep[#keep + 1] = i
            zmin, zmax = math.min(zmin, p.z - pads[i]), math.max(zmax, p.z + pads[i])
        end
    end
    if #keep == 0 then return end
    if floor then zmin = math.min(zmin, floor) end
    local radius = {}
    local rmax, rtop = 0, 0
    for _, i in ipairs(keep) do
        local p = pts[i]
        local r = math.sqrt((p.x - axis.x) ^ 2 + (p.y - axis.y) ^ 2) + pads[i]
        radius[i] = r
        rmax = math.max(rmax, r)
        if p.z + pads[i] > zmax - TOP_NEAR then rtop = math.max(rtop, r) end
    end
    local th = math.tan(math.rad((self:GetFOV() or 70) / 2)) * FIT_FILL
    local tv = th * h / w
    local f = math.Clamp(self.advinvFitBottom or 0, 0, 0.5)
    local side = math.sqrt(1 + 1 / (th * th)) -- a point at radius r, on its worst side
    local byWidth = rmax * side
    local byHeight = (zmax - zmin) / (2 * tv * (1 - f)) + rtop / (2 * (1 - f))
    local dist = math.max(self.advinvFitMinDist or 0, byWidth, byHeight)
    local look = Angle(0, 180, 0)
    -- the top (as near the camera as it may come) at the top of the window
    local center = Vector(axis.x, axis.y, zmax - (dist - rtop) * tv)
    self.advinvFitInfo = { dist = dist, by = byWidth >= byHeight and "width" or "height", rmax = rmax, rtop = rtop,
        zmin = zmin, zmax = zmax } -- (what set the distance: tests)
    self.vCamPos = center - look:Forward() * dist
    self.aLookAngle = look
end

-- Turntable: dragging with the left button turns the character (the cursor is held in place meanwhile).
function AdvInvAdjustableModelPanel:OnMousePressed(code)
    if not self.advinvTurntable then return baseclass.Get("DAdjustableModelPanel").OnMousePressed(self, code) end
    if code ~= MOUSE_LEFT then return end
    self:SetCursor("none")
    self:MouseCapture(true)
    self.Capturing = true
    self.MouseKey = code
    self:CaptureMouse()
end

function AdvInvAdjustableModelPanel:Think()
    if not self.advinvTurntable then return baseclass.Get("DAdjustableModelPanel").Think(self) end
    if not self.Capturing then return end
    if not input.IsMouseDown(MOUSE_LEFT) then return self:OnMouseReleased(MOUSE_LEFT) end
    local dx = self:CaptureMouse()
    if dx ~= 0 and IsValid(self.Entity) then
        local a = self.Entity:GetAngles()
        self.Entity:SetAngles(Angle(0, math.NormalizeAngle(a.y + dx * 0.5), 0))
    end
end

function AdvInvAdjustableModelPanel:OnMouseWheeled(delta)
    if not self.advinvTurntable then return baseclass.Get("DAdjustableModelPanel").OnMouseWheeled(self, delta) end
end

-- Dessine le personnage et les objets portés (enfants de l'entité de l'aperçu), sans sortir du cadre.
function AdvInvAdjustableModelPanel:DrawModel()
    local curparent = self
    local leftx, topy = self:LocalToScreen(0, 0)
    local rightx, bottomy = self:LocalToScreen(self:GetWide(), self:GetTall())

    while curparent:GetParent() ~= nil do
        curparent = curparent:GetParent()
        local x1, y1 = curparent:LocalToScreen(0, 0)
        local x2, y2 = curparent:LocalToScreen(curparent:GetWide(), curparent:GetTall())
        leftx = math.max(leftx, x1)
        topy = math.max(topy, y1)
        rightx = math.min(rightx, x2)
        bottomy = math.min(bottomy, y2)
    end

    render.SetScissorRect(leftx, topy, rightx, bottomy, true)
    self.Entity.advinvPreview = true -- its gear draws with it (cl_gear.lua)
    local ret = self:PreDrawModel(self.Entity)

    if ret ~= false then
        self.Entity:DrawModel()
        self:PostDrawModel(self.Entity)

        for _, m in pairs(self.Entity:GetChildren()) do
            if not m.advinvHiddenNoBone then
                AdvInv.PlaceGearModel(m, self.Entity)
                m:DrawModel()
                -- the parts it shares with its pack's playermodel (straps...), as in the world
                local t = m.advinvClass and AdvInv.ClassTable(m.advinvClass)
                if t and t.ModelSharedLooks and m.advinvAttach and AdvInv.DrawSharedParts then AdvInv.DrawSharedParts(m, t, true) end
                self:PostDrawModel(m)
            end
        end
        -- equipped weapons on the body (the one in the hands is left out)
        if IsValid(self.advinvOwner) and AdvInv.DrawMountedWeapons then
            AdvInv.DrawMountedWeapons(self.Entity, self.advinvOwner, self.advinvWeaponHidden or function() return false end)
        end
    end

    render.SetScissorRect(0, 0, 0, 0, false)
end

-- Rotation de la caméra autour du personnage à la souris (pas de déplacement libre).
function AdvInvAdjustableModelPanel:FirstPersonControls()
    local x, _ = self:CaptureMouse()
    local scale = self:GetFOV() / 180
    x = x * -0.5 * scale

    if self.MouseKey == MOUSE_LEFT then
        self.aLookAngle = self.aLookAngle + Angle(0, x * 4, 0)
        self.vCamPos = self.OrbitPoint - self.aLookAngle:Forward() * self.OrbitDistance
        return
    end

    self.aLookAngle = self.aLookAngle + Angle(0, x, 0)
end

vgui.Register("AdvInvAdjustableModelPanel", AdvInvAdjustableModelPanel, "DAdjustableModelPanel")

-- Jauge verticale (blindage, munitions d'une arme) : getFraction() renvoie 0 à 1.
local AdvInvProgress = {}
AdvInvProgress.color = Color(255, 255, 255, 100)
AdvInvProgress.getFraction = function() return 0 end
AdvInvProgress.SetSize = AdvInvSpawnIcon.SetSize
AdvInvProgress.SetPos = AdvInvSpawnIcon.SetPos

function AdvInvProgress:Paint(w, h)
    local fraction = math.Clamp(self.getFraction() or 0, 0, 1)
    surface.SetDrawColor(self.color)
    surface.DrawRect(0, h * (1 - fraction), w, h * fraction)
end

vgui.Register("AdvInvProgress", AdvInvProgress, "Panel")

local AdvInvBinder = {}

function AdvInvBinder:UpdateText()
    local str = input.GetKeyName(self:GetSelectedNumber())
    if not str then
        str = "NONE"
    end
    str = language.GetPhrase(str)
    self:SetText(string.upper(str))
end

vgui.Register("AdvInvBinder", AdvInvBinder, "DBinder")
