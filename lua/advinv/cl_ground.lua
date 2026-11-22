--[[
    Looking at an item on the ground (within reach): its name, how many there are, its rounds,
    its mass, and the key that takes it. Works for registered items, weapons lying around and whitelisted
    entities (sh_generic.lua).
--]]
local I = AdvInv
local REACH = 120
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
        local x, y = ScrW() / 2 + 28, ScrH() / 2 + 12
        surface.SetFont("DermaDefaultBold")
        local w = math.max(surface.GetTextSize(title), (surface.GetTextSize(line)))
        draw.RoundedBox(4, x, y, w + 16, 40, Color(20, 22, 26, 200))
        draw.SimpleText(title, "DermaDefaultBold", x + 8, y + 4, Color(235, 235, 235))
        draw.SimpleText(line, "DermaDefault", x + 8, y + 20, Color(190, 195, 205))
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
    local x, y = ScrW() / 2 + 28, ScrH() / 2 + 12
    surface.SetFont("DermaDefaultBold")
    local w = surface.GetTextSize(title)
    surface.SetFont("DermaDefault")
    for _, l in ipairs(lines) do w = math.max(w, (surface.GetTextSize(l))) end
    local h = 20 + #lines * 16
    draw.RoundedBox(4, x, y, w + 16, h, Color(20, 22, 26, 200))
    draw.SimpleText(title, "DermaDefaultBold", x + 8, y + 4, Color(235, 235, 235))
    for k, l in ipairs(lines) do
        draw.SimpleText(l, "DermaDefault", x + 8, y + 4 + k * 16, Color(190, 195, 205))
    end
end)
