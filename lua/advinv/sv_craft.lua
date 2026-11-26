--[[
    Crafting, server side (rules in sh_craft.lua). ACT.CRAFT: recipe index. The ingredients are
    checked, then taken after the recipe's time if the player is still alive (and still at the
    workbench if it needs one); the result goes into the containers, or on the ground.
--]]
local I = AdvInv
local handlers = I.ActHandlers

local function resultItem(spec)
    if spec.item then
        local id = AdvInv.ClassID[spec.item]
        return id and I.NewItem(id)
    elseif spec.entity then
        return I.NewItem(I.GENERIC_ENTITY, spec.entity)
    elseif spec.weapon then
        local it = I.ItemForWeaponClass(spec.weapon, 0)
        return it and I.NewItem(it.id, it.c)
    elseif spec.ammo then
        local id, c = I.AmmoBoxFor(spec.ammo)
        return id and I.NewItem(id, c)
    end
end

-- The items a recipe takes: each one for a single ingredient (two ingredients that both match an
-- item don't both count it: else less was consumed than the recipe asks), never a job's item (a
-- loadout copy turned into an ordinary result). -> the picks, or nil and the missing ingredient.
local function plan(ply, r)
    local used, picks = {}, {}
    local order = {}
    for _, spec in ipairs(r.needs or {}) do order[#order + 1] = spec end
    -- (an item named exactly first: a general ingredient, any box of an ammunition, must not take
    -- the very box a named one needs)
    table.sort(order, function(a, b) return (a.ammo and 1 or 0) < (b.ammo and 1 or 0) end)
    for _, spec in ipairs(order) do
        local need = spec.count or 1
        for _, cont in ipairs(I.PLAYER_CONTAINERS) do
            local items = I.Get(ply, cont)
            for k = #items, 1, -1 do
                if need <= 0 then break end
                local it = items[k]
                if not used[it] and not it.j and I.ItemMatches(it, spec) then
                    used[it] = true
                    picks[#picks + 1] = { cont = cont, item = it }
                    need = need - 1
                end
            end
        end
        if need > 0 then return nil, spec end
    end
    return picks
end

local function take(ply, picks)
    for _, p in ipairs(picks) do
        local items = I.Get(ply, p.cont)
        local k = table.KeyFromValue(items, p.item)
        if k then
            table.remove(items, k)
            I.MarkDirty(ply, p.cont)
        end
    end
end

handlers[I.ACT.CRAFT] = function(ply)
    local r = I.Recipes[net.ReadUInt(8)]
    if not (r and ply:Alive()) then return end
    if not I.CraftingEnabled() then return false, I.L("craft_disabled") end
    if ply.AdvInvCrafting then return false, I.L("craft_busy") end
    local ok, why = I.CanCraft(ply, r, I.NearBench(ply))
    if not ok then return false, why end
    local picks, missing = plan(ply, r)
    if not picks then return false, I.L("craft_missing", I.SpecName(missing)) end
    if hook.Run("AdvInv_CanCraft", ply, r) == false then return false end
    ply.AdvInvCrafting = true
    ply:SetNWFloat("AdvInvCraftEnd", CurTime() + (r.time or 1))
    timer.Simple(r.time or 1, function()
        if not IsValid(ply) then return end
        ply.AdvInvCrafting = nil
        ply:SetNWFloat("AdvInvCraftEnd", 0)
        if not ply:Alive() then return end
        if not I.CraftingEnabled() then I.Tell(ply, I.L("craft_disabled")) return end
        if hook.Run("AdvInv_CanCraft", ply, r) == false then return end
        local ok2, why2 = I.CanCraft(ply, r, I.NearBench(ply))
        if not ok2 then I.Tell(ply, why2) return end
        local picks2, missing2 = plan(ply, r)
        if not picks2 then I.Tell(ply, I.L("craft_missing", I.SpecName(missing2))) return end
        take(ply, picks2)
        for _ = 1, (r.gives and r.gives.count or 1) do
            local item = r.gives and resultItem(r.gives)
            if item and not I.Store(ply, item) then I.SpawnItem(item, I.DropPos(ply)) end
        end
        hook.Run("AdvInv_Crafted", ply, r)
    end)
    return true
end
