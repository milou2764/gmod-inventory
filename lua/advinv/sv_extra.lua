--[[
    Small things, server side: chat command, pickup key, Wiremod outputs of crates.
      !inventory, /inventory, !inv, /inv   open the inventory
      advinv_pickup (pickup key, cl_extra.lua) / inventory tool right click: take the item looked at
      Wiremod (if installed): crates have outputs Load, Capacity, Items, Viewers
--]]
local I = AdvInv

util.AddNetworkString("advinv_open_inventory")
util.AddNetworkString("advinv_pickup")

local COMMANDS = { ["!inventory"] = true, ["/inventory"] = true, ["!inv"] = true, ["/inv"] = true }
hook.Add("PlayerSay", "AdvInv_Chat", function(ply, text)
    if COMMANDS[string.lower(string.Trim(text))] then
        net.Start("advinv_open_inventory")
        net.Send(ply)
        return ""
    end
end)

-- Takes the item ply looks at, within reach (same as the Use key on it).
function I.PickupLooked(ply)
    if not (IsValid(ply) and ply:Alive()) then return end
    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    if not IsValid(ent) or tr.HitPos:DistToSqr(ply:EyePos()) > 130 * 130 then return end
    if not I.ItemFromEntity(ent) then return end
    I.Use(ply, ent)
end

net.Receive("advinv_pickup", function(_, ply) I.PickupLooked(ply) end)

if I.WeaponBlacklist then I.WeaponBlacklist.advinv_inventory_tool = true end

-- Wiremod outputs of crates (updated every second).
timer.Create("AdvInv_Wire", 1, 0, function()
    if not WireLib then return end
    for _, ent in ipairs(ents.FindByClass("advinv_crate")) do
        if not ent.Outputs then
            ent.Outputs = WireLib.CreateOutputs(ent, { "Load", "Capacity", "Items", "Viewers" })
        end
        if not I.IsKeyed(ent) or not ent.AdvInvPersonal then
            local items = I.Get(ent, "Storage")
            WireLib.TriggerOutput(ent, "Load", I.ItemsLoad(items))
            WireLib.TriggerOutput(ent, "Capacity", I.MaxLoad(ent, "Storage"))
            WireLib.TriggerOutput(ent, "Items", #items)
        end
        WireLib.TriggerOutput(ent, "Viewers", table.Count(ent.AdvInvViewers or {}))
    end
end)
