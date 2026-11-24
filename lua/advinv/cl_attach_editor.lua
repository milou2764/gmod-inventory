--[[
    Worn item placement editor.
    Console: advinv_attach_editor [item class or model path]

    Shows your playermodel wearing the item and lets you tune the bone, offset, rotation and
    size; "Copy the code" then puts the ENT.Model / ENT.Attach block in the clipboard (and in
    the console). Nothing is sent to the server: the preview is purely local.
--]]
local L = AdvInv.L

local editor

local function attachCode(modelPath, a)
    return string.format(
        'ENT.Model = "%s"\nENT.Attach = {\n    bone = "%s",\n' ..
        '    pos = Vector(%.2f, %.2f, %.2f),\n    ang = Angle(%.1f, %.1f, %.1f),\n    scale = %.2f,\n}\n',
        modelPath, a.bone, a.pos.x, a.pos.y, a.pos.z, a.ang.p, a.ang.y, a.ang.r, a.scale
    )
end

local function initialValues(arg)
    local modelPath = "models/barneyhelmet.mdl"
    local attach = {
        bone = "ValveBiped.Bip01_Head1",
        pos = Vector(0, 0, 0),
        ang = Angle(0, 0, 0),
        scale = 1,
    }
    local bonemerge = false

    if arg and arg ~= "" then
        local tab = scripted_ents.Get(arg)
        if tab and tab.Model then
            modelPath = tab.Model
            if tab.Attach then
                attach.bone = tab.Attach.bone or attach.bone
                attach.pos = Vector(tab.Attach.pos or vector_origin)
                attach.ang = Angle(tab.Attach.ang or angle_zero)
                attach.scale = tab.Attach.scale or 1
            else
                bonemerge = true
            end
        else
            modelPath = arg
        end
    end

    return modelPath, attach, bonemerge
end

