-- Every installed extension pack (AdvInv.ModelGearPacks, addons/advinv-ext-*): its items registered by
-- name, available where its models are, on the ground with their hull's physics, worn by a citizen
-- (a fitted copy) and saved by class; on the pack's own playermodels (when they are playermodels) an
-- item is shown by its bodygroup and that bodygroup is locked off without it. Needs a bot. Asynchronous
-- (the items dropped on the ground settle): run with ASYNC.
local I, C = AdvInv, AdvInv.ClassID
local done = ASYNC(30)
local CIT = "models/player/group01/male_07.mdl"
local b = player.GetBots()[1]
if not IsValid(b) then return done({ skipped = "no bot" }) end
if not b:Alive() then b:Spawn() end
local out, problems, spawned = {}, {}, {}
local function bad(s) problems[#problems + 1] = s end
local tr = util.TraceLine({ start = b:GetPos() + Vector(100, 0, 80), endpos = b:GetPos() + Vector(100, 0, -200) })
local n = 0

for _, pack in ipairs(I.ModelGearPacks or {}) do
    local here = util.IsValidModel(pack.model)
    local r = { items = #pack.items, here = here, registered = 0, physics = 0, worn = 0, own = 0, locked = 0 }
    out[pack.key] = r
    for _, it in ipairs(pack.items) do
        local cls = it.class
        local t = scripted_ents.Get(cls)
        if (C[cls] or 0) >= I.DYNAMIC_ID_START and I.IDClass[C[cls]] == cls and t then
            r.registered = r.registered + 1
        else
            bad(cls .. ": not registered")
        end
        if t and t.AdvInvAvailable ~= here then bad(cls .. ": available " .. tostring(t.AdvInvAvailable)) end
        if here and t then
            -- on the ground
            n = n + 1
            local ent = ents.Create(cls)
            ent:SetPos(tr.HitPos + Vector((n % 10) * 45 - 200, math.floor(n / 10) * 45, 40))
            ent:Spawn()
            if IsValid(ent:GetPhysicsObject()) then r.physics = r.physics + 1 else bad(cls .. ": no physics") end
            spawned[#spawned + 1] = { ent = ent, z = ent:GetPos().z, cls = cls }
            -- worn by a citizen: a copy; saved by class
            I.SetDefaults(b)
            b:SetModel(CIT)
            local slot = it.slot
            if I.Equip(b, { id = C[cls], a = it.armor or 0 }, {}) == true and b:GetNW2Int(slot) == C[cls]
                and not I.ShownByModel(b, b:GetNW2Int(slot)) then
                r.worn = r.worn + 1
            else
                bad(cls .. ": not worn by a citizen (" .. slot .. ")")
            end
            I.Save(b, "advinv_test_mgp")
            local rec = I.Record("advinv_test_mgp")
            if not (rec and rec.s[slot] and rec.s[slot][1] == cls) then bad(cls .. ": not saved by class") end
            I.DeleteRecord("advinv_test_mgp")
            I.TakeOff(b, slot)
            -- on the pack's first own model (registered or not: a pack's own Lua isn't run here): shown by
            -- its bodygroup, locked without it
            local own = pack.model
            local bgs = it.on and own and it.on[string.lower(own)]
            b:SetModel(own)
            if bgs and (b:LookupSequence("idle_all_01") < 0 -- NPC models (the Vietnam soldiers): never worn
                or (I.GearBuiltIn[string.lower(own)] or {})[slot]) then -- gear of that slot built in (PMC vest)
                bgs = nil
                b:SetModel(CIT)
            end
            if bgs then
                local k, v = next(bgs)
                b:SetBodygroup(k, v) -- the player picks it from a menu
                I.ApplyModelGear(b)
                if b:GetBodygroup(k) ~= v then r.locked = r.locked + 1 else bad(cls .. ": bodygroup " .. k .. " not locked") end
                if I.Equip(b, { id = C[cls], a = it.armor or 0 }, {}) == true then
                    I.ApplyModelGear(b)
                    if b:GetBodygroup(k) == v and I.ShownByModel(b, b:GetNW2Int(slot)) then
                        r.own = r.own + 1
                    else
                        bad(cls .. ": not shown by its bodygroup on " .. own)
                    end
                    I.TakeOff(b, slot)
                else
                    bad(cls .. ": refused on " .. own)
                end
                b:SetModel(CIT)
            end
        end
    end
end
I.SetDefaults(b)

timer.Simple(5, function()
    local fell, resting = 0, 0
    for _, s in ipairs(spawned) do
        if IsValid(s.ent) then
            local p = s.ent:GetPhysicsObject()
            if s.z - s.ent:GetPos().z > 5 then fell = fell + 1 else bad(s.cls .. ": didn't fall") end
            if IsValid(p) and (p:IsAsleep() or p:GetVelocity():Length() < 1) then resting = resting + 1 else bad(s.cls .. ": still moving") end
            s.ent:Remove()
        end
    end
    out.spawned, out.fell, out.resting = #spawned, fell, resting
    out.problems = problems                                     -- {} (none)
    done(out)
end)
