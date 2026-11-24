-- Frames of the Workshop's animated icon (dev tool, not shipped): the local player, in third person,
-- puts on and switches gear, one state a frame; rendered into a target (no HUD, hints or counters;
-- the user's settings are not changed). Frames: data/devkit_cl/gif/<GIF_NAME>_<nn>.png, then
-- tools/shots/make_gif.py. Needs the playermodel and the items of GIF_STATES on the client.
--   python devkit/gmodclient.py start --gamemode darkrp --map rp_southside_day
--   python devkit/gmodclient.py scene advanced-inventory/tools/shots/gear_gif.lua
--@serveur
local I, C = AdvInv, AdvInv.ClassID
GIF_MODEL = GIF_MODEL or "models/leygun/rfarmy/soilder_rf_07.mdl"
GIF_SPOT = GIF_SPOT or { Vector(-2052, 9708, 129), 180 }
-- each state: the items worn (slot = class); a state lists everything worn, the rest comes off
GIF_STATES = GIF_STATES or {
    {},
    { Helmet = "advinv_milou_rfarmy_6b47" },
    { Helmet = "advinv_milou_rfarmy_6b47", Vest = "advinv_milou_rfarmy_plate_carrier" },
    { Helmet = "advinv_milou_rfarmy_6b47", Vest = "advinv_milou_rfarmy_plate_carrier", Rucksack = "advinv_milou_pmc_backpack" },
    { Helmet = "advinv_milou_pmc_black_helmet", Vest = "advinv_milou_rfarmy_plate_carrier", Rucksack = "advinv_milou_pmc_backpack" },
    { Helmet = "advinv_milou_pmc_black_helmet", Vest = "advinv_milou_rfarmy_plate_carrier", Rucksack = "advinv_milou_pmc_backpack", Gasmask = "advinv_milou_pmc_gasmask_black" },
    { Helmet = "advinv_milou_pmc_black_helmet", Vest = "advinv_milou_rfarmy_plate_carrier", Rucksack = "advinv_milou_pmc_backpack", Gasmask = "advinv_milou_pmc_gasmask_black", NVGs = "advinv_milou_pmc_nvg" },
}
local SLOTS = { "Helmet", "Vest", "Rucksack", "Gasmask", "NVGs", "Radio" }
local ply = Entity(1)
ply:SetModel(GIF_MODEL)
ply:SetPos(GIF_SPOT[1])
ply:SetEyeAngles(Angle(0, GIF_SPOT[2], 0))
if ply:HasWeapon("keys") then ply:SelectWeapon("keys") end
for _, s in ipairs(SLOTS) do if ply:GetNW2Int(s) > 1 then I.TakeOff(ply, s) end end
concommand.Add("advinv_gif_state", function(p, _, args)
    if p ~= ply then return end
    local st = GIF_STATES[tonumber(args[1]) or 0]
    if not st then return end
    for _, s in ipairs(SLOTS) do
        local want = st[s] and C[st[s]]
        if ply:GetNW2Int(s) > 1 and ply:GetNW2Int(s) ~= want then I.TakeOff(ply, s) end
    end
    for _, s in ipairs(SLOTS) do
        local c = st[s]
        if c and ply:GetNW2Int(s) ~= C[c] then
            local t = scripted_ents.Get(c)
            I.Equip(ply, { id = C[c], a = t and t.Armor or 0 }, {})
        end
    end
    I.ApplyModelGear(ply)
end)
return { states = #GIF_STATES }
--@client
local done = ASYNC(120)
local NAME = GIF_NAME or "gear"
local N = GIF_COUNT or 7
local p = LocalPlayer()
local W, H = ScrW(), ScrH()
local rt = GetRenderTargetEx("advinv_gif", W, H, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE, bit.bor(2, 256), 0, IMAGE_FORMAT_RGB888)
file.CreateDir("devkit_cl/gif")
hook.Add("ShouldDrawLocalPlayer", "AdvInv_Gif", function() return true end)
local function view()
    local o, yaw = p:GetPos(), GIF_SPOT_YAW or 180   -- the spot's yaw (the body's own drifts)
    local d = GIF_CAM or { -30, 88, 64, 54, 50 }  -- side angle, distance, height, aim height, fov
    local pos = o + Angle(0, yaw + d[1], 0):Forward() * d[2] + Vector(0, 0, d[3])
    return pos, (o + Vector(0, 0, d[4]) - pos):Angle(), d[5]
end
local function capture(name, cb)
    local taken = false
    hook.Add("PostRender", "AdvInv_Gif", function()
        if taken then return end
        taken = true
        hook.Remove("PostRender", "AdvInv_Gif")
        local pos, ang, fov = view()
        render.PushRenderTarget(rt)
        render.Clear(0, 0, 0, 255, true, true)
        render.RenderView({ origin = pos, angles = ang, fov = fov, x = 0, y = 0, w = W, h = H, drawhud = false,
            drawviewmodel = false, znear = 3 })
        local data = render.Capture({ format = "png", x = 0, y = 0, w = W, h = H })
        render.PopRenderTarget()
        file.Write("devkit_cl/gif/" .. name .. ".png", data or "")
        cb(data and #data or 0)
    end)
end
local sizes = {}
local function step(k)
    if k > N then
        hook.Remove("ShouldDrawLocalPlayer", "AdvInv_Gif")
        return done({ frames = N, bytes = sizes })
    end
    RunConsoleCommand("advinv_gif_state", tostring(k))
    timer.Simple(GIF_WAIT or 1.5, function()
        capture(string.format("%s_%02d", NAME, k), function(n) sizes[#sizes + 1] = n step(k + 1) end)
    end)
end
timer.Simple(3, function() step(1) end)
