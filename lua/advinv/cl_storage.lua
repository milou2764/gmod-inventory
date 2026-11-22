--[[
    Storage features, client side (sh_storage.lua): context menu on crates (settings for admins,
    lock and code for owners), the code prompt, and the admin menu's Loot spawns tab.
--]]
local I = AdvInv

local function set(ent, key, value)
    net.Start("advinv_storage_set")
    net.WriteEntity(ent)
    net.WriteString(key)
    net.WriteString(tostring(value))
    net.SendToServer()
end

local function isCrate(ent)
    return IsValid(ent) and (ent:GetClass() == "advinv_crate" or ent:GetClass() == "advinv_bank")
end

-- Settings window of a storage (admins).
local function settingsWindow(ent)
    local f = vgui.Create("DFrame")
    f:SetSize(460, 360)
    f:Center()
    f:SetTitle(I.L("storage_settings"))
    f:MakePopup()
    local list = vgui.Create("DScrollPanel", f)
    list:Dock(FILL)
    local function row(label, build)
        local r = list:Add("DPanel")
        r:Dock(TOP)
        r:DockMargin(0, 0, 0, 4)
        r:SetTall(28)
        r.Paint = function() end
        local l = vgui.Create("DLabel", r)
        l:Dock(LEFT)
        l:SetWide(200)
        l:SetText(label)
        build(r)
    end
    local function check(label, key, value, enabled)
        row(label, function(r)
            local b = vgui.Create("DCheckBox", r)
            b:Dock(LEFT)
            b:DockMargin(0, 6, 0, 6)
            b:SetWide(16)
            b:SetChecked(value)
            b:SetEnabled(enabled ~= false)
            b.OnChange = function(_, v) set(ent, key, v and "1" or "0") end
        end)
    end
    local function text(label, key, value, numeric)
        row(label, function(r)
            local e = vgui.Create("DTextEntry", r)
            e:Dock(FILL)
            e:SetValue(value or "")
            e:SetNumeric(numeric or false)
            e.OnEnter = function(self) set(ent, key, self:GetValue()) end
            e.OnLoseFocus = function(self) set(ent, key, self:GetValue()) end
        end)
    end
    local bank = ent:GetClass() == "advinv_bank"
    check(I.L("storage_permanent"), "permanent", ent:GetNWBool("AdvInvPermanent"))
    check(I.L("storage_personal"), "personal", ent:GetNWBool("AdvInvPersonal"), not bank)
    if not bank then text(I.L("storage_sync"), "sync", ent:GetNWString("AdvInvSync", "")) end
    text(I.L("storage_capacity"), "cap", tostring(ent:GetNWInt("AdvInvCap", 0)), true)
    if not bank then
        row(I.L("storage_loot"), function(r)
            local c = vgui.Create("DComboBox", r)
            c:Dock(FILL)
            c:AddChoice("-", "", ent:GetNWString("AdvInvLoot", "") == "")
            for _, name in ipairs(I.LootTableNames()) do c:AddChoice(name, name, ent:GetNWString("AdvInvLoot", "") == name) end
            c.OnSelect = function(_, _, _, data) set(ent, "loot", data or "") end
        end)
        text(I.L("storage_loot_every"), "every", "", true)
    end
    check(I.L("storage_lock"), "locked", ent:GetNWBool("AdvInvLocked"))
    text(I.L("storage_code"), "code", "", true)
    local note = list:Add("DLabel")
    note:Dock(TOP)
    note:DockMargin(0, 6, 0, 0)
    note:SetTall(48)
    note:SetWrap(true)
    note:SetText(I.L("storage_settings_note"))
end

properties.Add("advinv_storage_settings", {
    MenuLabel = I.L("storage_settings"),
    Order = 9996,
    MenuIcon = "icon16/cog.png",
    Filter = function(_, ent, ply) return isCrate(ent) and I.IsAdmin(ply) end,
    Action = function(_, ent) settingsWindow(ent) end,
    Receive = function() end,
})

properties.Add("advinv_storage_lock", {
    MenuLabel = I.L("storage_lock_toggle"),
    Order = 9995,
    MenuIcon = "icon16/lock.png",
    Filter = function(_, ent, ply)
        return isCrate(ent) and ent:GetClass() ~= "advinv_bank" and (I.IsAdmin(ply) or I.IsStorageOwner(ply, ent))
    end,
    Action = function(_, ent) set(ent, "locked", ent:GetNWBool("AdvInvLocked") and "0" or "1") end,
    Receive = function() end,
})

