--[[
    Crafting window (sh_craft.lua): the "Crafting" button of the inventory, or a workbench.
--]]
local I = AdvInv

local frame

function I.OpenCrafting()
    if IsValid(frame) then frame:Remove() end
    frame = vgui.Create("DFrame")
    frame:SetSize(math.min(ScrW() - 40, 620), math.min(ScrH() - 40, 460))
    frame:Center()
    frame:SetTitle(I.L("craft_title"))
    frame:MakePopup()
    local list = vgui.Create("DScrollPanel", frame)
    list:Dock(FILL)
    local function fill()
        list:Clear()
        local bench = I.NearBench(LocalPlayer())
        for k, r in ipairs(I.Recipes) do
            local row = list:Add("DPanel")
            row:Dock(TOP)
            row:DockMargin(0, 0, 0, 6)
            row:SetTall(64)
            local ok, why = I.CanCraft(LocalPlayer(), r, bench)
            local needs = {}
            for _, spec in ipairs(r.needs or {}) do
                needs[#needs + 1] = ("%s %d/%d"):format(I.SpecName(spec), I.CountCarried(LocalPlayer(), spec), spec.count or 1)
            end
            row.Paint = function(_, w, h)
                draw.RoundedBox(4, 0, 0, w, h, Color(0, 0, 0, 90))
                draw.SimpleText(I.RecipeName(r) .. (r.bench and ("  (" .. I.L("craft_bench") .. ")") or ""), "DermaDefaultBold", 10, 8, color_white)
                draw.SimpleText(table.concat(needs, ", "), "DermaDefault", 10, 28, Color(200, 200, 200))
                if not ok and why then draw.SimpleText(why, "DermaDefault", 10, 44, Color(230, 120, 100)) end
            end
            local b = vgui.Create("DButton", row)
            b:Dock(RIGHT)
            b:DockMargin(0, 14, 10, 14)
            b:SetWide(110)
            b:SetText(I.L("craft_do"))
            b:SetEnabled(ok)
            b.DoClick = function()
                I.Act(I.ACT.CRAFT, function() net.WriteUInt(k, 8) end)
                -- (this window only: one reopened meanwhile has its own list, this one's is gone)
                timer.Simple((r.time or 1) + 0.4, function() if IsValid(list) then fill() end end)
            end
        end
    end
    fill()
end

-- progress while crafting
hook.Add("HUDPaint", "AdvInv_Craft", function()
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local stop = me:GetNWFloat("AdvInvCraftEnd", 0)
    if stop <= CurTime() then return end
    local w, h = ScrW(), ScrH()
    draw.SimpleTextOutlined(I.L("craft_working"), "DermaDefaultBold", w / 2, h * 0.62, color_white,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
end)

net.Receive("advinv_open_crafting", function() if I.CraftingEnabled() then I.OpenCrafting() end end)
