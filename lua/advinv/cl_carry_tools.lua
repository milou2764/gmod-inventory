--[[
    Carry modes, dev tools (client only, they change nothing on the server):

    advinv_carry_tune    viewer with your playermodel, your long gun and its carry mode (or any other
                       choice): move the weapon with the sliders, the change shows at once on every
                       model of the same offset set, here and in the world. "Print" writes the
                       values to the console, "Save" to garrysmod/data/advinv_carry_tuned.json (loaded
                       again next time; copy it to tools/carry_overrides.json and run
                       tools/fit_carry.py to ship them).
    advinv_carry_cycle   the same viewer going through every default playermodel x weapon x mode
                       (Previous / Next, or Auto), with a second weapon if wanted, to check them all.
--]]
local I = AdvInv

local TUNED_FILE = "advinv_carry_tuned.json"
local BONES = {
    "ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine1",
    "ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Pelvis",
}
local ANIMS = { "idle_all_01", "idle_passive", "walk_all", "run_all_01", "idle_pistol", "cidle_all" }
local HL2_MODELS = {
    weapon_smg1 = "models/weapons/w_smg1.mdl", weapon_ar2 = "models/weapons/w_irifle.mdl",
    weapon_shotgun = "models/weapons/w_shotgun.mdl", weapon_crossbow = "models/weapons/w_crossbow.mdl",
    weapon_rpg = "models/weapons/w_rocket_launcher.mdl",
}

-- weapon class -> { model = world model, cat = equipment slot }
local function weaponInfo()
    local out = {}
    for id in pairs(AdvInv.IDClass or {}) do
        local t = AdvInv.EntityTable(id)
        if t and t.WeaponClass and t.Model and I.CarryWeapons[t.WeaponClass] then
            out[t.WeaponClass] = { model = t.Model, cat = t.AdvInvCategory }
        end
    end
    for class in pairs(I.CarryWeapons) do
        if not out[class] then
            local swep = weapons.Get(class)
            local model = HL2_MODELS[class] or (swep and swep.WorldModel)
            if model and model ~= "" then
                out[class] = { model = model, cat = class == "weapon_rpg" and "RocketLauncher" or "PrimaryWep" }
            end
        end
    end
    return out
end

