--[[
    Fixe un modèle client (objet porté) sur sa cible : joueur, ragdoll ou entité d'un aperçu.

    attach == nil : bonemerge. Le modèle doit être riggé sur le squelette ValveBiped.
    attach = { bone = "ValveBiped.Bip01_Head1", pos = Vector(...), ang = Angle(...), scale = 1 } :
        n'importe quel prop. Il est placé sur l'os avec ce décalage à chaque image (AdvInv.GearPlacement,
        le même calcul que les ajustements). Sa taille suit celle du personnage.
    bodyFit ("vest", "back" ou nil) : en bonemerge, adapte la position au playermodel
        (voir cl_bodyfit.lua).
--]]
-- Tables keyed by playermodel path are looked up in lowercase (a model's path can be written with
-- capitals, "models/nada/pms/male/Naval_Officer.mdl"): their keys are lowercased once loaded.
function AdvInv.LowerKeys(t)
    if not istable(t) then return end
    local moves = {}
    for k in pairs(t) do
        if isstring(k) and k ~= string.lower(k) then moves[#moves + 1] = k end
    end
    for _, k in ipairs(moves) do
        local l = string.lower(k)
        if t[l] == nil then t[l] = t[k] end
        t[k] = nil
    end
end
AdvInv.LowerKeys(AdvInv.Fits)
-- the fits of the gear packs taken from playermodels (sh_modelgear_items.lua), on top of the inventory's
AdvInv.FitsLoaded = true
for _, pack in ipairs(AdvInv.ModelGearPacks or {}) do AdvInv.MergePackFits(pack) end
AdvInv.LowerKeys(AdvInv.BodyFit and AdvInv.BodyFit.models)

-- Placement of an item on a playermodel: its fit for that model (cl_fits_data.lua, made by
-- tools/fit_items.py), or the item's own ENT.Attach for models that are not in the table.
local fitCache = {}
function AdvInv.AttachFor(class, playermodel, default)
    local fits = AdvInv.Fits and AdvInv.Fits[string.lower(playermodel or "")]
    local f = fits and class and fits[class]
    if default and class and not f then
        -- an item that adapts its own place to a playermodel without a fit (ENT.AdaptAttach: sh_jmod.lua)
        local t = AdvInv.ClassTable(class)
        if not (t and t.AdaptAttach) then return default end
        local key = class .. "|" .. tostring(playermodel)
        local a = fitCache[key]
        if a == nil then
            a = t.AdaptAttach(string.lower(playermodel or ""), default) or false
            fitCache[key] = a
        end
        return a or default
    end
    if not (f and default) then return default end
    local key = class .. "|" .. playermodel
    local a = fitCache[key]
    if not a then
        a = { bone = default.bone, pos = f[1], ang = f[2], scale = f[3], stretch = f[4], depth = f[5] }
        fitCache[key] = a
    end
    return a
end

-- The wearer's own gear is not drawn in first person: it would sit in front of the camera (mask,
-- bucket, backpack...). It still shows in third person and to everyone else; the inventory
-- preview draws its own copies directly.
-- Is the wearer not drawn (dead, out of view, no-draw, cloaked by an admin tool)? Then neither is
-- what he wears or carries.
local CLOAK = "models/effects/vol_light001"
function AdvInv.OwnerHidden(owner)
    if not IsValid(owner) or owner:IsDormant() or owner:GetNoDraw() then return true end
    if owner:IsPlayer() and not owner:Alive() then return true end
    return owner:GetMaterial() == CLOAK or owner:GetColor().a == 0
end

--[[
    Rigid vests (props fitted on Spine4) bend with the torso: drawn halfway between where Spine1 and
    Spine4 would each put them. The two agree in the reference pose the fits were made in; when the
    spine bends (crouching hunches the lower back, a body lying down), the vest follows the middle of
    the torso instead of staying with the shoulders.
--]]
local SPINE2, SPINE4 = "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Spine4" -- (SPINE2: the lower bone of the blend)
local refRel = {} -- [playermodel] = Spine2 -> Spine4 in the reference pose (VMatrix), or false

