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
                -- (a clientside model loses its parent when the body leaves the view range)
                if id > 1 and (not IsValid(have) or have:GetParent() ~= ent) then
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
hook.Add("PostDrawOpaqueRenderables", "AdvInv_BodiesWeapons", function(depth, skybox)
    if depth or skybox or not (AdvInv.Config and AdvInv.Config.ShowMountedWeapons) then return end
    local eye, dir = EyePos(), EyeVector()
    for body in pairs(bodies) do
        local pos = IsValid(body) and body:GetPos()
        if pos and not body:IsDormant() and pos:DistToSqr(eye) < 3000 * 3000 and (pos - eye):Dot(dir) > -80 then
            I.DrawWeaponList(body, body, I.EquippedWeaponList(body))
        end
    end
end)
