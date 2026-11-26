--[[
    Interface de l'inventaire (touche I, voir cl_keybinds.lua).

    À gauche : le personnage, son équipement, ses armes, puis ses contenants (tenue, gilet, sac)
    avec leur charge « utilisée / capacité » et le contenu de celui qui est sélectionné.
    À droite, quand on fouille une caisse ou un véhicule : son contenu.

    On déplace les objets en les glissant : vers un contenant (ou son onglet), vers un
    emplacement d'équipement (équiper), ou hors des panneaux (déposer au sol). Clic droit : menu
    (équiper, ranger dans..., déposer). Double-clic : équiper.
    Le serveur vérifie et fait chaque action ; l'affichage suit ce qu'il renvoie.

    Compatibilité : AdvInv.plyInvPanel, le hook "AdvInv_PanelCreated" (panel, cible) et
    panel.<catégorie>.Model (modèle de l'objet porté dans l'aperçu) restent disponibles.
--]]
local I = AdvInv
local ACT = I.ACT
local S = AdvInv.S

-- (références gardées si le fichier est rechargé : un inventaire ouvert reste fermable)
AdvInv.InvZones = AdvInv.InvZones or {}

local function makeFonts()
    surface.CreateFont("AdvInvSmall", { font = "Roboto", size = math.max(12, S(15)), weight = 700 })
    surface.CreateFont("AdvInvText", { font = "Roboto", size = math.max(13, S(18)), weight = 500 })
    surface.CreateFont("AdvInvTitle", { font = "Roboto", size = math.max(15, S(22)), weight = 800 })
    surface.CreateFont("AdvInvCount", { font = "Roboto", size = math.max(14, S(20)), weight = 900 })
end
makeFonts()

-- Themes (client setting advinv_theme: dark, light, military; Options > Advanced Inventory > Inventory).
local THEMES = {
    dark = {
        bg = Color(0, 0, 0, 200), slot = Color(78, 78, 78, 169), slotFill = Color(20, 22, 26, 140),
        text = Color(235, 235, 235), dim = Color(160, 160, 160), barBg = Color(45, 45, 45, 230),
        ok = Color(80, 150, 80), warn = Color(205, 145, 45), full = Color(190, 55, 55),
        armor = Color(60, 90, 220, 190), ammo = Color(230, 200, 90, 200), selected = Color(255, 255, 255, 30),
        accent = Color(230, 200, 90), badge = Color(0, 0, 0, 215),
    },
    light = {
        bg = Color(228, 230, 234, 235), slot = Color(150, 155, 165, 200), slotFill = Color(250, 251, 252, 210),
        text = Color(25, 28, 34), dim = Color(95, 100, 110), barBg = Color(205, 208, 214, 240),
        ok = Color(60, 150, 70), warn = Color(210, 140, 30), full = Color(200, 55, 55),
        armor = Color(50, 90, 210, 200), ammo = Color(200, 160, 40, 210), selected = Color(0, 0, 0, 25),
        accent = Color(40, 100, 190), badge = Color(255, 255, 255, 230),
    },
    military = {
        bg = Color(24, 28, 18, 215), slot = Color(96, 104, 72, 170), slotFill = Color(36, 42, 28, 160),
        text = Color(226, 222, 196), dim = Color(150, 150, 120), barBg = Color(50, 56, 38, 230),
        ok = Color(110, 150, 70), warn = Color(200, 150, 60), full = Color(180, 60, 45),
        armor = Color(90, 120, 170, 190), ammo = Color(210, 180, 90, 200), selected = Color(255, 255, 220, 30),
        accent = Color(214, 186, 96), badge = Color(16, 18, 10, 220),
    },
}
local themeVar = CreateClientConVar("advinv_theme", "dark", true, false, "Inventory colours: dark, light or military")
local COL = {}
local function applyTheme()
    local th = THEMES[themeVar:GetString()] or THEMES.dark
    for k, v in pairs(th) do COL[k] = v end
end
applyTheme()
cvars.AddChangeCallback("advinv_theme", function()
    applyTheme()
    if AdvInv.CloseInventory then AdvInv.CloseInventory() end
end, "AdvInv_Theme")
I.Themes = THEMES
I.Colors = COL -- the current theme's colours (other client files draw with them)

local function isWeaponCat(cat) return cat and table.HasValue(AdvInv.WeaponCat, cat) end

-- The world behind a window, blurred (drawn first in its Paint).
local blurMat = Material("pp/blurscreen")
local function drawBlur(panel)
    local x, y = panel:LocalToScreen(0, 0)
    local w, h = panel:GetSize()
    render.SetScissorRect(x, y, x + w, y + h, true) -- (painted manually, nothing clips it)
    surface.SetDrawColor(255, 255, 255)
    surface.SetMaterial(blurMat)
    for i = 1, 3 do
        blurMat:SetFloat("$blur", i * 1.6)
        blurMat:Recompute()
        render.UpdateScreenEffectTexture()
        surface.DrawTexturedRect(-x, -y, ScrW(), ScrH())
    end
    render.SetScissorRect(0, 0, 0, 0, false)
end
I.DrawBlur = drawBlur

-- Buttons in the inventory's colours (Derma's default ones are white).
local function themeButton(b)
    b:SetFont("AdvInvSmall")
    b:SetTextColor(COL.text)
    b.Paint = function(self, w, h)
        local hover = self:IsHovered() and not self:GetDisabled()
        draw.RoundedBox(4, 0, 0, w, h, hover and COL.slot or COL.barBg)
        surface.SetDrawColor(COL.accent.r, COL.accent.g, COL.accent.b, hover and 200 or 90)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end
    b.UpdateColours = function(self) self:SetTextStyleColor(COL.text) end
    return b
end
I.ThemeButton = themeButton
local function isEquipable(info) return info.cat and (AdvInv.GearCat[info.cat] or isWeaponCat(info.cat)) end

local function slotID(target, cat)
    if isWeaponCat(cat) then return target:GetNWInt(cat) end
    return target:GetNW2Int(cat)
end

---------------------------------------------------------------- actions demandées au serveur

local function writeCont(cont) net.WriteUInt(I.ContID[cont], 3) end

-- An item by its place in the list and what it is (the server checks it is still that one:
-- sv_containers.lua I.ResolveItemRef)
local function writeRef(src)
    net.WriteUInt(src.index, 8)
    net.WriteUInt(I.ItemCheck(src.item), 32)
end

-- count: how many identical items of the stack (1 by default, the whole stack with Shift held;
-- the server stops when space runs out)
local function moveItem(src, toHolder, toCont, count)
    if src.holder == toHolder and src.cont == toCont then return end
    count = count or (input.IsShiftDown() and src.count) or 1
    I.Act(ACT.MOVE, function()
        net.WriteEntity(src.holder) writeCont(src.cont) writeRef(src)
        net.WriteEntity(toHolder) writeCont(toCont)
        net.WriteUInt(math.Clamp(count or 1, 1, 255), 8)
    end)
end