local function bindBone(bind, base, id, inverse)
    local b = bind[id + base]
    if not (b and b.matrix) then return end
    if inverse then return b.matrix:GetInverse() end
    return b.matrix
end

local pending = {}
local function computeRelation(mdl, b2, b4)
    local r = false
    local ok, _, bind = pcall(util.GetModelMeshes, mdl, 0, 0)
    if ok and istable(bind) and b2 and b4 then
        local base = bind[0] and 0 or 1
        -- the bind matrices are world -> bone; their inverses place the bones in the reference pose
        for _, inverse in ipairs({ true, false }) do
            local m2, m4 = bindBone(bind, base, b2, inverse), bindBone(bind, base, b4, inverse)
            if m2 and m4 then
                local z2, z4 = m2:GetTranslation().z, m4:GetTranslation().z
                if z4 > z2 and z4 > 20 and z4 < 120 then
                    local inv2 = m2:GetInverse()
                    if inv2 then r = inv2 * m4 break end
                end
            end
        end
    end
    refRel[mdl] = r
end

-- The relation of target's playermodel, or nil while it is not known yet: it is read from the model
-- once, out of the drawing (a heavy call), and the vest follows Spine4 until then.
local function torsoRelation(target)
    local mdl = string.lower(target:GetModel() or "")
    local r = refRel[mdl]
    if r ~= nil then return r or nil end
    if not pending[mdl] then
        pending[mdl] = true
        local b2, b4 = target:LookupBone(SPINE2), target:LookupBone(SPINE4)
        timer.Simple(0, function()
            if b2 and b4 then computeRelation(mdl, b2, b4) else refRel[mdl] = false end
        end)
    end
end

-- Where a torso-blended vest is drawn on target now. -> pos, ang (nil: as the bone puts it)
function AdvInv.TorsoPlacement(model, target)
    local attach = model.advinvAttach
    if not (attach and model.advinvTorso) then return end
    local rel = torsoRelation(target)
    local b2, b4 = target:LookupBone(SPINE2), target:LookupBone(SPINE4)
    local M2, M4 = b2 and target:GetBoneMatrix(b2), b4 and target:GetBoneMatrix(b4)
    if not (rel and M2 and M4) then return end
    local T = Matrix()
    T:SetAngles(attach.ang or angle_zero)
    T:SetTranslation((attach.pos or vector_origin) * target:GetModelScale())
    local W4, W2 = M4 * T, M2 * rel * T
    local f = (W2:GetForward() + W4:GetForward()):GetNormalized()
    local u = W2:GetUp() + W4:GetUp()
    u = (u - f * u:Dot(f)):GetNormalized()
    return (W2:GetTranslation() + W4:GetTranslation()) * 0.5, f:AngleEx(u)
end

-- Props following a bone are lit where their wearer is: the engine lights a model at its origin,
-- which for many props is far from their mesh (a vest's origin can sink into the ground when its
-- wearer crouches: drawn black). Sampled once per wearer and frame.
local LIGHT_DIRS = { Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0), Vector(0, 0, 1), Vector(0, 0, -1) }
local lightCache = setmetatable({}, { __mode = "k" })
local function lightFrom(owner)
    local frame = FrameNumber()
    local c = lightCache[owner]
    if not c or c.frame ~= frame then
        c = c or {}
        c.frame, c.pos = frame, owner:WorldSpaceCenter()
        for i, d in ipairs(LIGHT_DIRS) do c[i] = render.ComputeLighting(c.pos, d) end
        lightCache[owner] = c
    end
    render.SuppressEngineLighting(true)
    render.SetLightingOrigin(c.pos)
    render.ResetModelLighting(0, 0, 0)
    for i = 1, 6 do render.SetModelLighting(i - 1, c[i].x, c[i].y, c[i].z) end
