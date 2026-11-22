--[[
    Dead players' bodies, client side (sv_death.lua): their gear is drawn on them like on a living
    player (each slot as the server says: taken items disappear), their carried weapons too, and
    the Use key opens them.
--]]
local I = AdvInv

local bodies = {}

net.Receive("advinv_open_body", function()
    local body = net.ReadEntity()
    if IsValid(body) and AdvInv.OpenBodyView then AdvInv.OpenBodyView(body) end
end)

local function cleanup(body)
    local gear = AdvInv.mountedGear and AdvInv.mountedGear[body]
    for _, m in pairs(gear or {}) do
        if IsValid(m) then m:Remove() end
    end
    if AdvInv.mountedGear then AdvInv.mountedGear[body] = nil end
    bodies[body] = nil
end

-- New bodies, and gear that changed on them (the NW2 callbacks of cl_gear.lua do most of it;
-- this catches bodies that arrived with their values already set).
timer.Create("AdvInv_BodiesGear", 0.5, 0, function()
    for _, ent in ipairs(ents.FindByClass("prop_ragdoll")) do
        if I.IsBody(ent) then
            if not bodies[ent] then
                bodies[ent] = true
                ent:CallOnRemove("AdvInv_BodyGear", cleanup)
            end
            for cat in pairs(AdvInv.GearCat) do
                local id = ent:GetNW2Int(cat, 1)
                local have = AdvInv.mountedGear and AdvInv.mountedGear[ent] and AdvInv.mountedGear[ent][cat]
                if id > 1 and not IsValid(have) then
                    AdvInv.UpdateCSGear(ent, ent, cat, id, true)
                elseif id <= 1 and IsValid(have) then
                    have:Remove()
                    AdvInv.mountedGear[ent][cat] = nil
                end
            end
        end
    end
    for body in pairs(bodies) do
        if not IsValid(body) then bodies[body] = nil end
    end
end)

-- weapons carried on bodies (cl_weapons.lua / cl_carry.lua place them like on players)
hook.Add("PostDrawOpaqueRenderables", "AdvInv_BodiesWeapons", function(_, skybox)
    if skybox then return end
    local eye = EyePos()
    for body in pairs(bodies) do
        if IsValid(body) and not body:IsDormant() and body:GetPos():DistToSqr(eye) < 3000 * 3000 then
            I.DrawWeaponList(body, body, I.EquippedWeaponList(body))
        end
    end
end)
