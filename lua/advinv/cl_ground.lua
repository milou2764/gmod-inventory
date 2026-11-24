--[[
    Looking at an item on the ground (within reach): its name, how many there are, its rounds,
    its mass, and the key that takes it. Works for registered items, weapons lying around and whitelisted
    entities (sh_generic.lua).
--]]
local I = AdvInv
local REACH = 130 -- same reach as the pickup key (sv_extra.lua)
-- Client option (Options > Advanced Inventory > More): no text box at all, for immersion.
local hoverVar = CreateClientConVar("advinv_hover_text", "1", true, false,
    "Text box when looking at an item on the ground or a body (0: none)", 0, 1)

-- The item an entity on the ground would become (the server decides; this is only to show it).
local function groundItem(ent)
    local class = ent:GetClass()
    local id = AdvInv.ClassID[class]
    if id and id > 1 and not I.IsGeneric(id) then return id, nil end
    if ent:IsWeapon() then
        if IsValid(ent:GetOwner()) or not GetConVar("advinv_pickup_weapons"):GetBool() or I.WeaponBlacklist[class] then return end
        local grenade = I.GrenadeAmmo(class)
        if grenade and game.GetAmmoID(grenade) ~= -1 then return I.GENERIC_AMMO, grenade end
        local reg = I.ItemForWeapon(class)
        if reg then return reg, nil end
        if GetConVar("advinv_pickup_any_weapon"):GetBool() and I.DefTable(I.GENERIC_WEAPON, class) then return I.GENERIC_WEAPON, class end
        return
    end
    if not GetConVar("advinv_pickup_entities"):GetBool() then return end
    local conv = I.PickupConvert[class]
    if conv and AdvInv.ClassID[conv] then return AdvInv.ClassID[conv], nil end
    if I.PickupWhitelist[class] then return I.GENERIC_ENTITY, class end
end

-- The label next to the crosshair: a title and lines, in the inventory's fonts and colours.
local function drawLabel(title, lines)
    local S, COL = I.S, I.Colors or {}
    local titleFont, lineFont = "AdvInvText", "AdvInvSmall"
    local x, y = ScrW() / 2 + S(28), ScrH() / 2 + S(12)
    local pad, gap = S(10), S(4)
    surface.SetFont(titleFont)
    local w, th = surface.GetTextSize(title)
    surface.SetFont(lineFont)
    local lh = select(2, surface.GetTextSize("Ag"))
    for _, l in ipairs(lines) do w = math.max(w, (surface.GetTextSize(l))) end
    local h = pad * 2 + th + #lines * (lh + gap)
    draw.RoundedBox(4, x, y, w + pad * 2, h, ColorAlpha(COL.badge or Color(20, 22, 26), 210))
    surface.SetDrawColor(COL.accent or Color(230, 200, 90))
    surface.DrawRect(x, y, S(3), h)
    draw.SimpleText(title, titleFont, x + pad, y + pad, COL.text or Color(235, 235, 235))
    for k, l in ipairs(lines) do
        draw.SimpleText(l, lineFont, x + pad, y + pad + th + gap + (k - 1) * (lh + gap), COL.dim or Color(190, 195, 205))
    end
end

hook.Add("HUDPaint", "AdvInv_GroundItem", function()
    local me = LocalPlayer()
    if not (IsValid(me) and me:Alive()) or IsValid(AdvInv.dropZone) or not hoverVar:GetBool() then return end
    local tr = me:GetEyeTrace()
    local ent = tr.Entity
    if not IsValid(ent) or tr.HitPos:DistToSqr(me:EyePos()) > REACH * REACH then return end
    if I.IsBody(ent) then -- a dead player's body
        local key = input.LookupBinding("+use") or "E"
        local title = I.L("body_of", I.HolderName(ent))
        local line = I.L("ground_search_body", string.upper(key))
        drawLabel(title, { line })
        return
    end
    local id, c = groundItem(ent)
    if not id then return end
    local info = I.Info(id, c)
    if not info.class then return end
    local count = math.max(ent:GetNWInt("AdvInvCount", 1), 1)
    local title = info.name .. (count > 1 and ("  x" .. count) or "")
    local lines = {}
    local rounds = ent:GetNWInt("AdvInvRounds", -1)
    if rounds < 0 then rounds = ent.Rounds or (ent.Clip1 and ent:Clip1()) or 0 end
    if (info.isBox or info.isWeapon) and rounds > 0 then lines[#lines + 1] = I.L("ground_rounds", rounds) end
    lines[#lines + 1] = I.L("tip_mass", info.mass * count)
    local key = input.LookupBinding("+use") or "E"
    lines[#lines + 1] = I.L("ground_take", string.upper(key))
    drawLabel(title, lines)
end)
