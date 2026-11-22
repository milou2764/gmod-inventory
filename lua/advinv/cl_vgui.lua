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

local function boxCorners(m, add)
    local mn, mx = m:GetRenderBounds()
    for k = 0, 7 do
        add(m:LocalToWorld(Vector(bit.band(k, 1) > 0 and mx.x or mn.x, bit.band(k, 2) > 0 and mx.y or mn.y,
            bit.band(k, 4) > 0 and mx.z or mn.z)), 0)
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
        if m then add(m:GetTranslation(), i == head and FIT_PAD_HEAD or FIT_PAD) end
    end
    for _, c in pairs(ent:GetChildren()) do
        if IsValid(c) and not c.advinvHiddenNoBone and c ~= self.advinvHeldModel and not c:IsEffectActive(EF_BONEMERGE) then
            boxCorners(c, add)
        end
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
    local ret = self:PreDrawModel(self.Entity)

    if ret ~= false then
        self.Entity:DrawModel()
        self:PostDrawModel(self.Entity)

        for _, m in pairs(self.Entity:GetChildren()) do
            if not m.advinvHiddenNoBone then
                AdvInv.PlaceGearModel(m, self.Entity)
                m:DrawModel()
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