local function dropItem(src, count)
    count = count or (input.IsShiftDown() and src.count) or 1
    I.Act(ACT.DROP, function()
        net.WriteEntity(src.holder) writeCont(src.cont) writeRef(src)
        net.WriteUInt(math.Clamp(count or 1, 1, 255), 8)
    end)
end

local function equipItem(src)
    I.Act(ACT.EQUIP, function() net.WriteEntity(src.holder) writeCont(src.cont) writeRef(src) end)
end

local function useItem(src)
    I.Act(ACT.USE, function() net.WriteEntity(src.holder) writeCont(src.cont) writeRef(src) end)
end

local function unloadItem(src)
    I.Act(ACT.UNLOAD, function()
        net.WriteBool(false) net.WriteEntity(src.holder) writeCont(src.cont) writeRef(src)
    end)
end

local function unloadSlot(cat)
    I.Act(ACT.UNLOAD, function() net.WriteBool(true) net.WriteUInt(AdvInv.CategoryID[cat], 4) end)
end

-- toHolder nil : déposer au sol
local function unequip(cat, toHolder, toCont)
    I.Act(ACT.UNEQUIP, function()
        net.WriteUInt(AdvInv.CategoryID[cat], 4)
        net.WriteBool(toHolder == nil)
        if toHolder then net.WriteEntity(toHolder) writeCont(toCont) end
    end)
end

---------------------------------------------------------------- dessin

local modelCache = {}
local function itemModel(id, c)
    local key = c and (id .. ":" .. c) or id
    local m = modelCache[key]
    if m then return m end
    local t = I.DefTable(id, c)
    m = {
        model = (t and t.Model) or "models/error.mdl",
        skin = (t and t.skin) or 0,
        bodygroups = (t and t.pocketID) and ("0" .. t.pocketID .. "0000000") or "",
    }
    modelCache[key] = m
    return m
end

local function isWeaponItem(id, c)
    local info = I.Info(id, c)
    return info.isWeapon or isWeaponCat(info.cat)
end

-- Weapon seen from the side, horizontal, fitted to the panel (cl_weapons.lua); other items: spawn icon.
local function itemIcon(parent, id, c)
    local m = itemModel(id, c)
    local class = not I.IsGeneric(id) and AdvInv.IDClass[id] or nil
    if class and I.UsesGearIcon and I.UsesGearIcon(class) then -- a prop of another addon, as worn
        local icon = vgui.Create("AdvInvGearIcon", parent)
        icon:SetItemClass(class)
        return icon
    end
    if isWeaponItem(id, c) then
        local icon = vgui.Create("AdvInvWeaponIcon", parent)
        icon:SetWeaponModel(m.model, m.skin)
        return icon
    end
    local icon = vgui.Create("SpawnIcon", parent)
    icon:SetModel(m.model, m.skin, m.bodygroups)
    return icon
end

