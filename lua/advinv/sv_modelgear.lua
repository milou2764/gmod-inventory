-- The bodygroups of AdvInv.ModelGear (sh_modelgear.lua) on players and bodies: locked gear, the gear
-- worn, the wearer's own choices back when nothing asks for a bodygroup any more.
-- ent.AdvInvOwnBodygroups = { model = model, set = { [index] = value set here },
--     [index] = the player's own choice } (only the bodygroups asked for)
local I = AdvInv

function I.ApplyModelGear(ent)
    if not IsValid(ent) then return end
    local model = string.lower(ent:GetModel() or "")
    local own = ent.AdvInvOwnBodygroups
    if own and own.model ~= model then own = nil end -- another playermodel: these values aren't its own
    own = own or { model = model, set = {} }
    own.set = own.set or {}
    -- a value changed since by someone else (the player's menu, a job) is the player's choice now
    for k, v in pairs(own.set) do
        local now = ent:GetBodygroup(k)
        if now ~= v then
            own[k] = now
            own.set[k] = nil
        end
    end
    local want = I.ModelGearBodygroups(ent, own) or {}
    for k, v in pairs(own) do
        if isnumber(k) and want[k] == nil then -- nothing asks for it: the player's choice again
            if ent:GetBodygroup(k) ~= v then ent:SetBodygroup(k, v) end
            own[k] = nil
            own.set[k] = nil
        end
    end
    for k, v in pairs(want) do
        if own[k] == nil then own[k] = ent:GetBodygroup(k) end
        if ent:GetBodygroup(k) ~= v then ent:SetBodygroup(k, v) end
        own.set[k] = v
    end
    ent.AdvInvOwnBodygroups = next(own.set) and own or nil
end

-- every change of a worn item, whatever made it (equip, take off, loot from a body, death, admin...)
local pending = {}
hook.Add("EntityNetworkedVarChanged", "AdvInv_ModelGear", function(ent, name)
    if not I.GearCat[name] or pending[ent] then return end
    if not (ent:IsPlayer() or I.IsBody(ent)) or not I.ModelGearOf(ent) then return end
    pending[ent] = true
    timer.Simple(0, function() -- the hook runs before the value changes
        pending[ent] = nil
        I.ApplyModelGear(ent)
    end)
end)

-- A player who takes a playermodel with headgear, a vest or a backpack in its mesh (job, model chooser,
-- bodygroup) while wearing one of ours: impossible, ours comes off. It goes back to the inventory, or
-- down at the feet without room, or with what it holds (a vest or a backpack keeps its contents).
function I.GearBuiltInCheck(ply)
    if not (IsValid(ply) and ply:Alive()) then return end
    for cat, msg in pairs(I.GearBuiltInMessages) do
        if I.SlotID(ply, cat) > 1 and I.HasBuiltInGear(ply, cat) then
            local item, contents = I.TakeOff(ply, cat)
            -- a job's items inside, and what his drop rules keep (DisallowDrop...), stay with him (in
            -- his other containers), never on the ground; the rest leaves as ordinary items
            for k = #(contents or {}), 1, -1 do
                if contents[k].j or not I.MayLeaveItem(ply, contents[k]) then
                    local it = table.remove(contents, k)
                    if not I.Store(ply, it) then I.ForceStore(ply, it) end
                end
            end
            local empty = not contents or #contents == 0
            if item and not (empty and I.Store(ply, item)) then
                item.j = nil
                I.SpawnItem(item, I.DropPos(ply), contents)
            end
            I.Tell(ply, I.L(msg))
        end
    end
end

-- every second: gear built into a playermodel taken meanwhile, and the locked bodygroups (a player
-- who picked his cap or his helmet in a menu gets "none" back: only the item shows it)
timer.Create("AdvInv_GearBuiltIn", 1, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        I.GearBuiltInCheck(ply)
        if I.ModelGearOf(ply) then I.ApplyModelGear(ply) end
    end
end)

-- A spawn chooses the bodygroups anew (playermodel, job): what was changed goes back first, then the
-- gear worn asks again once the playermodel is set.
hook.Add("PlayerSpawn", "AdvInv_ModelGear", function(ply)
    local own = ply.AdvInvOwnBodygroups
    if own and own.model == string.lower(ply:GetModel() or "") then
        for k, v in pairs(own) do
            if isnumber(k) then ply:SetBodygroup(k, v) end
        end
    end
    ply.AdvInvOwnBodygroups = nil
    timer.Simple(0.2, function() I.ApplyModelGear(ply) end)
end)
