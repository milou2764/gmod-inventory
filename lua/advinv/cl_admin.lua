--[[
    Admin menu (sh_admin.lua): console "advinv_admin", or the context menu on a player.
      Players   view a player's inventory (next to yours: move, take, delete), clear it
      Items     give any item (or any weapon by class) to a player
      Settings  the addon's server settings
    The server checks every request: this menu only sends them.
--]]
local I = AdvInv

local function adminAct(sub, fn)
    I.Act(I.ACT.ADMIN, function()
        net.WriteUInt(sub, 4)
        if fn then fn() end
    end)
end

-- Items that can be given: registered items, then whitelisted entities.
local function itemList()
    local out = {}
    for id, class in pairs(AdvInv.IDClass or {}) do
        if id > 1 and not I.IsGeneric(id) then
            local t = scripted_ents.Get(class)
            if t and t.AdvInvAvailable ~= false then -- (compatibility items: only when their addon is here)
                out[#out + 1] = { id = id, name = t.PrintName or class, class = class, cat = t.Category or "" }
            end
        end
    end
    for class, w in pairs(I.PickupWhitelist) do
        out[#out + 1] = { id = I.GENERIC_ENTITY, c = class, name = w.name or class, class = class, cat = "" }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function playerCombo(parent, selected)
    local combo = vgui.Create("DComboBox", parent)
    for _, p in ipairs(player.GetAll()) do combo:AddChoice(p:Nick(), p, p == selected) end
    return combo
end

local frame

local function settingsTab(sheet)
    local panel = vgui.Create("DScrollPanel", sheet)
    panel.Paint = function() end
    local note = panel:Add("DLabel")
    note:Dock(TOP)
    note:SetTall(24)
    note:SetText(I.L("admin_settings_wait"))
    panel.note = note
    function panel:Fill(values)
        self:Clear()
        for _, s in ipairs(I.AdminSettings) do
            local name, kind = s[1], s[2]
            local value = values[name]
            if value ~= nil then
                local row = self:Add("DPanel")
                row:Dock(TOP)
                row:DockMargin(0, 0, 0, 4)
                row:SetTall(32)
                row.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(0, 0, 0, 60)) end
                local label = vgui.Create("DLabel", row)
                label:Dock(LEFT)
                label:DockMargin(8, 0, 0, 0)
                label:SetWide(420)
                label:SetText(I.L("set_" .. name) .. "  (" .. name .. ")")
                label:SetTooltip(name)
                local function send(v)
                    net.Start("advinv_admin_set")
                    net.WriteString(name)
                    net.WriteString(tostring(v))
                    net.SendToServer()
                end
                if kind == "bool" then
                    local box = vgui.Create("DCheckBox", row)
                    box:Dock(LEFT)
                    box:DockMargin(8, 8, 0, 8)
                    box:SetWide(16)
                    box:SetChecked(value == "1")
                    box.OnChange = function(_, v) send(v and "1" or "0") end
                elseif kind == "choice" then
                    local combo = vgui.Create("DComboBox", row)
                    combo:Dock(LEFT)
                    combo:DockMargin(8, 4, 0, 4)
                    combo:SetWide(160)
                    for _, c in ipairs(s[3]) do combo:AddChoice(c, c, c == value) end
                    combo.OnSelect = function(_, _, v) send(v) end
                elseif kind == "text" then
                    local entry = vgui.Create("DTextEntry", row)
                    entry:Dock(FILL)
                    entry:DockMargin(8, 4, 8, 4)
                    entry:SetValue(value)
                    local sent = value
                    local function apply()
                        local v = entry:GetValue()
                        if v ~= sent then sent = v send(v) end
                    end
                    entry.OnEnter = apply
                    entry.OnLoseFocus = function(self) apply() DTextEntry.OnLoseFocus(self) end
                else
                    local slider = vgui.Create("DNumSlider", row)
                    slider:Dock(FILL)
                    slider:DockMargin(8, 0, 8, 0)
                    slider:SetText("")
                    slider:SetMinMax(s[3] or 0, s[4] or 100)
                    slider:SetDecimals(kind == "float" and 2 or 0)
                    slider:SetValue(tonumber(value) or 0)
                    local pending
                    slider.OnValueChanged = function(_, v)
                        pending = v
                        timer.Create("AdvInv_AdminSetting_" .. name, 0.4, 1, function() if pending then send(pending) end end)
                    end
                end
            end
        end
        local note2 = self:Add("DLabel")
        note2:Dock(TOP)
        note2:DockMargin(8, 8, 0, 0)
        note2:SetTall(40)
        note2:SetWrap(true)
        note2:SetText(I.L("admin_settings_note"))
    end
    net.Start("advinv_admin_settings")
    net.SendToServer()
    return panel
end

local function open(target)
    if not I.IsAdmin(LocalPlayer()) then
        notification.AddLegacy(I.L("admin_denied"), NOTIFY_ERROR, 3)
        return
    end
    if IsValid(frame) then frame:Remove() end
    frame = vgui.Create("DFrame")
    frame:SetSize(math.min(ScrW() - 40, 980), math.min(ScrH() - 40, 640))
    frame:Center()
    frame:SetTitle(I.L("admin_title"))
    frame:MakePopup()
    local sheet = vgui.Create("DPropertySheet", frame)
    sheet:Dock(FILL)

    -- players
    local pp = vgui.Create("DPanel", sheet)
    pp.Paint = function() end
    local list = vgui.Create("DListView", pp)
    list:Dock(LEFT)
    list:SetWide(420)
    list:SetMultiSelect(false)
    list:AddColumn(I.L("admin_col_name"))
    list:AddColumn(I.L("admin_col_team")):SetFixedWidth(130)
    list:AddColumn(I.L("load")):SetFixedWidth(60)
    for _, p in ipairs(player.GetAll()) do
        local line = list:AddLine(p:Nick(), team.GetName(p:Team()), p:GetNWInt("AdvInvLoad"))
        line.ply = p
        if p == target then list:SelectItem(line) end
    end
    local side = vgui.Create("DPanel", pp)
    side:Dock(FILL)
    side:DockMargin(8, 0, 0, 0)
    side.Paint = function() end
    local function selected()
        local _, line = list:GetSelectedLine()
        return line and IsValid(line.ply) and line.ply or nil
    end
    local function button(text, icon, fn)
        local b = vgui.Create("DButton", side)
        b:Dock(TOP)
        b:DockMargin(0, 0, 0, 6)
        b:SetTall(32)
        b:SetText(text)
        b:SetIcon(icon)
        b.DoClick = fn
        return b
    end
    button(I.L("admin_view"), "icon16/magnifier.png", function()
        local p = selected()
        if not p then return end
        if p == LocalPlayer() then AdvInv.OpenInventory() else AdvInv.OpenAdminView(p) end
        frame:Remove()
    end)
    button(I.L("admin_clear"), "icon16/bin_empty.png", function()
        local p = selected()
        if not p then return end
        Derma_Query(I.L("admin_clear_confirm", p:Nick()), I.L("admin_title"),
            I.L("admin_yes"), function() adminAct(I.ADMIN.CLEAR, function() net.WriteEntity(p) end) end,
            I.L("admin_no"))
    end)
    list.DoDoubleClick = function(_, _, line)
        if IsValid(line.ply) and line.ply ~= LocalPlayer() then
            AdvInv.OpenAdminView(line.ply)
            frame:Remove()
        end
    end
    sheet:AddSheet(I.L("admin_players"), pp, "icon16/group.png")

    -- items
    local ip = vgui.Create("DPanel", sheet)
    ip.Paint = function() end
    local top = vgui.Create("DPanel", ip)
    top:Dock(TOP)
    top:SetTall(30)
    top.Paint = function() end
    local who = playerCombo(top, target or LocalPlayer())
    who:Dock(LEFT)
    who:SetWide(220)
    local search = vgui.Create("DTextEntry", top)
    search:Dock(LEFT)
    search:DockMargin(8, 0, 0, 0)
    search:SetWide(240)
    search:SetPlaceholderText(I.L("admin_search"))
    local count = vgui.Create("DNumberWang", top)
    count:Dock(LEFT)
    count:DockMargin(8, 0, 0, 0)
    count:SetWide(60)
    count:SetMinMax(1, 100)
    count:SetValue(1)
    local give = vgui.Create("DButton", top)
    give:Dock(LEFT)
    give:DockMargin(8, 0, 0, 0)
    give:SetWide(120)
    give:SetText(I.L("admin_give"))
    give:SetIcon("icon16/add.png")
    local items = vgui.Create("DListView", ip)
    items:Dock(FILL)
    items:DockMargin(0, 6, 0, 0)
    items:SetMultiSelect(false)
    items:AddColumn(I.L("admin_col_name"))
    items:AddColumn(I.L("admin_col_class"))
    items:AddColumn(I.L("admin_col_category"))
    local all = itemList()
    local function fill()
        items:Clear()
        local q = string.lower(search:GetValue() or "")
        for _, it in ipairs(all) do
            if q == "" or string.find(string.lower(it.name .. " " .. it.class), q, 1, true) then
                items:AddLine(it.name, it.class, it.cat).it = it
            end
        end
    end
    search.OnChange = fill
    fill()
    local wrow = vgui.Create("DPanel", ip)
    wrow:Dock(BOTTOM)
    wrow:DockMargin(0, 6, 0, 0)
    wrow:SetTall(30)
    wrow.Paint = function() end
    local wclass = vgui.Create("DTextEntry", wrow)
    wclass:Dock(LEFT)
    wclass:SetWide(300)
    wclass:SetPlaceholderText(I.L("admin_weapon_class"))
    local wgive = vgui.Create("DButton", wrow)
    wgive:Dock(LEFT)
    wgive:DockMargin(8, 0, 0, 0)
    wgive:SetWide(160)
    wgive:SetText(I.L("admin_give_weapon"))
    local function sendGive(id, c)
        local _, p = who:GetSelected()
        if not IsValid(p) then return end
        adminAct(I.ADMIN.GIVE, function()
            net.WriteEntity(p)
            net.WriteUInt(id, I.NET_ID_BITS)
            net.WriteString(c or "")
            net.WriteUInt(math.Clamp(math.floor(count:GetValue()), 1, 100), 8)
        end)
    end
    give.DoClick = function()
        local _, line = items:GetSelectedLine()
        if line and line.it then sendGive(line.it.id, line.it.c) end
    end
    items.DoDoubleClick = function(_, _, line) if line.it then sendGive(line.it.id, line.it.c) end end
    local arow = vgui.Create("DPanel", ip)
    arow:Dock(BOTTOM)
    arow:DockMargin(0, 6, 0, 0)
    arow:SetTall(30)
    arow.Paint = function() end
    local atype = vgui.Create("DTextEntry", arow)
    atype:Dock(LEFT)
    atype:SetWide(300)
    atype:SetPlaceholderText(I.L("admin_ammo_type"))
    local agive = vgui.Create("DButton", arow)
    agive:Dock(LEFT)
    agive:DockMargin(8, 0, 0, 0)
    agive:SetWide(160)
    agive:SetText(I.L("admin_give_ammo"))
    agive.DoClick = function()
        local ammo = string.Trim(atype:GetValue() or "")
        if ammo == "" then return end
        local id, c = I.AmmoBoxFor(ammo)
        if id then sendGive(id, c) end
    end
    wgive.DoClick = function()
        local class = string.Trim(wclass:GetValue() or "")
        if class == "" then return end
        local reg = I.ItemForWeapon(class)
        local grenade = I.GrenadeAmmo(class)
        if grenade and game.GetAmmoID(grenade) ~= -1 then sendGive(I.GENERIC_AMMO, grenade)
        elseif reg then sendGive(reg) else sendGive(I.GENERIC_WEAPON, class) end
    end
    sheet:AddSheet(I.L("admin_items"), ip, "icon16/box.png")

    -- settings
    frame.settings = settingsTab(sheet)
    sheet:AddSheet(I.L("admin_settings"), frame.settings, "icon16/cog.png")
    hook.Run("AdvInv_AdminMenu", sheet, frame) -- other tabs (cl_storage.lua: loot spawns)
end

net.Receive("advinv_admin_settings", function()
    local values = {}
    for _ = 1, net.ReadUInt(8) do
        local name = net.ReadString()
        values[name] = net.ReadString()
    end
    if IsValid(frame) and IsValid(frame.settings) then frame.settings:Fill(values) end
end)

concommand.Add("advinv_admin", function() open() end, nil, "Advanced Inventory System admin menu")

properties.Add("advinv_admin_view", {
    MenuLabel = I.L("admin_property"),
    Order = 9998,
    MenuIcon = "icon16/shield.png",
    Filter = function(_, ent, ply)
        return IsValid(ent) and ent:IsPlayer() and ent ~= ply and I.IsAdmin(ply)
    end,
    Action = function(_, ent) AdvInv.OpenAdminView(ent) end,
    Receive = function() end,
})

I.OpenAdminMenu = open