end

-- worn gear of an extension painted on its hidden body's material (sh_modelgear_items.lua)
local function drawShared(self)
    local t = self.advinvClass and AdvInv.ClassTable(self.advinvClass)
    -- (a rigid copy only: a bonemerged one bends with its wearer, the mesh at rest wouldn't follow)
    if t and t.ModelSharedLooks and self.advinvAttach then AdvInv.DrawSharedParts(self, t, true) end
end

local function drawGear(self, flags)
    local owner = self:GetParent()
    -- (a preview's character is a no-draw entity drawn by its panel: its gear is drawn with it)
    if not (IsValid(owner) and owner.advinvPreview) and AdvInv.OwnerHidden(owner) then return end
    if owner == LocalPlayer() and not owner:ShouldDrawLocalPlayer() then return end
    -- spectating him through his eyes: the engine doesn't draw him, nor his gear around the camera
    local lp = LocalPlayer()
    if IsValid(lp) and lp:GetObserverMode() == OBS_MODE_IN_EYE and lp:GetObserverTarget() == owner then return end
    -- an item that is drawn otherwise for now (ENT.HideWhenWorn: a JMod mask pushed up, drawn by JMod)
    local t = self.advinvClass and AdvInv.ClassTable(self.advinvClass)
    if t and t.HideWhenWorn and IsValid(owner) and not owner.advinvPreview and t.HideWhenWorn(owner) then return end
    if owner.advinvPreview or not self.advinvAttach then
        self:DrawModel(flags)
        drawShared(self)
        return
    end
    local pos, ang = AdvInv.GearPlacement(self, owner)
    if not pos then return end
    lightFrom(owner)
    self:SetRenderOrigin(pos)
    self:SetRenderAngles(ang)
    -- a colour chosen for the piece (ENT.WornColor: JMod's)
    local col = t and t.WornColor and IsValid(owner) and t.WornColor(owner)
    local r0, g0, b0
    if col then
        r0, g0, b0 = render.GetColorModulation()
        render.SetColorModulation((col.r or 255) / 255, (col.g or 255) / 255, (col.b or 255) / 255)
    end
    self:DrawModel(flags)
    if col then render.SetColorModulation(r0, g0, b0) end
    drawShared(self)
    self:SetRenderOrigin(nil)
    self:SetRenderAngles(nil)
    render.SuppressEngineLighting(false)
end

-- A vest fitted to the body on two axes besides its size: made taller on a body longer than it is wide
-- (the fit's stretch, around the item's ENT.StretchTop: its straps stay on the shoulders) and deeper
-- or shallower front to back (the fit's depth, around ENT.DepthCenter: both its panels clear of the
-- body). The render matrix is in the scaled model's space.
function AdvInv.StretchGear(model, attach, parentScale)
    local t = model.advinvClass and AdvInv.ClassTable(model.advinvClass)
    local top, st = t and t.StretchTop, attach and attach.stretch or 1
    local cx, dp = t and t.DepthCenter, attach and attach.depth or 1
    if not cx then dp = 1 end
    if top and (st ~= 1 or dp ~= 1) then
        local s = (attach.scale or 1) * (parentScale or 1)
        local x, z = (cx or 0) * s, top * s
        local m = Matrix()
        m:Translate(Vector(x, 0, z))
        m:Scale(Vector(dp, 1, st))
        m:Translate(Vector(-x, 0, -z))
        model:EnableMatrix("RenderMultiply", m)
        model.advinvStretched = true
    elseif model.advinvStretched then
        model:DisableMatrix("RenderMultiply")
        model.advinvStretched = nil
    end
end

function AdvInv.MountGearModel(model, target, attach, bodyFit, class)
    model.RenderOverride = drawGear
    model.advinvBaseAttach = attach -- the item's own ENT.Attach; the playermodel's fit is applied on top
    model.advinvClass = class or model.advinvClass
    model.advinvBodyFit = bodyFit
    if attach then attach = AdvInv.AttachFor(model.advinvClass, target:GetModel(), attach) end
    model.advinvAttach = attach
    if not attach then
        AdvInv.StretchGear(model, nil)
        model:SetParent(target)
        model:AddEffects(EF_BONEMERGE)
        model:AddEffects(EF_BONEMERGE_FASTCULL)
        AdvInv.BodyFit.Enable(model, bodyFit)
        return
    end

    local scale = target:GetModelScale()
    model.advinvParentModel = target:GetModel()
    model.advinvParentScale = scale
    model:SetModelScale((attach.scale or 1) * scale, 0)
    AdvInv.StretchGear(model, attach, scale)

    local boneID = target:LookupBone(attach.bone or "ValveBiped.Bip01_Head1")
    if not boneID then
        -- Os absent sur ce playermodel : on cache l'objet plutôt que de l'afficher n'importe où.
        model:SetParent(target)
        if not model:GetNoDraw() then
            model:SetNoDraw(true)
            model.advinvHiddenNoBone = true
        end
        return
    end
    if model.advinvHiddenNoBone then
        model:SetNoDraw(false)
        model.advinvHiddenNoBone = nil
    end

    -- Parented to the wearer and placed each time it is drawn (drawGear, AdvInv.GearPlacement): the
    -- engine's FollowBone places a prop in another frame than the bone matrix on some Workshop
    -- playermodels (their skeleton compiled with another root), which the fits are measured in.
    model:SetParent(target)
    model:SetLocalPos(vector_origin)
    model:SetLocalAngles(angle_zero)
    model:SetRenderBounds(Vector(-96, -96, -48) * scale, Vector(96, 96, 112) * scale) -- around the wearer
    -- a rigid vest on the chest: drawn between Spine1 and Spine4 (see AdvInv.TorsoPlacement)
    model.advinvTorso = (attach.bone == SPINE4) and AdvInv.Config.VestFollowsTorso ~= false or nil
end

--[[
    Pour les aperçus (panneau d'inventaire, création de personnage) : place un objet
    en mode attach à la main, juste avant de le dessiner. Ne coûte rien hors des menus.
--]]
-- Where a prop worn on a bone is drawn on target now: its fit on the bone's matrix (what the fits
-- are measured in), or between Spine1 and Spine4 for a vest. -> pos, ang (nil: no such bone)
function AdvInv.GearPlacement(model, target)
    local attach = model.advinvAttach
    if not attach then return end
    local tpos, tang = AdvInv.TorsoPlacement(model, target)
    if tpos then return tpos, tang end
    local boneID = target:LookupBone(attach.bone or "ValveBiped.Bip01_Head1")
    local matrix = boneID and target:GetBoneMatrix(boneID)
    if not matrix then return end
    return LocalToWorld((attach.pos or vector_origin) * target:GetModelScale(), attach.ang or angle_zero,
        matrix:GetTranslation(), matrix:GetAngles())
end

function AdvInv.PlaceGearModel(model, target)
    local attach = model.advinvAttach
    if not attach then return end
    local pos, ang = AdvInv.GearPlacement(model, target)
    if not pos then return end
    model:SetRenderOrigin(pos)
    model:SetRenderAngles(ang)
    local wanted = (attach.scale or 1) * target:GetModelScale()
    if model:GetModelScale() ~= wanted then
        model:SetModelScale(wanted, 0)
        AdvInv.StretchGear(model, attach, target:GetModelScale())
    end
end

-- Si le playermodel ou sa taille change, les index d'os peuvent changer : on réattache.
timer.Create("AdvInv_GearAttachRefresh", 1, 0, function()
    for _, gears in pairs(AdvInv.mountedGear) do
        for _, g in pairs(gears) do
            if IsValid(g) and g.advinvAttach then
                local parent = g:GetParent()
                if IsValid(parent) and (
                    parent:GetModel() ~= g.advinvParentModel or
                    parent:GetModelScale() ~= g.advinvParentScale
                ) then
                    AdvInv.MountGearModel(g, parent, g.advinvBaseAttach or g.advinvAttach, g.advinvBodyFit, g.advinvClass)
                end
            end
        end
    end
end)

net.Receive("advinv_gear_playerspawn", function()
    local target = net.ReadEntity()

    AdvInv.LoadPlayerGear(target)
end)

net.Receive("advinv_gear_mnt", function()
    local itemID = net.ReadUInt(AdvInv.NET_ID_BITS)
    local itemTable = AdvInv.EntityTable(itemID)
    local target = net.ReadEntity()
    local userid
    if target.UserID then
        userid = target:UserID()
    else
        userid = target:EntIndex()
    end
    AdvInv.mountedGear[userid] = AdvInv.mountedGear[userid] or {}
    AdvInv.mountedGear[userid][itemTable.AdvInvCategory] = itemTable:createCSModel(target)
end)

net.Receive("advinv_gear_umnt", function()
    local itemID = net.ReadUInt(AdvInv.NET_ID_BITS)
    local itemTable = AdvInv.EntityTable(itemID)
    local target = net.ReadEntity()
    itemTable:unmount(target)
end)

local function hideGear(g)
    g:DrawShadow(false)
    g:SetMaterial("models/effects/vol_light001")
    g:SetRenderMode(RENDERMODE_TRANSALPHA)
end

local hideGears = function(uid)
    for k, g in pairs(AdvInv.mountedGear[uid] or {}) do
        if IsValid(g) then
            hideGear(g)
        else
            AdvInv.mountedGear[uid][k] = nil
        end
    end
end

local function showGear(g)
    if not IsValid(g) then return end
    -- (gear cut out of a playermodel keeps no shadow: the hidden body would cast it)
    local t = g.advinvClass and AdvInv.ClassTable(g.advinvClass)
    g:DrawShadow(not (t and t.ModelHiddenMaterials))
    g:SetMaterial("")
    g:SetRenderMode(RENDERMODE_NORMAL)
end

net.Receive("advinv_gear_vis", function()
    local p = net.ReadEntity()
    if not (IsValid(p) and p:IsPlayer()) then return end
    local uid = p:UserID()
    local bool = net.ReadBool()
    local vis = net.ReadInt(8)
    AdvInv.mountedGear[uid] = AdvInv.mountedGear[uid] or {}
    if bool then
        hideGears(uid)
    else
        for _, g in pairs(AdvInv.mountedGear[uid]) do
            showGear(g)
        end
    end
end)

local function updateCSGear(ent, uid, cat, gearID, replace)
    if AdvInv.NoMountCat[cat] then return end -- la tenue n'est pas affichée sur le joueur
    AdvInv.mountedGear[uid] = AdvInv.mountedGear[uid] or {}
    -- a model is already drawn
    if IsValid(AdvInv.mountedGear[uid][cat]) then
        if not replace then return end
        AdvInv.mountedGear[uid][cat]:Remove()
    end
    AdvInv.mountedGear[uid][cat] = nil
    -- the wearer's playermodel shows this item itself, as a bodygroup (sh_modelgear.lua)
    if AdvInv.ShownByModel(ent, gearID) then return end
    -- draw the new one
    if isnumber(gearID) and gearID > 1 then
        local tab = AdvInv.EntityTable(gearID)
        if not tab then
            AdvInv.Log.d("Gear", "invalid gearID " .. gearID)
        else
            AdvInv.mountedGear[uid][cat] =
                tab:createCSModel(ent)
        end
    end
end

AdvInv.UpdateCSGear = updateCSGear

function AdvInv.LoadPlayerGear(p)
    if not IsValid(p) then return end
    if not p:Alive() then return end
    local getID = p.AdvInvGetID
    local userid
    if p.UserID then
        userid = p:UserID()
    else
        userid = p
    end
    AdvInv.mountedGear[userid] = AdvInv.mountedGear[userid] or {}
    for cat,_ in pairs(AdvInv.GearCat) do
        local gearID = p:GetNW2Int(cat)
        updateCSGear(p, userid, cat, gearID, true)
    end
end

-- A playermodel change (a job, a model chooser, or the item arriving before the model) can change
-- what the model shows itself (sh_modelgear.lua): the gear of that player is mounted again.
timer.Create("AdvInv_GearModelWatch", 0.5, 0, function()
    for _, p in ipairs(player.GetAll()) do
        local m = string.lower(p:GetModel() or "")
        local old = p.AdvInvGearModel
        if old ~= m then
            p.AdvInvGearModel = m
            if old and p:Alive() and (AdvInv.ModelGear[old] or AdvInv.ModelGear[m]) then AdvInv.LoadPlayerGear(p) end
        end
    end
end)

hook.Add(
    "EntityNetworkedVarChanged",
    "AdvInv_Gear_Update",
    function(ent, name, oldval, newval)
        -- players and dead bodies only (other entities may use the same names)
        if AdvInv.GearCat[name] and isnumber(newval) and IsValid(ent) and (ent:IsPlayer() or AdvInv.IsBody(ent)) then
            local uid
            if ent.UserID then
                uid = ent:UserID()
            else
                uid = ent
            end
            updateCSGear(ent, uid, name, newval, true)
        end
    end
)

hook.Add("InitPostEntity", "AdvInv_EnableGearRendering", function()
    for _,p in pairs(player.GetAll()) do
        local tab = p:GetTable()
        if
            tab.invis and
            tab.invis.vis > 0
        then
            local uid = p:UserID()
            hideGears(uid)
        end
    end
    hook.Add(
        "NotifyShouldTransmit",
        "AdvInv_ShouldTransmitGear",
        function(ent, shouldTransmit)
            if not ent:IsPlayer() then return end
            do
                for _, v in pairs(AdvInv.mountedGear[ent:UserID()] or {}) do
                    if IsValid(v) and shouldTransmit then
                        v:SetNoDraw(false)
                        AdvInv.MountGearModel(v, ent, v.advinvBaseAttach or v.advinvAttach, v.advinvBodyFit, v.advinvClass)
                    elseif IsValid(v) then
                        v:SetNoDraw(true)
                    end
                end
                -- for when for some reason ent's gear has not
                -- loaded when LocalPlayer joined
                for gearCat,_ in pairs(AdvInv.GearCat) do
                    updateCSGear(
                        ent,
                        ent:UserID(),
                        gearCat,
                        ent:GetNW2Int(gearCat),
                        false
                    )
                end
            end
        end
    )
end)

net.Receive("advinv_gear_follow", function()
    local target = net.ReadEntity()
    AdvInv.Log.d("advinv_gear_follow", "called")
    AdvInv.LoadPlayerGear(target)
end)

local function unmountGear(userid)
    for _, v in pairs(AdvInv.mountedGear[userid] or {}) do
        if IsValid(v) then v:Remove() end
    end
    AdvInv.mountedGear[userid] = nil
end

-- The item list is built after the first snapshot: the players already here get their gear then.
hook.Add("AdvInv_ItemsInitialized", "AdvInv_LoadAllGear", function()
    timer.Simple(0, function()
        for _, p in ipairs(player.GetAll()) do AdvInv.LoadPlayerGear(p) end
    end)
end)
gameevent.Listen("player_disconnect")
hook.Add("player_disconnect", "AdvInv_RemovePlayerGear", function(data)
    unmountGear(data.userid)
end)

-- (The gear of a dead player is on his body: cl_death.lua.)