local function modesOf(class)
    local conf = I.CarryWeapons[class]
    local out = {}
    for _, m in ipairs((conf and conf.modes) or I.CARRY_MODES) do
        if I.CarryZone[m] then out[#out + 1] = m end -- (not "stowed", nor a removed mode)
    end
    return out
end

local function sortedKeys(t)
    local k = table.GetKeys(t)
    table.sort(k)
    return k
end

---------------------------------------------------------------- tuned values on disk

local function toPlain()
    local out = {}
    for set, wmap in pairs(I.CarryTuned) do
        for class, mmap in pairs(wmap) do
            for mode, e in pairs(mmap) do
                out[set] = out[set] or {}
                out[set][class] = out[set][class] or {}
                out[set][class][mode] = {
                    bone = e.bone, pos = { e.pos.x, e.pos.y, e.pos.z },
                    ang = { e.ang.p, e.ang.y, e.ang.r }, out = { e.out.x, e.out.y, e.out.z },
                }
            end
        end
    end
    return out
end

local loaded = false
local function loadTuned()
    if loaded then return end
    loaded = true
    local text = file.Read(TUNED_FILE, "DATA")
    local data = text and util.JSONToTable(text)
    if not istable(data) then return end
    local n = 0
    for set, wmap in pairs(data) do
        for class, mmap in pairs(wmap) do
            for mode, v in pairs(mmap) do
                if istable(v.pos) and istable(v.ang) and isstring(v.bone) then
                    I.CarryTuned[set] = I.CarryTuned[set] or {}
                    I.CarryTuned[set][class] = I.CarryTuned[set][class] or {}
                    local o = istable(v.out) and Vector(v.out[1], v.out[2], v.out[3]) or Vector(0, 1, 0)
                    I.CarryTuned[set][class][mode] = {
                        bone = v.bone, pos = Vector(v.pos[1], v.pos[2], v.pos[3]),
                        ang = Angle(v.ang[1], v.ang[2], v.ang[3]), out = o:GetNormalized(),
                    }
                    n = n + 1
                end
            end
        end
    end
    print(("[Advanced Inventory System] %d tuned carry offsets loaded from data/%s"):format(n, TUNED_FILE))
end

local function luaLine(set, class, mode, e)
    return ('["%s"] %s %s = { "%s", V(%.2f, %.2f, %.2f), A(%.1f, %.1f, %.1f), V(%.3f, %.3f, %.3f) },'):format(
        set, class, mode, e.bone, e.pos.x, e.pos.y, e.pos.z, e.ang.p, e.ang.y, e.ang.r, e.out.x, e.out.y, e.out.z)
end

---------------------------------------------------------------- viewer

local viewer

local function openViewer(cycle)
    if IsValid(viewer) then viewer:Remove() end
    loadTuned()
    local winfo = weaponInfo()
    local classes = sortedKeys(winfo)
    if #classes == 0 then
        print("[Advanced Inventory System] no weapon with carry modes")
        return
    end
    local models = table.Copy(I.CarryDefaultModels or {})
    local mine = string.lower(LocalPlayer():GetModel() or "")
    if mine ~= "" and not table.HasValue(models, mine) then table.insert(models, 1, mine) end

    -- current choice: your playermodel, your carried long gun and its mode
    local st = { model = mine ~= "" and mine or models[1], class = classes[1], mode = nil,
                 second = nil, anim = "idle_all_01", yaw = 200, fov = 40, auto = false, delay = 1.5 }
    for _, cat in ipairs(I.CARRY_CATS) do
        local id = LocalPlayer():GetNWInt(cat)
        local conf = id > 1 and I.CarryConfig(id)
        if conf and winfo[conf.weaponClass] then
            st.class = conf.weaponClass
            local m = I.CarryMode(LocalPlayer(), cat)
            st.mode = m ~= "stowed" and m or nil
            break
        end
    end
    st.mode = st.mode or modesOf(st.class)[1]

    -- every combination, for the cycle
    local combos = {}
    for _, pm in ipairs(I.CarryDefaultModels or models) do
        for _, class in ipairs(classes) do
            for _, mode in ipairs(modesOf(class)) do combos[#combos + 1] = { pm, class, mode } end
        end
    end
    local index = 1

    local f = vgui.Create("DFrame")
    viewer = f
    f:SetSize(math.min(ScrW() - 40, 1100), math.min(ScrH() - 40, 760))
    f:Center()
    f:SetTitle(cycle and "Carry modes - check every playermodel" or "Carry modes - tune offsets")
    f:MakePopup()

    local side = vgui.Create("DScrollPanel", f)
    side:Dock(RIGHT)
    side:SetWide(380)
    side:DockMargin(6, 0, 0, 0)

    local status = vgui.Create("DLabel", f)
    status:Dock(BOTTOM)
    status:SetTall(22)
    status:SetTextColor(Color(235, 235, 235))

    local view = vgui.Create("DModelPanel", f)
    view:Dock(FILL)
    view:SetFOV(st.fov)
    view:SetCamPos(Vector(110, 0, 45))
    view:SetLookAt(Vector(0, 0, 40))
    view:SetAnimated(true)

    local controls = {}
    local loading = false

    local function slotOf(class)
        return (winfo[class] and winfo[class].cat == "RocketLauncher") and "RocketLauncher" or "PrimaryWep"
    end

    local function list()
        local out = { { cat = slotOf(st.class), class = st.class, model = winfo[st.class].model, mode = st.mode } }
        if st.second then
            local class, mode = st.second[1], st.second[2]
            out[2] = { cat = out[1].cat == "PrimaryWep" and "RocketLauncher" or "PrimaryWep",
                       class = class, model = winfo[class].model, mode = mode }
        end
        return out
    end

    local function currentEntry()
        local ent = view.Entity
        if not IsValid(ent) then return end
        return I.CarryEntry(ent, st.class, st.mode, winfo[st.class].model)
    end

    local function refreshSliders()
        local e = currentEntry()
        if not e then return end
        loading = true
        controls.bone:SetValue(e.bone)
        controls.px:SetValue(e.pos.x) controls.py:SetValue(e.pos.y) controls.pz:SetValue(e.pos.z)
        controls.ap:SetValue(e.ang.p) controls.ay:SetValue(e.ang.y) controls.ar:SetValue(e.ang.r)
        loading = false
    end

    local function setName()
        local _, name = I.CarrySetFor(st.model)
        local n = 0
        for pm, s in pairs(I.CarryAliases) do
            if s == name and table.HasValue(I.CarryDefaultModels or {}, pm) then n = n + 1 end
        end
        return name, n
    end

    local function refreshStatus()
        local name, n = setName()
        local tuned = I.CarryTuned[name] and I.CarryTuned[name][st.class] and I.CarryTuned[name][st.class][st.mode]
        status:SetText(("  %s%s   |   set \"%s\" (%d model%s)   |   %s   |   %s%s"):format(
            cycle and (index .. " / " .. #combos .. "   |   ") or "", st.model, name, n, n == 1 and "" or "s",
            st.class, I.L("carry_" .. st.mode), tuned and "   |   TUNED (not shipped yet)" or ""))
    end

    local function applyModel()
        view:SetModel(st.model)
        local ent = view.Entity
        if IsValid(ent) then
            local seq = ent:LookupSequence(st.anim)
            if seq < 0 then seq = ent:LookupSequence("idle_all_01") end
            ent:ResetSequence(math.max(seq, 0))
            ent:SetCycle(0)
            ent:SetPlaybackRate(1)
        end
    end

    local function refreshAll()
        if not table.HasValue(modesOf(st.class), st.mode) then st.mode = modesOf(st.class)[1] end
        loading = true
        controls.model:SetValue(st.model)
        controls.class:SetValue(st.class)
        controls.mode:Clear()
        for _, m in ipairs(modesOf(st.class)) do controls.mode:AddChoice(I.L("carry_" .. m), m, m == st.mode) end
        controls.second:Clear()
        controls.second:AddChoice("-", nil, st.second == nil)
        for _, class in ipairs(classes) do
            if slotOf(class) ~= slotOf(st.class) then
                for _, m in ipairs(modesOf(class)) do
                    if I.CarryZone[m] ~= I.CarryZone[st.mode] then
                        local sel = st.second and st.second[1] == class and st.second[2] == m
                        controls.second:AddChoice(class .. "  " .. I.L("carry_" .. m), { class, m }, sel)
                    end
                end
            end
        end
        loading = false
        refreshSliders()
        refreshStatus()
    end

    -- writes the slider values as this set's tuned entry
    local function writeTuned()
        if loading then return end
        local e = currentEntry()
        local _, name = I.CarrySetFor(st.model)
        if not e then return end
        I.CarryTuned[name] = I.CarryTuned[name] or {}
        I.CarryTuned[name][st.class] = I.CarryTuned[name][st.class] or {}
        I.CarryTuned[name][st.class][st.mode] = {
            bone = controls.bone:GetValue(),
            pos = Vector(controls.px:GetValue(), controls.py:GetValue(), controls.pz:GetValue()),
            ang = Angle(controls.ap:GetValue(), controls.ay:GetValue(), controls.ar:GetValue()),
            out = e.out,
        }
        refreshStatus()
    end

    function view:LayoutEntity(ent)
        ent:SetAngles(Angle(0, st.yaw, 0))
        self:RunAnimation()
    end

    function view:PostDrawModel(ent)
        I.DrawWeaponList(ent, nil, list())
    end

    -- controls
    local function header(text)
        local l = side:Add("DLabel")
        l:Dock(TOP)
        l:DockMargin(0, 8, 0, 2)
        l:SetText(text)
        l:SetFont("DermaDefaultBold")
        l:SetTextColor(Color(240, 240, 240))
    end
    local function combo(text, choices, current, onSelect)
        header(text)
        local c = side:Add("DComboBox")
        c:Dock(TOP)
        c:SetSortItems(false)
        for _, v in ipairs(choices) do c:AddChoice(v, v, v == current) end
        c.OnSelect = function(_, _, _, data) if not loading then onSelect(data) end end
        return c
    end
    local function slider(text, min, max, decimals)
        local s = side:Add("DNumSlider")
        s:Dock(TOP)
        s:SetText(text)
        s:SetMinMax(min, max)
        s:SetDecimals(decimals)
        s:SetDark(false)
        s.OnValueChanged = writeTuned
        return s
    end

    controls.model = combo("Playermodel", models, st.model, function(v) st.model = v applyModel() refreshAll() end)
    controls.class = combo("Weapon", classes, st.class, function(v) st.class = v st.second = nil refreshAll() end)
    header("Carry mode")
    controls.mode = side:Add("DComboBox")
    controls.mode:Dock(TOP)
    controls.mode.OnSelect = function(_, _, _, data)
        if loading then return end
        st.mode = data
        if st.second and I.CarryZone[st.second[2]] == I.CarryZone[st.mode] then st.second = nil end
        refreshAll()
    end
    header("Second weapon (checks two guns carried together)")
    controls.second = side:Add("DComboBox")
    controls.second:Dock(TOP)
    controls.second:SetSortItems(false)
    controls.second.OnSelect = function(_, _, _, data) if not loading then st.second = data refreshStatus() end end
    combo("Animation", ANIMS, st.anim, function(v) st.anim = v applyModel() end)

    header("View")
    local yaw = slider("Turn", 0, 360, 0)
    yaw.OnValueChanged = function(_, v) st.yaw = v end
    yaw:SetValue(st.yaw)
    local zoom = slider("Zoom (FOV)", 10, 70, 0)
    zoom.OnValueChanged = function(_, v) view:SetFOV(v) end
    zoom:SetValue(st.fov)
    local row = side:Add("DPanel")
    row:Dock(TOP)
    row:SetTall(24)
    row:SetPaintBackground(false)
    for _, b in ipairs({ { "Front", 0 }, { "Back", 180 }, { "Right", 90 }, { "Left", 270 } }) do
        local btn = row:Add("DButton")
        btn:Dock(LEFT)
        btn:SetWide(90)
        btn:SetText(b[1])
        btn.DoClick = function() yaw:SetValue(b[2]) end
    end

    header("Offsets (bone frame) - shared by the whole set")
    controls.bone = side:Add("DComboBox")
    controls.bone:Dock(TOP)
    for _, b in ipairs(BONES) do controls.bone:AddChoice(b) end
    -- another bone: the weapon keeps its place, its values are converted to the new bone
    controls.bone.OnSelect = function(_, _, value)
        if loading then return end
        local ent, e = view.Entity, currentEntry()
        local ob, nb = IsValid(ent) and ent:LookupBone(e.bone), IsValid(ent) and ent:LookupBone(value)
        local om, nm = ob and ent:GetBoneMatrix(ob), nb and ent:GetBoneMatrix(nb)
        if om and nm then
            local wp, wa = LocalToWorld(e.pos, e.ang, om:GetTranslation(), om:GetAngles())
            local lp, la = WorldToLocal(wp, wa, nm:GetTranslation(), nm:GetAngles())
            local wo = LocalToWorld(e.out, angle_zero, vector_origin, om:GetAngles())
            local lo = WorldToLocal(wo, angle_zero, vector_origin, nm:GetAngles())
            loading = true
            controls.px:SetValue(lp.x) controls.py:SetValue(lp.y) controls.pz:SetValue(lp.z)
            controls.ap:SetValue(la.p) controls.ay:SetValue(la.y) controls.ar:SetValue(la.r)
            loading = false
            e = { bone = value, out = lo }
        end
        local _, name = I.CarrySetFor(st.model)
        I.CarryTuned[name] = I.CarryTuned[name] or {}
        I.CarryTuned[name][st.class] = I.CarryTuned[name][st.class] or {}
        I.CarryTuned[name][st.class][st.mode] = {
            bone = value, out = e.out,
            pos = Vector(controls.px:GetValue(), controls.py:GetValue(), controls.pz:GetValue()),
            ang = Angle(controls.ap:GetValue(), controls.ay:GetValue(), controls.ar:GetValue()),
        }
        refreshStatus()
    end
    controls.px = slider("Position X", -40, 40, 2)
    controls.py = slider("Position Y", -40, 40, 2)
    controls.pz = slider("Position Z", -40, 40, 2)
    controls.ap = slider("Pitch", -180, 180, 1)
    controls.ay = slider("Yaw", -180, 180, 1)
    controls.ar = slider("Roll", -180, 180, 1)

    local function button(text, fn)
        local b = side:Add("DButton")
        b:Dock(TOP)
        b:DockMargin(0, 4, 0, 0)
        b:SetText(text)
        b.DoClick = fn
        return b
    end
    button("Print values (console)", function()
        local e = currentEntry()
        local _, name = I.CarrySetFor(st.model)
        if e then print(luaLine(name, st.class, st.mode, e)) end
    end)
    button("Save every tuned value (data/" .. TUNED_FILE .. ")", function()
        file.Write(TUNED_FILE, util.TableToJSON(toPlain(), true))
        print("[Advanced Inventory System] tuned carry offsets saved to data/" .. TUNED_FILE)
        for set, wmap in pairs(I.CarryTuned) do
            for class, mmap in pairs(wmap) do
                for mode, e in pairs(mmap) do print(luaLine(set, class, mode, e)) end
            end
        end
    end)
    button("Reset this one (computed values)", function()
        local _, name = I.CarrySetFor(st.model)
        if I.CarryTuned[name] and I.CarryTuned[name][st.class] then
            I.CarryTuned[name][st.class][st.mode] = nil
        end
        refreshSliders()
        refreshStatus()
    end)

    -- cycle through every combination
    local function go(k)
        index = (k - 1) % #combos + 1
        local c = combos[index]
        local changed = c[1] ~= st.model
        st.model, st.class, st.mode = c[1], c[2], c[3]
        if st.second and (slotOf(st.second[1]) == slotOf(st.class) or I.CarryZone[st.second[2]] == I.CarryZone[st.mode]) then
            st.second = nil
        end
        if changed then applyModel() end
        refreshAll()
    end
    header("Cycle through every playermodel x weapon x mode (" .. #combos .. ")")
    local nav = side:Add("DPanel")
    nav:Dock(TOP)
    nav:SetTall(24)
    nav:SetPaintBackground(false)
    local perModel = math.max(math.floor(#combos / math.max(#(I.CarryDefaultModels or {}), 1)), 1)
    for _, b in ipairs({ { "<< model", function() go(index - perModel) end },
                         { "< previous", function() go(index - 1) end },
                         { "next >", function() go(index + 1) end },
                         { "model >>", function() go(index + perModel) end } }) do
        local btn = nav:Add("DButton")
        btn:Dock(LEFT)
        btn:SetWide(90)
        btn:SetText(b[1])
        btn.DoClick = b[2]
    end
    local auto = side:Add("DCheckBoxLabel")
    auto:Dock(TOP)
    auto:DockMargin(0, 6, 0, 0)
    auto:SetText("Auto")
    auto:SetValue(cycle)
    auto.OnChange = function(_, v) st.auto = v end
    st.auto = cycle
    local delay = slider("Seconds per view", 0.3, 5, 1)
    delay.OnValueChanged = function(_, v) st.delay = v end
    delay:SetValue(st.delay)

    local nextAt = RealTime() + st.delay
    local frameThink = f.Think -- DFrame moves and resizes in its Think
    function f:Think()
        frameThink(self)
        if st.auto and RealTime() >= nextAt then
            nextAt = RealTime() + st.delay
            go(index + 1)
        elseif not st.auto then
            nextAt = RealTime() + st.delay
        end
    end

    if cycle then
        index = 1
        go(1)
    else
        for k, c in ipairs(combos) do
            if c[1] == st.model and c[2] == st.class and c[3] == st.mode then index = k break end
        end
        applyModel()
        refreshAll()
    end
end

concommand.Add("advinv_carry_tune", function() openViewer(false) end, nil,
    "Tune the carry offsets of long guns for a playermodel (dev tool)")
concommand.Add("advinv_carry_cycle", function() openViewer(true) end, nil,
    "Go through every default playermodel, long gun and carry mode (dev tool)")