properties.Add("advinv_storage_code", {
    MenuLabel = I.L("storage_set_code"),
    Order = 9994,
    MenuIcon = "icon16/key.png",
    Filter = function(_, ent, ply)
        return isCrate(ent) and ent:GetClass() ~= "advinv_bank" and (I.IsAdmin(ply) or I.IsStorageOwner(ply, ent))
    end,
    Action = function(_, ent)
        Derma_StringRequest(I.L("storage_set_code"), I.L("storage_code_help"), "", function(code) set(ent, "code", code) end)
    end,
    Receive = function() end,
})

net.Receive("advinv_storage_code", function()
    local ent = net.ReadEntity()
    if not IsValid(ent) then return end
    Derma_StringRequest(I.L("storage_locked"), I.L("storage_enter_code"), "", function(code)
        net.Start("advinv_storage_code")
        net.WriteEntity(ent)
        net.WriteString(code)
        net.SendToServer()
    end)
end)

---------------------------------------------------------------- admin menu: loot spawns

local showSpawns = false
local spawns = {}

hook.Add("AdvInv_AdminMenu", "AdvInv_LootSpawns", function(sheet, frame)
    local p = vgui.Create("DPanel", sheet)
    p.Paint = function() end
    local top = vgui.Create("DPanel", p)
    top:Dock(TOP)
    top:SetTall(30)
    top.Paint = function() end
    local tbl = vgui.Create("DComboBox", top)
    tbl:Dock(LEFT)
    tbl:SetWide(160)
    for k, name in ipairs(I.LootTableNames()) do tbl:AddChoice(name, name, k == 1) end
    local every = vgui.Create("DNumberWang", top)
    every:Dock(LEFT)
    every:DockMargin(8, 0, 0, 0)
    every:SetWide(80)
    every:SetMinMax(10, 86400)
    every:SetValue(I.Config.LootSpawnEvery)
    every:SetTooltip(I.L("loot_every_seconds"))
    local function send(act, fn)
        net.Start("advinv_loot_spawn_act")
        net.WriteString(act)
        if fn then fn() end
        net.SendToServer()
    end
    local add = vgui.Create("DButton", top)
    add:Dock(LEFT)
    add:DockMargin(8, 0, 0, 0)
    add:SetWide(200)
    add:SetText(I.L("loot_add_here"))
    add:SetIcon("icon16/add.png")
    add.DoClick = function()
        local _, name = tbl:GetSelected()
        send("add", function() net.WriteString(name or "supplies") net.WriteUInt(math.floor(every:GetValue()), 20) end)
    end
    local list = vgui.Create("DListView", p)
    list:Dock(FILL)
    list:DockMargin(0, 6, 0, 0)
    list:AddColumn(I.L("loot_col_table"))
    list:AddColumn(I.L("loot_col_every"))
    list:AddColumn(I.L("loot_col_pos"))
    p.list = list
    list.OnRowRightClick = function(_, _, line)
        local m = DermaMenu()
        m:AddOption(I.L("loot_goto"), function() send("goto", function() net.WriteEntity(line.ent) end) end):SetIcon("icon16/arrow_right.png")
        m:AddOption(I.L("loot_apply"), function()
            local _, name = tbl:GetSelected()
            send("set", function() net.WriteEntity(line.ent) net.WriteString(name or "supplies") net.WriteUInt(math.floor(every:GetValue()), 20) end)
        end):SetIcon("icon16/pencil.png")
        m:AddOption(I.L("admin_delete"), function() send("remove", function() net.WriteEntity(line.ent) end) end):SetIcon("icon16/cross.png")
        m:Open()
    end
    frame.lootSpawns = p
    sheet:AddSheet(I.L("loot_tab"), p, "icon16/package.png")
    showSpawns = true
    frame.OnRemove = function() showSpawns = false end
    net.Start("advinv_loot_spawns")
    net.SendToServer()
    I.LootSpawnPanel = p
end)

net.Receive("advinv_loot_spawns", function()
    spawns = {}
    for _ = 1, net.ReadUInt(12) do
        spawns[#spawns + 1] = { ent = net.ReadEntity(), pos = net.ReadVector(), table = net.ReadString(), every = net.ReadUInt(20) }
    end
    local p = I.LootSpawnPanel
    if IsValid(p) and IsValid(p.list) then
        p.list:Clear()
        for _, s in ipairs(spawns) do
            local line = p.list:AddLine(s.table, s.every, ("%d %d %d"):format(s.pos.x, s.pos.y, s.pos.z))
            line.ent = s.ent
        end
    end
end)

-- markers where loot spawns are, while the tab is open
hook.Add("PostDrawTranslucentRenderables", "AdvInv_LootSpawns", function()
    if not showSpawns then return end
    for _, s in ipairs(spawns) do
        render.SetColorMaterial()
        render.DrawSphere(s.pos, 6, 12, 12, Color(255, 200, 40, 160))
    end
end)
