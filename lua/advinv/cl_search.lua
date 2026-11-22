--[[
    Searching another player, client side (sh_search.lua): "Search" in the context menu on a
    player, the progress bar, the result.
--]]
local I = AdvInv

properties.Add("advinv_search", {
    MenuLabel = I.L("menu_search"),
    Order = 9997,
    MenuIcon = "icon16/magnifier.png",
    Filter = function(_, ent, ply)
        return IsValid(ent) and ent:IsPlayer() and I.CanSearch(ply, ent) == true
    end,
    Action = function(_, ent)
        I.Act(I.ACT.SEARCH, function() net.WriteUInt(1, 2) net.WriteEntity(ent) end)
    end,
    Receive = function() end,
})

net.Receive("advinv_search_done", function()
    local target = net.ReadEntity()
    local text = net.ReadString()
    chat.AddText(Color(120, 190, 255), "[" .. I.L("menu_search") .. "] ", Color(235, 235, 235), text)
    if IsValid(target) then AdvInv.OpenSearchView(target) end
end)

-- progress: the searcher sees a bar, the target a line of text
hook.Add("HUDPaint", "AdvInv_Search", function()
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local w, h = ScrW(), ScrH()
    local stop = me:GetNWFloat("AdvInvSearchEnd", 0)
    local target = me:GetNWEntity("AdvInvSearchTarget")
    if stop > CurTime() and IsValid(target) then
        local total = math.max(I.SearchTime:GetFloat(), 0.01)
        local f = 1 - math.Clamp((stop - CurTime()) / total, 0, 1)
        local bw, bh = math.min(420, w * 0.4), 22
        local x, y = (w - bw) / 2, h * 0.62
        draw.RoundedBox(4, x, y, bw, bh, Color(0, 0, 0, 180))
        draw.RoundedBox(4, x + 2, y + 2, (bw - 4) * f, bh - 4, Color(90, 160, 230))
        draw.SimpleTextOutlined(I.L("search_progress", target:Nick()), "DermaDefaultBold", w / 2, y - 12,
            color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
    end
    local by = me:GetNWEntity("AdvInvSearchedBy")
    if IsValid(by) then
        draw.SimpleTextOutlined(I.L("search_you", by:Nick()), "DermaLarge", w / 2, h * 0.25,
            Color(255, 220, 120), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, 200))
    end
end)