local function openEditor(arg)
    if IsValid(editor) then editor:Remove() end
    local ply = LocalPlayer()
    local modelPath, attach, bonemerge = initialValues(arg)
    local cam = { yaw = 160, pitch = 10, dist = 45 }

    editor = vgui.Create("DFrame")
    editor:SetTitle(L("editor_title"))
    editor:SetSize(math.min(ScrW() - 40, 1000), math.min(ScrH() - 40, 680))
    editor:Center()
    editor:MakePopup()

    local prop = ClientsideModel(modelPath, RENDERGROUP_OPAQUE)
    prop:SetNoDraw(true)
    function editor:OnRemove()
        if IsValid(prop) then prop:Remove() end
    end

    -- Réglages (à droite)
    local side = vgui.Create("DScrollPanel", editor)
    side:Dock(RIGHT)
    side:SetWide(340)
    side:DockMargin(8, 0, 0, 0)

    local function heading(text)
        local l = vgui.Create("DLabel", side)
        l:Dock(TOP)
        l:DockMargin(0, 8, 0, 2)
        l:SetText(text)
        l:SetFont("DermaDefaultBold")
    end

    local function slider(label, min, max, decimals, value, onChange)
        local s = vgui.Create("DNumSlider", side)
        s:Dock(TOP)
        s:SetText(label)
        s:SetMin(min)
        s:SetMax(max)
        s:SetDecimals(decimals)
        s:SetValue(value)
        s.OnValueChanged = function(_, v) onChange(v) end
        return s
    end

    heading(L("editor_model"))
    local path = vgui.Create("DTextEntry", side)
    path:Dock(TOP)
    path:SetText(modelPath)
    path.OnEnter = function(self)
        local p = string.Trim(self:GetValue())
        if util.IsValidModel(p) or file.Exists(p, "GAME") then
            modelPath = p
            prop:SetModel(p)
        else
            notification.AddLegacy(L("editor_model_missing", p), NOTIFY_ERROR, 4)
        end
    end

    local bm = vgui.Create("DCheckBoxLabel", side)
    bm:Dock(TOP)
    bm:DockMargin(0, 4, 0, 0)
    bm:SetText(L("editor_bonemerge"))
    bm:SetValue(bonemerge)
    bm.OnChange = function(_, v) bonemerge = v end

    heading(L("editor_bone"))
    local boneBox = vgui.Create("DComboBox", side)
    boneBox:Dock(TOP)

    heading(L("editor_offset"))
    slider("X", -40, 40, 2, attach.pos.x, function(v) attach.pos.x = v end)
    slider("Y", -40, 40, 2, attach.pos.y, function(v) attach.pos.y = v end)
    slider("Z", -40, 40, 2, attach.pos.z, function(v) attach.pos.z = v end)

    heading(L("editor_rotation"))
    slider("Pitch", -180, 180, 1, attach.ang.p, function(v) attach.ang.p = v end)
    slider("Yaw", -180, 180, 1, attach.ang.y, function(v) attach.ang.y = v end)
    slider("Roll", -180, 180, 1, attach.ang.r, function(v) attach.ang.r = v end)

    heading(L("editor_size"))
    slider(L("editor_scale"), 0.1, 3, 2, attach.scale, function(v) attach.scale = v end)

    heading(L("editor_camera"))
    slider(L("editor_cam_rotation"), -180, 180, 0, cam.yaw, function(v) cam.yaw = v end)
    slider(L("editor_cam_height"), -89, 89, 0, cam.pitch, function(v) cam.pitch = v end)
    slider(L("editor_cam_distance"), 10, 150, 0, cam.dist, function(v) cam.dist = v end)

    local copy = vgui.Create("DButton", side)
    copy:Dock(TOP)
    copy:DockMargin(0, 12, 0, 0)
    copy:SetTall(30)
    copy:SetText(L("editor_copy"))
    copy.DoClick = function()
        local code
        if bonemerge then
            code = string.format('ENT.Model = "%s"\n-- %s\n', modelPath, L("editor_rigged_comment"))
        else
            code = attachCode(modelPath, attach)
        end
        SetClipboardText(code)
        print(code)
        notification.AddLegacy(L("editor_copied"), NOTIFY_GENERIC, 3)
    end

    -- Aperçu (à gauche)
    local preview = vgui.Create("DModelPanel", editor)
    preview:Dock(FILL)
    preview:SetModel(ply:GetModel())
    preview:SetFOV(35)
    local ent = preview.Entity
    ent:SetSkin(ply:GetSkin())
    for i = 0, ply:GetNumBodyGroups() - 1 do
        ent:SetBodygroup(i, ply:GetBodygroup(i))
    end
    local seq = ent:LookupSequence("idle_all_01")
    if seq and seq > 0 then ent:ResetSequence(seq) end

    for i = 0, ent:GetBoneCount() - 1 do
        local name = ent:GetBoneName(i)
        if name and name ~= "__INVALIDBONE__" then
            boneBox:AddChoice(name, nil, name == attach.bone)
        end
    end
    boneBox.OnSelect = function(_, _, value) attach.bone = value end

    -- Caméra centrée sur l'os réglé (appelé avant le rendu de chaque image).
    function preview:LayoutEntity(e)
        local id = e:LookupBone(attach.bone)
        local m = id and e:GetBoneMatrix(id)
        local center = m and m:GetTranslation() or Vector(0, 0, 60)
        self:SetLookAt(center)
        self:SetCamPos(center - Angle(cam.pitch, cam.yaw, 0):Forward() * cam.dist)
    end

    function preview:PostDrawModel(e)
        if not IsValid(prop) then return end
        if bonemerge then
            if prop:GetParent() ~= e then
                prop:SetParent(e)
                prop:AddEffects(EF_BONEMERGE)
            end
            prop:SetRenderOrigin(nil)
            prop:SetRenderAngles(nil)
            prop:SetModelScale(1, 0)
        else
            if prop:GetParent() == e then
                prop:SetParent(NULL)
                prop:RemoveEffects(EF_BONEMERGE)
            end
            prop.advinvAttach = attach
            AdvInv.PlaceGearModel(prop, e)
        end
        prop:DrawModel()
    end
end

concommand.Add(
    "advinv_attach_editor",
    function(_, _, args) openEditor(args[1]) end,
    nil,
    "Opens the worn item placement editor (argument: item class or model path)"
)
