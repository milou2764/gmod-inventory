-- Spawn menu categories, crafting switch, ground items despawn.
local done = ASYNC(40)
local I = AdvInv
for _, b in ipairs(player.GetBots()) do b:Kick("reset") end
local out = { categories = {} }
for _, c in ipairs({ "advinv_suitcase", "advinv_barney_helmet", "advinv_top_hat", "advinv_hl2_ar2", "advinv_ammo_ar2",
        "advinv_crate", "advinv_workbench", "advinv_bank", "mrpi_mil_vest_coyote_m" }) do
    local t = scripted_ents.Get(c)
    out.categories[c] = t and (tostring(t.Category) .. " | " .. tostring(t.Model)) or "missing"
end
local tool = weapons.Get("advinv_inventory_tool")
out.tool = tool and tool.Category
out.defaults = { craft = GetConVar("advinv_craft"):GetDefault(), ground = GetConVar("advinv_ground_item_time"):GetDefault(),
    settings = (function()
        local t = {}
        for _, s in ipairs(I.AdminSettings) do if s[1] == "advinv_craft" or s[1] == "advinv_ground_item_time" then t[#t + 1] = s[1] end end
        return table.concat(t, " ")
    end)() }

local function craft(ply, index)
    local saved = net.ReadUInt
    net.ReadUInt = function() return index end
    I.Actor = ply
    local ok, a, b = pcall(I.ActHandlers[I.ACT.CRAFT], ply)
    I.Actor = nil
    net.ReadUInt = saved
    return ok and { tostring(a), tostring(b) } or { "error", tostring(a) }
end

player.CreateNextBot("Crafter")
timer.Simple(1, function()
    local b = player.GetBots()[1]
    b:SetPos(Vector(-2800, -900, -140))
    I.SetDefaults(b)
    GetConVar("advinv_craft"):SetBool(false)
    out.craftOff = craft(b, 1)
    GetConVar("advinv_craft"):SetBool(true)
    out.craftOnNoIngredients = craft(b, 1)
    I.Set(b, "Uniform", { { id = I.GENERIC_ENTITY, c = "item_healthvial" }, { id = I.GENERIC_ENTITY, c = "item_healthvial" } })
    out.craftOn = craft(b, 1)
    GetConVar("advinv_craft"):SetBool(false)

    -- ground items: 3 s for the test
    GetConVar("advinv_ground_item_time"):SetInt(3)
    local pos = b:GetPos() + Vector(60, 0, 20)
    local dropped = I.SpawnItem({ id = I.ClassID.advinv_ammo_pistol, r = 18 }, pos)
    local taken = I.SpawnItem({ id = I.ClassID.advinv_ammo_smg1, r = 45 }, pos + Vector(0, 30, 0))
    local spot = ents.Create("advinv_loot_spawn")
    spot:SetPos(pos + Vector(0, -60, 0))
    spot:Spawn()
    out.tracked = { dropped = I.GroundItems[dropped] ~= nil, taken = I.GroundItems[taken] ~= nil }
    timer.Simple(1, function()
        b.AdvInvUseDelay = 0
        I.Use(b, taken)
    end)
    timer.Simple(4, function()
        out.lootItem = IsValid(spot.AdvInvSpawned) and spot.AdvInvSpawned:GetClass() or "none"
        out.lootTracked = IsValid(spot.AdvInvSpawned) and I.GroundItems[spot.AdvInvSpawned] ~= nil
    end)
    timer.Simple(12, function()
        out.after12s = { droppedGone = not IsValid(dropped), takenInPockets = I.Used(b, "Uniform") > 0,
            lootStillThere = IsValid(spot.AdvInvSpawned) }
        GetConVar("advinv_ground_item_time"):SetInt(600)
        if IsValid(spot) then spot:Remove() end
        done(out)
    end)
end)