local function tooltip(item)
    local info = I.Info(item.id, item.c)
    local lines = { info.name, I.L("tip_mass", info.mass) }
    if info.rarity then lines[#lines + 1] = I.L("tip_rarity", I.L("rarity_" .. info.rarity)) end
    if info.cat and I.SlotLabels[info.cat] then lines[#lines + 1] = I.L("tip_slot", I.SlotLabels[info.cat]) end
    if info.isBox then lines[#lines + 1] = I.L("tip_rounds", item.r or 0, info.boxRounds) end
    if info.isWeapon and (info.clipSize or 0) > 0 then lines[#lines + 1] = I.L("tip_clip", item.r or 0, info.clipSize) end
    if info.isWeapon then
        local ammo = I.WeaponAmmo(item.id, item.c)
        if ammo then lines[#lines + 1] = I.L("tip_ammo", ammo) end
        local conf = I.CarryConfig(item.id, item.c)
        if conf then
            local names = {}
            for _, m in ipairs(conf.modes) do names[#names + 1] = I.L("carry_" .. m) end
            lines[#lines + 1] = I.L("tip_carry", table.concat(names, ", "))
        end
    end
    if info.armor then
        lines[#lines + 1] = I.L("tip_armor", item.a or 0, info.armor)
    end
    if info.isContainer then lines[#lines + 1] = I.L("tip_capacity", info.maxLoad) end
    local use = I.UseOf(item)
    if use and not use.custom then
        if (use.health or 0) > 0 then lines[#lines + 1] = I.L("tip_use_health", use.health) end
        if (use.armor or 0) > 0 then lines[#lines + 1] = I.L("tip_use_armor", use.armor) end
    end
    if I.IsIllegal(item) then lines[#lines + 1] = I.L("tip_illegal") end
    return table.concat(lines, "\n")
end

local function drawLoadBar(x, y, w, h, used, max, label, active)
    draw.RoundedBox(4, x, y, w, h, COL.barBg)
    if max > 0 then
        local f = math.Clamp(used / max, 0, 1)
        local col = used > max and COL.full or (f >= 0.9 and COL.warn or COL.ok)
        draw.RoundedBox(4, x, y, w * f, h, col)
    end
    local textCol = active and COL.text or COL.dim
    draw.SimpleText(label, "AdvInvSmall", x + S(8), y + h / 2, textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(max > 0 and (used .. " / " .. max) or "—", "AdvInvSmall", x + w - S(8), y + h / 2, textCol,
        TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

local function drawSlotFrame(w, h)
    surface.SetDrawColor(COL.slot)
    surface.DrawOutlinedRect(0, 0, w, h, math.max(2, S(4)))
end

-- Jauge verticale à droite d'une case.
local function drawSideGauge(w, h, f, col)
    f = math.Clamp(f or 0, 0, 1)
    local bw = math.max(3, S(6))
    local bh = (h - S(12)) * f
    surface.SetDrawColor(col)
    surface.DrawRect(w - bw - S(5), h - S(6) - bh, bw, bh)
end

---------------------------------------------------------------- menus et glisser-déposer

-- Où ranger : les contenants du joueur, plus la caisse ou le véhicule ouvert.
local function storeTargets()
    local list = {}
    local me = LocalPlayer()
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        if I.HasContainer(me, cont) then list[#list + 1] = { me, cont, I.ContainerNames[cont] } end
    end
    local sp = AdvInv.storagePanel
    if IsValid(sp) and IsValid(sp.holder) then list[#list + 1] = { sp.holder, "Storage", sp.title } end
    local ap = AdvInv.adminPanel -- player seen by an admin, or a body (a searcher can't put things on him)
    if IsValid(ap) and (ap.admin or ap.loot) and IsValid(ap.target) then
        for _, cont in ipairs(I.PLAYER_CONTAINERS) do
            if I.HasContainer(ap.target, cont) then
                list[#list + 1] = { ap.target, cont, I.HolderName(ap.target) .. " : " .. I.ContainerNames[cont] }
            end
        end
    end
    return list
end

-- Name shown for another player, or a body.
function I.HolderName(ent)
    if not IsValid(ent) then return "?" end
    if ent:IsPlayer() then return ent:Nick() end
    local name = ent:GetNWString("AdvInvBodyName", "")
    return name ~= "" and name or I.L("body_title")
end

local function lootSlot(body, cat)
    I.Act(ACT.LOOT, function() net.WriteEntity(body) net.WriteUInt(AdvInv.CategoryID[cat], 4) end)
end

local function adminAct(sub, fn)
    I.Act(ACT.ADMIN, function()
        net.WriteUInt(sub, 4)
        if fn then fn() end
    end)
end

-- Small window: choose an amount between 1 and max, then fn(amount).
local function askAmount(title, max, start, fn)
    local f = vgui.Create("DFrame")
    f:SetSize(360, 110)
    f:Center()
    f:SetTitle(title)
    f:MakePopup()
    local slider = vgui.Create("DNumSlider", f)
    slider:Dock(TOP)
    slider:SetText(I.L("amount"))
    slider:SetMinMax(1, max)
    slider:SetDecimals(0)
    slider:SetValue(start or max)
    local ok = vgui.Create("DButton", f)
    ok:Dock(BOTTOM)
    ok:SetText("OK")
    ok.DoClick = function()
        fn(math.Clamp(math.floor(slider:GetValue()), 1, max))
        f:Remove()
    end
end

local function itemMenu(src)
    local menu = DermaMenu()
    local info = I.Info(src.item.id, src.item.c)
    local n = src.count or 1
    if isEquipable(info) and not (src.holder == LocalPlayer() and src.cont == info.cat and info.cat ~= "Uniform") then
        menu:AddOption(I.L("menu_equip"), function() equipItem(src) end):SetIcon("icon16/user_go.png")
    end
    if src.holder == LocalPlayer() and I.UseOf(src.item) then
        menu:AddOption(I.L("menu_use"), function() useItem(src) end):SetIcon("icon16/heart.png")
    end
    if info.isWeapon and I.CanUnload(src.item.id, src.item.c, src.item.r) then
        menu:AddOption(I.L("menu_unload"), function() unloadItem(src) end):SetIcon("icon16/arrow_undo.png")
    end
    local sub, parent = menu:AddSubMenu(I.L("menu_store_in"))
    parent:SetIcon("icon16/box.png")
    local subAll
    if n > 1 then
        local p
        subAll, p = menu:AddSubMenu(I.L("menu_store_all_in", n))
        p:SetIcon("icon16/box.png")
    end
    local subSome
    if n > 2 then
        local p
        subSome, p = menu:AddSubMenu(I.L("menu_store_some_in"))
        p:SetIcon("icon16/box.png")
    end
    for _, t in ipairs(storeTargets()) do
        if not (t[1] == src.holder and t[2] == src.cont) then
            sub:AddOption(t[3], function() moveItem(src, t[1], t[2]) end)
            if subAll then subAll:AddOption(t[3], function() moveItem(src, t[1], t[2], n) end) end
            if subSome then
                subSome:AddOption(t[3], function()
                    askAmount(I.L("menu_store_some_in"), n, math.ceil(n / 2), function(k) moveItem(src, t[1], t[2], k) end)
                end)
            end
        end
    end
    menu:AddOption(I.L("menu_drop"), function() dropItem(src) end):SetIcon("icon16/arrow_down.png")
    if n > 1 then
        menu:AddOption(I.L("menu_drop_all", n), function() dropItem(src, n) end):SetIcon("icon16/arrow_down.png")
    end
    if n > 2 then
        menu:AddOption(I.L("menu_drop_some"), function()
            askAmount(I.L("menu_drop_some"), n, math.ceil(n / 2), function(k) dropItem(src, k) end)
        end):SetIcon("icon16/arrow_down.png")
    end
    if info.isBox and (src.item.r or 0) > 1 then -- split an ammo box
        menu:AddOption(I.L("menu_split"), function()
            askAmount(I.L("menu_split"), src.item.r - 1, math.floor(src.item.r / 2), function(k)
                I.Act(ACT.SPLIT, function()
                    net.WriteEntity(src.holder) writeCont(src.cont) writeRef(src)
                    net.WriteUInt(k, I.NET_ROUNDS_BITS)
                end)
            end)
        end):SetIcon("icon16/arrow_divide.png")
    end
    if I.IsAdmin(LocalPlayer()) then -- admin: delete (the server checks again)
        local del = function(count)
            adminAct(I.ADMIN.DELETE, function()
                net.WriteEntity(src.holder) writeCont(src.cont) writeRef(src)
                net.WriteUInt(math.Clamp(count, 1, 255), 8)
            end)
        end
        menu:AddSpacer()
        menu:AddOption(I.L("admin_delete"), function() del(1) end):SetIcon("icon16/cross.png")
        if n > 1 then menu:AddOption(I.L("admin_delete_all", n), function() del(n) end):SetIcon("icon16/cross.png") end
    end
    menu:Open()
end

-- Admin, on another player's equipped item: take it, or delete it.
local function adminGearMenu(target, cat)
    local menu = DermaMenu()
    local function send(sub)
        adminAct(sub, function() net.WriteEntity(target) net.WriteUInt(AdvInv.CategoryID[cat], 4) end)
    end
    menu:AddOption(I.L("admin_take"), function() send(I.ADMIN.SLOT_TAKE) end):SetIcon("icon16/arrow_left.png")
    menu:AddOption(I.L("admin_delete"), function() send(I.ADMIN.SLOT_DELETE) end):SetIcon("icon16/cross.png")
    menu:Open()
end

local function gearMenu(cat)
    local menu = DermaMenu()
    local sub, parent = menu:AddSubMenu(I.L("menu_store_in"))
    parent:SetIcon("icon16/box.png")
    for _, t in ipairs(storeTargets()) do
        if not (t[1] == LocalPlayer() and t[2] == cat) then
            sub:AddOption(t[3], function() unequip(cat, t[1], t[2]) end)
        end
    end
    menu:AddOption(I.L("menu_drop"), function() unequip(cat, nil) end):SetIcon("icon16/arrow_down.png")
    if table.HasValue(AdvInv.WeaponCat, cat) then
        local id, c = I.SlotRef(LocalPlayer(), cat)
        local info = I.Info(id, c)
        local wep = info.weaponClass and LocalPlayer():GetWeapon(info.weaponClass)
        if IsValid(wep) and I.CanUnload(id, c, math.max(wep:Clip1(), 0)) then
            menu:AddOption(I.L("menu_unload"), function() unloadSlot(cat) end):SetIcon("icon16/arrow_undo.png")
        end
    end
    I.AddCarryMenu(menu, cat) -- long guns: how they are carried
    menu:Open()
end

-- Panneau qui reçoit les objets glissés : onItem(src) pour un objet rangé, onGear(src) pour un
-- objet équipé. Sans fonction : le dépôt est simplement ignoré (fond des panneaux).
local function acceptDrop(panel, onItem, onGear)
    panel:Receiver("advinv", function(_, panels, dropped)
        if not dropped then return end
        local src = panels[1] and panels[1].advinv
        if not src then return end
        if src.kind == "item" and onItem then onItem(src) end
        if src.kind == "gear" and onGear then onGear(src) end
    end)
end

---------------------------------------------------------------- objets rangés

local function makeTile(holder, cont, index, item, count)
    local tile = itemIcon(nil, item.id, item.c)
    -- long guns take two cells, lying flat
    local wide = isWeaponItem(item.id, item.c) and I.WeaponAspect(itemModel(item.id, item.c).model) > 2.2
    tile:SetSize(wide and S(184) or S(88), S(88))
    tile:SetTooltip(tooltip(item))
    tile.advinv = { kind = "item", holder = holder, cont = cont, index = index, item = item, count = count or 1 }
    tile:Droppable("advinv")
    local info = I.Info(item.id, item.c)
    local illegal = IsValid(holder) and holder:IsPlayer() and holder ~= LocalPlayer() and I.IsIllegal(item)
    local rarity = info.rarity and I.RarityColors[info.rarity]
    tile.PaintOver = function(_, w, h)
        drawSlotFrame(w, h)
        if rarity then
            surface.SetDrawColor(rarity.r, rarity.g, rarity.b, 230)
            surface.DrawOutlinedRect(0, 0, w, h, math.max(2, S(2)))
        end
        if illegal then
            surface.SetDrawColor(220, 40, 40, 255)
            surface.DrawOutlinedRect(0, 0, w, h, math.max(2, S(3)))
        end
        if (count or 1) > 1 then
            -- stack size: white on a dark badge, readable on any item
            local text = "x" .. count
            surface.SetFont("AdvInvCount")
            local tw, th = surface.GetTextSize(text)
            local pad = math.max(2, S(4))
            draw.RoundedBox(4, S(6), S(6), tw + pad * 2, th + pad, COL.badge)
            draw.SimpleText(text, "AdvInvCount", S(6) + pad, S(6) + pad / 2, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
        local gauge = (info.isBox and info.boxRounds > 0) or (info.armor and info.armor > 0)
        draw.SimpleText(info.mass, "AdvInvSmall", w - (gauge and S(16) or S(6)), h - S(3), COL.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
        if info.isBox and info.boxRounds > 0 then
            drawSideGauge(w, h, (item.r or 0) / info.boxRounds, COL.ammo)
        elseif info.armor and info.armor > 0 then
            drawSideGauge(w, h, (item.a or 0) / info.armor, COL.armor)
        end
    end
    tile.DoRightClick = function() itemMenu(tile.advinv) end
    tile.DoDoubleClick = function()
        if isEquipable(info) then
            equipItem(tile.advinv)
        elseif holder == LocalPlayer() and I.UseOf(item) then
            useItem(tile.advinv)
        end
    end
    return tile
end

-- Vue du contenu d'un contenant (grille d'objets, défilante).
local function makeContainerView(parent, x, y, w, h)
    local view = vgui.Create("DPanel", parent)
    view:SetPos(S(x), S(y))
    view:SetSize(S(w), S(h))
    view.items = {}
    view.Paint = function(self, pw, ph)
        draw.RoundedBox(4, 0, 0, pw, ph, COL.slotFill)
        if #self.items == 0 then
            draw.SimpleText(self.emptyText or I.L("empty"), "AdvInvText", pw / 2, ph / 2, COL.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    local scroll = vgui.Create("DScrollPanel", view)
    scroll:Dock(FILL)
    scroll:DockMargin(S(8), S(8), S(8), S(8))
    local layout = vgui.Create("DIconLayout", scroll)
    -- TOP, not FILL: the layout takes the height of its tiles and the scroll canvas that of the layout
    -- (docked FILL, each waited for the other and a list filled late showed no tile)
    layout:Dock(TOP)
    layout:SetSpaceX(S(8))
    layout:SetSpaceY(S(8))

    function view:Show(holder, cont, emptyText)
        self.holder, self.cont, self.emptyText = holder, cont, emptyText
        self:Refresh()
    end

    -- Whatever order the contents and the container arrive in (a body just made: its contents can
    -- come before the client knows it), the view catches up: received lists are new tables.
    function view:Think()
        if (self.nextCheck or 0) > RealTime() then return end
        self.nextCheck = RealTime() + 0.25
        local ok = IsValid(self.holder) and self.cont and I.HasContainer(self.holder, self.cont) or false
        if ok ~= self.lastOk or (ok and I.Get(self.holder, self.cont) ~= self.items) then self:Refresh() end
    end

    function view:Refresh()
        layout:Clear()
        local ok = IsValid(self.holder) and self.cont and I.HasContainer(self.holder, self.cont) or false
        self.lastOk = ok
        self.items = ok and I.Get(self.holder, self.cont) or {}
        -- identical items make one stack (first index, count), in the order they first appear
        local stacks, order = {}, {}
        for k, it in ipairs(self.items) do
            local key = I.StackKey(it)
            local s = stacks[key]
            if s then
                s.count = s.count + 1
            else
                s = { index = k, item = it, count = 1 }
                stacks[key] = s
                order[#order + 1] = s
            end
        end
        for _, s in ipairs(order) do layout:Add(makeTile(self.holder, self.cont, s.index, s.item, s.count)) end
        layout:Layout()
        scroll:InvalidateLayout(true)
    end

    acceptDrop(view,
        function(src) if view.cont then moveItem(src, view.holder, view.cont) end end,
        function(src) if view.cont then unequip(src.cat, view.holder, view.cont) end end)
    return view
end

---------------------------------------------------------------- emplacements d'équipement

local SLOT_LABELS = I.SlotLabels -- in the server's language (sh_lang.lua)

-- Case d'un emplacement d'équipement ; se reconstruit quand l'objet équipé change.
local function makeGearSlot(panel, target, cat, x, y, w, h)
    local slot = vgui.Create("DPanel", panel)
    slot:SetPos(S(x), S(y))
    slot:SetSize(S(w), S(h))
    slot.cat = cat
    slot.Paint = function(self, pw, ph)
        draw.RoundedBox(0, 0, 0, pw, ph, COL.slotFill)
        drawSlotFrame(pw, ph)
        if not IsValid(self.content) then
            -- emplacement vide : son nom
            draw.SimpleText(SLOT_LABELS[cat], "AdvInvSmall", pw / 2, ph / 2, COL.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    slot:SetTooltip(SLOT_LABELS[cat])

    function slot:Rebuild()
        if IsValid(self.content) then self.content:Remove() end
        if IsValid(self.Model) then self.Model:Remove() end
        self.Model = nil
        local id, c = I.SlotRef(target, cat)
        self.id, self.c = id, c -- (generic weapons all share one ID: their class tells them apart)
        panel[cat] = {}
        if self.id <= 1 then return end
        local t = I.DefTable(id, c)
        if not t then return end
        local content = itemIcon(self, id, c)
        content:Dock(FILL)
        local info = I.Info(id, c)
        local item = { id = id, c = c, r = target:GetNWInt(cat .. "Rounds"), a = target:GetNWInt(cat .. "Armor") }
        content:SetTooltip(SLOT_LABELS[cat] .. " : " .. tooltip(item))
        content.advinv = { kind = "gear", cat = cat }
        if target == LocalPlayer() then
            content:Droppable("advinv")
            content.DoRightClick = function() gearMenu(cat) end
        elseif panel.loot then -- a body: take what it wears
            content.DoDoubleClick = function() lootSlot(target, cat) end
            content.DoRightClick = function()
                local menu = DermaMenu()
                menu:AddOption(I.L("body_take"), function() lootSlot(target, cat) end):SetIcon("icon16/arrow_left.png")
                menu:Open()
            end
        elseif panel.admin then
            content.DoRightClick = function() adminGearMenu(target, cat) end
        elseif panel.search and isWeaponCat(cat) and I.SearchTake:GetBool() then
            content.DoRightClick = function()
                local menu = DermaMenu()
                menu:AddOption(I.L("search_take"), function()
                    I.Act(ACT.SEARCH, function()
                        net.WriteUInt(3, 2) net.WriteEntity(target) net.WriteUInt(AdvInv.CategoryID[cat], 4)
                    end)
                end):SetIcon("icon16/arrow_left.png")
                menu:Open()
            end
        end
        -- searching another player: what he wears or holds that is illegal is framed in red too
        local illegal = target ~= LocalPlayer() and target:IsPlayer() and I.IsIllegal(item)
        content.PaintOver = function(_, pw, ph)
            drawSlotFrame(pw, ph)
            if illegal then
                surface.SetDrawColor(220, 40, 40, 255)
                surface.DrawOutlinedRect(0, 0, pw, ph, math.max(2, S(3)))
            end
            if not IsValid(target) then return end -- (gone while the window closes)
            if info.armor and info.armor > 0 then
                drawSideGauge(pw, ph, target:GetNWInt(cat .. "Armor") / info.armor, COL.armor)
            elseif isWeaponCat(cat) then
                local wep = info.weaponClass and target.GetWeapon and target:GetWeapon(info.weaponClass)
                if IsValid(wep) and wep:GetMaxClip1() > 0 then
                    drawSideGauge(pw, ph, wep:Clip1() / wep:GetMaxClip1(), COL.ammo)
                end
            end
            if info.isContainer then
                draw.SimpleText(info.maxLoad, "AdvInvSmall", pw - S(6), ph - S(3), COL.accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
            end
        end
        self.content = content
        panel[cat] = content
        -- objet porté affiché sur le personnage de l'aperçu (pas pour les armes ni la tenue)
        if not isWeaponCat(cat) and not AdvInv.NoMountCat[cat] and IsValid(panel.pmodel) and t.createCSModel
            and not AdvInv.ShownByModel(target, id) then -- (else a bodygroup of the playermodel shows it)
            local model = t:createCSModel(panel.pmodel.Entity)
            if IsValid(model) then
                model:SetNoDraw(true)
                content.Model = model
                self.Model = model
            end
        end
    end

    slot.OnRemove = function(self)
        if IsValid(self.Model) then self.Model:Remove() end
    end

    if target == LocalPlayer() then
        acceptDrop(slot, function(src)
            local info = I.Info(src.item.id, src.item.c)
            if info.cat == cat then equipItem(src) end
        end)
    end
    slot:Rebuild()
    return slot
end

---------------------------------------------------------------- aperçu du personnage

-- Animation de repos selon le type de prise en main de l'arme (table de weapon_base/sh_anim.lua).
local HOLD_IDLE = {
    pistol = ACT_HL2MP_IDLE_PISTOL, smg = ACT_HL2MP_IDLE_SMG1, grenade = ACT_HL2MP_IDLE_GRENADE,
    ar2 = ACT_HL2MP_IDLE_AR2, shotgun = ACT_HL2MP_IDLE_SHOTGUN, rpg = ACT_HL2MP_IDLE_RPG,
    physgun = ACT_HL2MP_IDLE_PHYSGUN, crossbow = ACT_HL2MP_IDLE_CROSSBOW, melee = ACT_HL2MP_IDLE_MELEE,
    slam = ACT_HL2MP_IDLE_SLAM, normal = ACT_HL2MP_IDLE, fist = ACT_HL2MP_IDLE_FIST,
    melee2 = ACT_HL2MP_IDLE_MELEE2, passive = ACT_HL2MP_IDLE_PASSIVE, knife = ACT_HL2MP_IDLE_KNIFE,
    duel = ACT_HL2MP_IDLE_DUEL, camera = ACT_HL2MP_IDLE_CAMERA, magic = ACT_HL2MP_IDLE_MAGIC,
    revolver = ACT_HL2MP_IDLE_REVOLVER,
}
-- De trois-quarts, côté main droite, quand il tient son arme (elle ne pointe pas vers la caméra).
local HELD_YAW_OFFSET = 45

local function heldClassOf(target)
    local wep = target:IsPlayer() and target:GetActiveWeapon()
    return IsValid(wep) and wep:GetClass() or nil
end

local function heldPrimaryWeapon(target)
    if not target:IsPlayer() then return end
    local wep = target:GetActiveWeapon()
    if not IsValid(wep) then return end
    local primary = target:AdvInvEntityTable("PrimaryWep")
    if not primary or not primary.WeaponClass or wep:GetClass() ~= primary.WeaponClass then return end
    return wep
end

-- Le personnage de l'aperçu tient son arme principale s'il l'a en main (pose et modèle de l'arme).
local function updateHeldWeapon(pmodel, target)
    local ent = pmodel.Entity
    if not IsValid(ent) then return end
    if pmodel.advinvBaseSequence == nil then
        pmodel.advinvBaseSequence = ent:GetSequence()
        pmodel.advinvBaseAngles = ent:GetAngles()
    end
    local wep = heldPrimaryWeapon(target)
    local key = IsValid(wep) and (wep:GetClass() .. "|" .. (wep:GetModel() or "")) or false
    if key == pmodel.advinvHeldKey then return end
    pmodel.advinvHeldKey = key
    if IsValid(pmodel.advinvHeldModel) then pmodel.advinvHeldModel:Remove() end
    pmodel.advinvHeldModel = nil
    if not IsValid(wep) then
        ent:ResetSequence(pmodel.advinvBaseSequence)
        ent:SetCycle(0)
        ent:SetAngles(pmodel.advinvBaseAngles)
        return
    end
    local turned = Angle(pmodel.advinvBaseAngles)
    turned:RotateAroundAxis(Vector(0, 0, 1), HELD_YAW_OFFSET)
    ent:SetAngles(turned)
    local seq = ent:SelectWeightedSequence(HOLD_IDLE[string.lower(wep:GetHoldType() or "")] or ACT_HL2MP_IDLE)
    if seq and seq >= 0 then
        ent:ResetSequence(seq)
        ent:SetCycle(0)
    end
    local mdl = wep:GetModel()
    if mdl and mdl ~= "" and (util.IsValidModel(mdl) or file.Exists(mdl, "GAME")) then
        local worldModel = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
        worldModel:SetNoDraw(true)
        AdvInv.MountGearModel(worldModel, ent, nil)
        pmodel.advinvHeldModel = worldModel
    end
end

local function makePreview(panel, target)
    local pmodel = vgui.Create("AdvInvAdjustableModelPanel", panel)
    pmodel:SetModel(target:GetModel())
    pmodel:SetPos(25, 25)
    pmodel:SetSize(325, 470)
    local ent = pmodel.Entity
    ent:SetAngles(Angle(0, 20, 0)) -- facing the camera, a little turned; dragging turns him (cl_vgui.lua)
    local head = ent:LookupBone("ValveBiped.Bip01_Head1")
    local headPos = head and ent:GetBonePosition(head)
    if headPos then ent:SetEyeTarget(headPos + Vector(40, 0, 0)) end -- towards the camera
    for k = 0, target:GetNumBodyGroups() - 1 do ent:SetBodygroup(k, target:GetBodygroup(k)) end
    ent:SetSkin(target:GetSkin())
    -- what the playermodel shows by its bodygroups (its own pack's gear worn or taken off, a choice
    -- made meanwhile) follows the target while the window is open
    local baseThink, nextLook = pmodel.Think, 0
    pmodel.Think = function(self, ...)
        if baseThink then baseThink(self, ...) end
        if CurTime() < nextLook then return end
        nextLook = CurTime() + 0.25
        local e = self.Entity
        if not (IsValid(target) and IsValid(e)) or e:GetModel() ~= target:GetModel() then return end
        for k = 0, target:GetNumBodyGroups() - 1 do
            local v = target:GetBodygroup(k)
            if e:GetBodygroup(k) ~= v then e:SetBodygroup(k, v) end
        end
        if e:GetSkin() ~= target:GetSkin() then e:SetSkin(target:GetSkin()) end
    end
    updateHeldWeapon(pmodel, target)
    -- his upper body, where the gear is, stays in the window whichever side he shows, the weapon in his
    -- hands too; the camera stays put and he turns when dragged (cl_vgui.lua)
    pmodel.advinvAutoFit = true
    pmodel.advinvTurntable = true
    pmodel.advinvFitUpper = true
    pmodel.advinvFitBottom = 0.09 -- the wallet bar covers the bottom of the window
    pmodel.advinvFitMinDist = 24
    pmodel.advinvFitExtra = function(add)
        local held = pmodel.advinvHeldModel
        if not IsValid(held) then return end
        local corners = I.WeaponCorners and I.WeaponCorners(held)
        if corners then
            for _, p in ipairs(corners) do add(p, 0) end
        else -- unknown geometry: a sphere of its size around the right hand
            local hand = ent:LookupBone("ValveBiped.Bip01_R_Hand")
            local m = hand and ent:GetBoneMatrix(hand)
            if m then add(m:GetTranslation(), held:GetModelRadius() or 20) end
        end
    end
    pmodel.advinvOwner = target
    pmodel.advinvWeaponHidden = function(_, info)
        return IsValid(pmodel.advinvHeldModel) and info.weaponClass ~= nil and info.weaponClass == heldClassOf(target)
    end
    local baseThink = pmodel.Think
    function pmodel:Think()
        if baseThink then baseThink(self) end
        if IsValid(target) then updateHeldWeapon(self, target) end
    end
    pmodel.OnRemove = function(self)
        if IsValid(self.Entity) then
            for _, child in pairs(self.Entity:GetChildren()) do child:Remove() end
            self.Entity:Remove() -- (DModelPanel le fait d'habitude : on remplace son OnRemove)
        end
        if IsValid(self.advinvHeldModel) then self.advinvHeldModel:Remove() end
    end
    return pmodel
end

---------------------------------------------------------------- panneau du joueur

local GEAR_LAYOUT = {
    { "NVGs", 375, 25 }, { "Helmet", 500, 25 },
    { "Radio", 375, 150 }, { "Gasmask", 500, 150 },
    { "Rucksack", 375, 275 }, { "Vest", 500, 275 },
    { "Uniform", 375, 400 },
}
local WEAPON_LAYOUT = {
    { "PrimaryWep", 25, 515, 350, 100 },
    { "SecondaryWep", 400, 515, 225, 100 },
    { "RocketLauncher", 25, 630, 600, 100 },
}

local function addCloseReceiver(panel)
    -- lâcher un objet sur le fond d'un panneau ne fait rien (seul l'extérieur dépose au sol)
    acceptDrop(panel)
end

-- mode: nil (the player's own), "admin" (another player seen by an admin) or "search" (a player
-- being searched); the other player's panel is on the right of the screen.
function AdvInv.OpenPlyInvPanel(target, mode)
    target = target or LocalPlayer()
    local admin, search, loot = mode == true or mode == "admin", mode == "search", mode == "loot"
    local other = admin or search or loot
    local panel = vgui.Create("EditablePanel", AdvInv.dropZone)
    panel.target = target
    panel.admin, panel.search, panel.loot = admin, search, loot
    if other then AdvInv.adminPanel = panel else AdvInv.plyInvPanel = panel end
    panel:SetSize(S(650), ScrH())
    if other then panel:SetX(ScrW() - S(650)) end
    panel.Paint = function(self, w, h)
        drawBlur(self)
        draw.RoundedBox(2, 0, 0, w, h, COL.bg)
        if other and IsValid(target) then
            local key = admin and "admin_view_title" or search and "search_view_title" or "body_of"
            draw.SimpleText(I.L(key, I.HolderName(target)), "AdvInvText", S(25), S(14), COL.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end
    addCloseReceiver(panel)

    panel.pmodel = makePreview(panel, target)

    panel.slots = {}
    for _, conf in ipairs(GEAR_LAYOUT) do
        panel.slots[conf[1]] = makeGearSlot(panel, target, conf[1], conf[2], conf[3], 100, 100)
    end
    for _, conf in ipairs(WEAPON_LAYOUT) do
        panel.slots[conf[1]] = makeGearSlot(panel, target, conf[1], conf[2], conf[3], conf[4], conf[5])
    end

    -- charge totale (et ralentissement si l'option est activée)
    local loadInfo = vgui.Create("DPanel", panel)
    loadInfo:SetPos(S(500), S(400))
    loadInfo:SetSize(S(125), S(100))
    loadInfo.Paint = function(_, w, h)
        draw.RoundedBox(0, 0, 0, w, h, COL.slotFill)
        draw.SimpleText(I.L("load"), "AdvInvSmall", w / 2, h * 0.25, COL.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if not IsValid(target) then return end
        draw.SimpleText(target:GetNWInt("AdvInvLoad"), "AdvInvTitle", w / 2, h * 0.52, COL.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if I.LoadSlowdownEnabled() then
            local f = I.SpeedFactor(target)
            draw.SimpleText(I.L("speed", math.Round(f * 100)), "AdvInvSmall", w / 2, h * 0.8,
                f < 1 and COL.warn or COL.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    -- crafting (sh_craft.lua)
    if target == LocalPlayer() and not other and #I.Recipes > 0 and I.CraftingEnabled() then
        local craft = vgui.Create("DButton", panel)
        craft:SetPos(S(25), S(418))
        craft:SetSize(S(150), S(36))
        craft:SetText(I.L("craft_title"))
        craft:SetIcon("icon16/wrench.png")
        themeButton(craft)
        craft.DoClick = function() I.OpenCrafting() end
    end

    -- DarkRP: wallet and "Drop money"
    if target == LocalPlayer() and not other and target.getDarkRPVar then
        local money = vgui.Create("DPanel", panel)
        money:SetPos(S(25), S(462))
        money:SetSize(S(330), S(38))
        money.Paint = function(_, w, h)
            draw.RoundedBox(4, 0, 0, w, h, COL.slotFill)
            local wallet = target:getDarkRPVar("money") or 0
            local text = DarkRP and DarkRP.formatMoney and DarkRP.formatMoney(wallet) or tostring(wallet)
            draw.SimpleText(I.L("money_wallet", text), "AdvInvSmall", S(10), h / 2, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local drop = vgui.Create("DButton", money)
        drop:Dock(RIGHT)
        drop:DockMargin(0, S(4), S(4), S(4))
        drop:SetWide(S(130))
        drop:SetText(I.L("money_drop"))
        themeButton(drop)
        drop.DoClick = function()
            Derma_StringRequest(I.L("money_drop"), I.L("money_amount"), "", function(v)
                local amount = math.floor(tonumber(v) or 0)
                if amount <= 0 then return end
                net.Start("advinv_drop_money")
                net.WriteUInt(math.min(amount, 4294967295), 32)
                net.SendToServer()
            end)
        end
    end

    -- onglets des contenants + contenu de celui qui est sélectionné
    panel.view = makeContainerView(panel, 25, 810, 600, 245)
    panel.tabs = {}
    local function select(cont)
        panel.selected = cont
        local name = I.ContainerNames[cont]
        panel.view:Show(target, cont, I.HasContainer(target, cont) and I.L("cont_empty", name) or I.L("cont_missing", string.lower(name)))
    end
    panel.Select = select
    for k, cont in ipairs(I.PLAYER_CONTAINERS) do
        local tab = vgui.Create("DButton", panel)
        tab:SetText("")
        tab:SetPos(S(25 + (k - 1) * 205), S(745))
        tab:SetSize(S(190), S(52))
        tab.Paint = function(self, w, h)
            local has = I.HasContainer(target, cont)
            if panel.selected == cont then draw.RoundedBox(4, 0, 0, w, h, COL.selected) end
            local used = I.ItemsLoad(I.Get(target, cont))
            drawLoadBar(S(4), S(10), w - S(8), h - S(20), used, has and I.MaxLoad(target, cont) or 0,
                I.ContainerNames[cont], has)
            if self:IsHovered() then
                surface.SetDrawColor(255, 255, 255, 60)
                surface.DrawOutlinedRect(0, 0, w, h, 1)
            end
        end
        tab.DoClick = function() select(cont) end
        acceptDrop(tab,
            function(src) moveItem(src, target, cont) end,
            function(src) unequip(src.cat, target, cont) end)
        panel.tabs[cont] = tab
    end

    -- contenant affiché au départ : le sac, sinon le gilet, sinon la tenue
    if I.HasContainer(target, "Rucksack") then select("Rucksack")
    elseif I.HasContainer(target, "Vest") then select("Vest")
    else select("Uniform") end

    -- équipement changé : cases, aperçu et contenants mis à jour
    local nextCheck = 0
    panel.Think = function()
        if CurTime() < nextCheck then return end
        nextCheck = CurTime() + 0.15
        local changed = false
        for cat, slot in pairs(panel.slots) do
            local id, c
            if IsValid(slot) then id, c = I.SlotRef(target, cat) end
            if IsValid(slot) and (id ~= slot.id or c ~= slot.c) then
                slot:Rebuild()
                changed = true
            end
        end
        if changed then
            if not I.HasContainer(target, panel.selected) then select("Uniform") else panel.view:Refresh() end
            hook.Run("AdvInv_PanelCreated", panel, target)
        end
    end

    -- Permet aux autres addons d'ajuster le panneau (modèles des objets portés, etc.).
    hook.Run("AdvInv_PanelCreated", panel, target)
    return panel
end

---------------------------------------------------------------- caisse / véhicule

local function storageTitle(ent)
    if ent.StorageTitle then return ent:StorageTitle() end
    if ent:GetClass() == "advinv_crate" then return ent.PrintName or I.L("storage_crate") end
    if ent.IsSimfphyscar or ent:GetClass() == "gmod_sent_vehicle_fphysics_base" then return I.L("storage_vehicle") end
    return ent.PrintName or I.ContainerNames.Storage
end

function AdvInv.OpenStorageContents(ent)
    if IsValid(AdvInv.storagePanel) then AdvInv.storagePanel:Remove() end
    if IsValid(AdvInv.adminPanel) then AdvInv.adminPanel:Remove() end -- same side of the screen
    local panel = vgui.Create("EditablePanel", AdvInv.dropZone)
    AdvInv.storagePanel = panel
    panel.holder = ent
    panel.title = storageTitle(ent)
    panel:SetSize(S(650), ScrH())
    panel:SetX(ScrW() - S(650))
    addCloseReceiver(panel)
    panel.Paint = function(_, w, h)
        draw.RoundedBox(2, 0, 0, w, h, COL.bg)
        draw.SimpleText(panel.title, "AdvInvTitle", S(25), S(40), COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if IsValid(ent) then
            drawLoadBar(S(25), S(70), S(600), S(32), I.ItemsLoad(I.Get(ent, "Storage")), I.MaxLoad(ent, "Storage"), I.L("storage_load"), true)
        end
    end
    panel.view = makeContainerView(panel, 25, 120, 600, 935)
    panel.view:Show(ent, "Storage", I.L("empty"))
    I.Act(ACT.OPEN, function() net.WriteEntity(ent) end)
    panel.OnRemove = function()
        if IsValid(ent) then I.Act(ACT.CLOSE, function() net.WriteEntity(ent) end) end
    end
    panel.Think = function()
        if not IsValid(ent) or LocalPlayer():EyePos():DistToSqr(ent:NearestPoint(LocalPlayer():EyePos())) > (I.Config.UseDistance + 50) ^ 2 then
            panel:Remove()
        end
    end
    return panel
end

---------------------------------------------------------------- ouverture et fermeture

-- Fond plein écran : il porte les panneaux et reçoit les objets lâchés à côté (déposer au sol).
function AdvInv.createDropZone()
    if IsValid(AdvInv.dropZone) then return AdvInv.dropZone end
    local zone = vgui.Create("EditablePanel")
    AdvInv.dropZone = zone
    AdvInv.InvZones[zone] = true
    zone:SetSize(ScrW(), ScrH())
    zone:MakePopup()
    zone:SetKeyboardInputEnabled(false)
    zone.Paint = function() end
    acceptDrop(zone,
        function(src) dropItem(src) end,
        function(src) unequip(src.cat, nil) end)
    return zone
end

function AdvInv.CloseInventory()
    for zone in pairs(AdvInv.InvZones) do
        if IsValid(zone) then zone:Remove() end
    end
    AdvInv.InvZones = {}
    AdvInv.dropZone, AdvInv.plyInvPanel, AdvInv.storagePanel, AdvInv.adminPanel = nil, nil, nil, nil
end

function AdvInv.OpenInventory()
    AdvInv.createDropZone()
    if not IsValid(AdvInv.plyInvPanel) then AdvInv.OpenPlyInvPanel(LocalPlayer()) end
end

-- Admin: a player's inventory on the right, the admin's own on the left (sv_admin.lua checks).
function AdvInv.OpenAdminView(target)
    if not (IsValid(target) and target:IsPlayer()) or target == LocalPlayer() then return end
    AdvInv.OpenInventory()
    if IsValid(AdvInv.storagePanel) then AdvInv.storagePanel:Remove() end
    if IsValid(AdvInv.adminPanel) then AdvInv.adminPanel:Remove() end
    I.Act(ACT.ADMIN, function() net.WriteUInt(I.ADMIN.VIEW, 4) net.WriteEntity(target) end)
    local panel = AdvInv.OpenPlyInvPanel(target, "admin")
    local remove = panel.OnRemove
    panel.OnRemove = function(self)
        if remove then remove(self) end
        I.Act(ACT.ADMIN, function() net.WriteUInt(I.ADMIN.UNVIEW, 4) end)
    end
    local think = panel.Think
    panel.Think = function(self)
        if not IsValid(target) then self:Remove() return end
        if think then think(self) end
    end
    return panel
end

-- A dead player's body (sv_death.lua): what he wears and carries on the right.
function AdvInv.OpenBodyView(body)
    if not I.IsBody(body) then return end
    if hook.Run("AdvInv_CanOpen", LocalPlayer()) == false then return end
    AdvInv.OpenInventory()
    if IsValid(AdvInv.storagePanel) then AdvInv.storagePanel:Remove() end
    if IsValid(AdvInv.adminPanel) then AdvInv.adminPanel:Remove() end
    I.Act(ACT.OPEN, function() net.WriteEntity(body) end)
    local panel = AdvInv.OpenPlyInvPanel(body, "loot")
    local remove = panel.OnRemove
    panel.OnRemove = function(self)
        if remove then remove(self) end
        if IsValid(body) then I.Act(ACT.CLOSE, function() net.WriteEntity(body) end) end
    end
    local think = panel.Think
    panel.Think = function(self)
        if not IsValid(body) or LocalPlayer():EyePos():DistToSqr(body:NearestPoint(LocalPlayer():EyePos())) > (I.Config.UseDistance + 50) ^ 2 then
            self:Remove()
            return
        end
        if think then think(self) end
    end
    return panel
end

-- Search done (sv_search.lua): the searched player's inventory on the right.
function AdvInv.OpenSearchView(target)
    if not (IsValid(target) and target:IsPlayer()) then return end
    AdvInv.OpenInventory()
    if IsValid(AdvInv.storagePanel) then AdvInv.storagePanel:Remove() end
    if IsValid(AdvInv.adminPanel) then AdvInv.adminPanel:Remove() end
    local panel = AdvInv.OpenPlyInvPanel(target, "search")
    local remove = panel.OnRemove
    panel.OnRemove = function(self)
        if remove then remove(self) end
        I.Act(ACT.SEARCH, function() net.WriteUInt(2, 2) end)
    end
    local think = panel.Think
    panel.Think = function(self)
        if not IsValid(target) or LocalPlayer():GetPos():DistToSqr(target:GetPos()) > (I.Config.SearchRange + 60) ^ 2 then
            self:Remove()
            return
        end
        if think then think(self) end
    end
    return panel
end

-- The server stopped showing us a holder (out of reach or sight, locked, a search over): its window
-- closes (it would keep what it saw last, and the actions would be refused).
net.Receive("advinv_view_end", function()
    local holder = net.ReadEntity()
    -- (each panel on its own: either may be nil, and ipairs would stop at the first nil)
    local panels = { AdvInv.storagePanel, AdvInv.adminPanel }
    for i = 1, 2 do
        local p = panels[i]
        if IsValid(p) and not p.admin and (p.holder == holder or p.target == holder) then p:Remove() end
    end
end)

-- Fouiller une caisse ou un véhicule : son contenu à droite, l'inventaire du joueur à gauche.
function AdvInv.OpenStorage(ent)
    if hook.Run("AdvInv_CanOpen", LocalPlayer()) == false then return end
    AdvInv.OpenInventory()
    AdvInv.OpenStorageContents(ent)
end

-- Inventaire ouvert : l'affichage du mode de jeu (DarkRP...) est masqué, sauf la discussion.
hook.Add("HUDShouldDraw", "AdvInv_HideHUD", function(name)
    if IsValid(AdvInv.dropZone) and name ~= "CHudChat" and name ~= "CHudGMod" and name ~= "CHudWeaponSelection" then
        if string.StartWith(name, "DarkRP") or string.StartWith(name, "CHud") then return false end
    end
end)

-- Contenu reçu du serveur : les vues concernées se mettent à jour.
hook.Add("AdvInv_Changed", "AdvInv_Panels", function(holder, cont, idx)
    local panels = { AdvInv.plyInvPanel, AdvInv.storagePanel, AdvInv.adminPanel }
    for i = 1, 3 do
        local p = panels[i]
        local v = IsValid(p) and p.view
        if IsValid(v) and v.cont == cont and (v.holder == holder
            or (idx and IsValid(v.holder) and v.holder:EntIndex() == idx)) then
            v:Refresh()
        end
    end
end)

hook.Add("OnScreenSizeChanged", "AdvInv_Fonts", function()
    makeFonts()
    AdvInv.CloseInventory()
end)

local keyReleased = true
local chatOpen = false
hook.Add("StartChat", "AdvInv_Key", function() chatOpen = true end)
hook.Add("FinishChat", "AdvInv_Key", function() chatOpen = false end)
hook.Add("Think", "AdvInv_Key", function()
    local key = AdvInv.InventoryKey()
    -- typing (chat, a text box) doesn't open or close the inventory
    if input.IsKeyDown(key) and not chatOpen and not IsValid(vgui.GetKeyboardFocus()) then
        if not keyReleased then return end
        keyReleased = false
        if IsValid(AdvInv.dropZone) then
            AdvInv.CloseInventory()
        elseif not vgui.CursorVisible() and not gui.IsGameUIVisible()
            and hook.Run("AdvInv_CanOpen", LocalPlayer()) ~= false then
            AdvInv.OpenInventory()
        end
    else
        keyReleased = true
    end
end)
