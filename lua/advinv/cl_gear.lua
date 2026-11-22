--[[
    Fixe un modèle client (objet porté) sur sa cible : joueur, ragdoll ou entité d'un aperçu.

    attach == nil : bonemerge. Le modèle doit être riggé sur le squelette ValveBiped.
    attach = { bone = "ValveBiped.Bip01_Head1", pos = Vector(...), ang = Angle(...), scale = 1 } :
        n'importe quel prop. Il suit l'os avec ce décalage (Entity:FollowBone, calculé par
        le moteur, sans Lua à chaque image). Sa taille suit celle du personnage.
    bodyFit ("vest", "back" ou nil) : en bonemerge, adapte la position au playermodel
        (voir cl_bodyfit.lua).
--]]
-- Placement of an item on a playermodel: its fit for that model (cl_fits_data.lua, made by
-- tools/fit_items.py), or the item's own ENT.Attach for models that are not in the table.
local fitCache = {}
function AdvInv.AttachFor(class, playermodel, default)
    local fits = AdvInv.Fits and AdvInv.Fits[string.lower(playermodel or "")]
    local f = fits and class and fits[class]
    if not (f and default) then return default end
    local key = class .. "|" .. playermodel
    local a = fitCache[key]
    if not a then
        a = { bone = default.bone, pos = f[1], ang = f[2], scale = f[3] }
        fitCache[key] = a
    end
    return a
end

-- The wearer's own gear is not drawn in first person: it would sit in front of the camera (mask,
-- bucket, backpack...). It still shows in third person and to everyone else; the inventory
-- preview draws its own copies directly.
local function drawGear(self, flags)
    local owner = self:GetParent()
    if owner == LocalPlayer() and not owner:ShouldDrawLocalPlayer() then return end
    self:DrawModel(flags)
end

function AdvInv.MountGearModel(model, target, attach, bodyFit, class)
    model.RenderOverride = drawGear
    model.advinvBaseAttach = attach -- the item's own ENT.Attach; the playermodel's fit is applied on top
    model.advinvClass = class or model.advinvClass
    model.advinvBodyFit = bodyFit
    if attach then attach = AdvInv.AttachFor(model.advinvClass, target:GetModel(), attach) end
    model.advinvAttach = attach
    if not attach then
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

    model:FollowBone(target, boneID)
    model:SetLocalPos(attach.pos or vector_origin)
    model:SetLocalAngles(attach.ang or angle_zero)
end

--[[
    Pour les aperçus (panneau d'inventaire, création de personnage) : place un objet
    en mode attach à la main, juste avant de le dessiner. Ne coûte rien hors des menus.
--]]
function AdvInv.PlaceGearModel(model, target)
    local attach = model.advinvAttach
    if not attach then return end
    local boneID = target:LookupBone(attach.bone or "ValveBiped.Bip01_Head1")
    local matrix = boneID and target:GetBoneMatrix(boneID)
    if not matrix then return end
    local scale = target:GetModelScale()
    local pos, ang = LocalToWorld(
        (attach.pos or vector_origin) * scale,
        attach.ang or angle_zero,
        matrix:GetTranslation(),
        matrix:GetAngles()
    )
    model:SetRenderOrigin(pos)
    model:SetRenderAngles(ang)
    local wanted = (attach.scale or 1) * scale
    if model:GetModelScale() ~= wanted then
        model:SetModelScale(wanted, 0)
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
    local itemID = net.ReadUInt(7)
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
    local itemID = net.ReadUInt(7)
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
    for k, g in pairs(AdvInv.mountedGear[uid]) do
        if g:IsValid() then
            hideGear(g)
        else
            AdvInv.mountedGear[uid][k] = nil
        end
    end
end

local function showGear(g)
    g:DrawShadow(true)
    g:SetMaterial("")
    g:SetRenderMode(RENDERMODE_NORMAL)
end

net.Receive("advinv_gear_vis", function()
    local p = net.ReadEntity()
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
        if replace then
            AdvInv.mountedGear[uid][cat]:Remove()
        else
            return
        end
    end
    -- draw the new one
    if gearID > 1 then
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

hook.Add(
    "EntityNetworkedVarChanged",
    "AdvInv_Gear_Update",
    function(ent, name, oldval, newval)
        if AdvInv.GearCat[name] then
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
            if AdvInv.mountedGear[ent:UserID()] then
                for _, v in pairs(AdvInv.mountedGear[ent:UserID()]) do
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
    AdvInv.mountedGear = AdvInv.mountedGear or {}
    AdvInv.mountedGear[userid] = AdvInv.mountedGear[userid] or {}
    for _, v in pairs(AdvInv.mountedGear[userid]) do
        if v.Remove then v:Remove() end
    end
end
gameevent.Listen("player_disconnect")
hook.Add("player_disconnect", "AdvInv_RemovePlayerGear", function(data)
    unmountGear(data.userid)
end)

-- À la mort du joueur, son équipement affiché passe sur son corps (ragdoll côté client).
hook.Add("NetworkEntityCreated", "AdvInvNetworkEntityCreated", function(ent)
    local owner = ent:GetOwner()
    if not (IsValid(owner) and owner:IsPlayer() and ent:GetClass() == "prop_ragdoll") then return end
    local ragdoll = ent
    local userid = owner:UserID()
    local ragdollid = ragdoll:EntIndex()
    AdvInv.mountedGear[userid] = AdvInv.mountedGear[userid] or {}
    AdvInv.mountedGear[ragdollid] = {}
    for k, gear in pairs(AdvInv.mountedGear[userid]) do
        AdvInv.mountedGear[userid][k] = nil
        if IsValid(gear) then
            local model = ClientsideModel(gear:GetModel(), RENDERGROUP_OPAQUE)
            AdvInv.MountGearModel(model, ragdoll, gear.advinvBaseAttach or gear.advinvAttach, gear.advinvBodyFit, gear.advinvClass)
            model:SetIK(false)
            model:SetTransmitWithParent(true)
            AdvInv.mountedGear[ragdollid][k] = model
            gear:Remove()
        end
    end
    ragdoll:CallOnRemove("AdvInvCleanUpRagdoll", function()
        for _, gear in pairs(AdvInv.mountedGear[ragdollid] or {}) do
            if IsValid(gear) then gear:Remove() end
        end
        AdvInv.mountedGear[ragdollid] = nil
    end)
end)
