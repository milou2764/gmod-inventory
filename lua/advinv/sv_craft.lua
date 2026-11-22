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

local function take(ply, spec, count)
    for _, cont in ipairs(I.PLAYER_CONTAINERS) do
        local items = I.Get(ply, cont)
        for k = #items, 1, -1 do
            if count <= 0 then return end
            if I.ItemMatches(items[k], spec) then
                table.remove(items, k)
                count = count - 1
                I.MarkDirty(ply, cont)
            end
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
    if hook.Run("AdvInv_CanCraft", ply, r) == false then return false end
    ply.AdvInvCrafting = true
    ply:SetNWFloat("AdvInvCraftEnd", CurTime() + (r.time or 1))
    timer.Simple(r.time or 1, function()
        if not IsValid(ply) then return end
        ply.AdvInvCrafting = nil
        ply:SetNWFloat("AdvInvCraftEnd", 0)
        if not ply:Alive() then return end
        local ok2, why2 = I.CanCraft(ply, r, I.NearBench(ply))
        if not ok2 then I.Tell(ply, why2) return end
        for _, spec in ipairs(r.needs or {}) do take(ply, spec, spec.count or 1) end
        for _ = 1, (r.gives and r.gives.count or 1) do
            local item = r.gives and resultItem(r.gives)
            if item and not I.Store(ply, item) then I.SpawnItem(item, I.DropPos(ply)) end
        end
        hook.Run("AdvInv_Crafted", ply, r)
    end)
    return true
end
