-- Frames of the WW1 Workshop screenshot (dev tool, not shipped): five French soldiers (bots) in a
-- trench whose gear changes from frame to frame (the WW1 French extension's items, shown by the
-- soldiers' own bodygroups), long guns WW1GIF_WEAPON (a weapon class: the Lebel) slung or held.
-- Rendered into a target (no HUD, hints or counters). Frames: data/devkit_cl/gif/ww1_<nn>.png, then
-- tools/shots/make_gif.py. Needs the WW1 French playermodels (Workshop 3433822040 + 1722627125), the
-- extension advinv-ext-ww1-french and a map (rp_ww1_siegfriedtrenches_b02, Workshop 3444363793);
-- the rifle: WW1GIF_WEAPON = "tfa_verdun_lebel_rifle_1886" ([TFA] Lebel Rifle 1886, Workshop
-- 2027550654, and the TFA base, subscribed in Steam: its Lua runs, so never mounted by hand).
--   python devkit/gmodclient.py start --gamemode darkrp --map rp_ww1_siegfriedtrenches_b02 --maxplayers 8
--   python devkit/gmodclient.py scene advanced-inventory/tools/shots/ww1_gif.lua   (twice: bots first)
--@serveur
local I, C = AdvInv, AdvInv.ClassID
WW1GIF_SPOT = WW1GIF_SPOT or { Vector(-9200, 13600, -3767), 315 }  -- squad centre (ground), facing (a sunlit spot: render.ComputeLighting)
-- a group photo: the five standing side by side, posing (the view is wide enough for all of them
-- standing: no reason for anyone to crouch), the ends a little forward; on the flat strip of the
-- spot (the ground rises past 40 units to its left). Sideways (right), depth toward the camera.
-- Image left to right: 3, 4, 2, 5, 1.
local SPREAD = WW1GIF_SPREAD or { { -96, 10 }, { -32, 0 }, { 32, 10 }, { 0, 4 }, { -64, 6 } }
local MODELS = {}
for k = 1, 5 do MODELS[k] = "models/adamwassim/player/imperialcommunity/ww1/soldatfrancais" .. k .. ".mdl" end
local P = "advinv_milou_ww1fr_"
-- One track per soldier: from frame to frame each one changes a different thing (helmet, webbing,
-- back, gas mask, the rifle), so four frames show many combinations, not one slot changing on all.
-- Per state, per soldier: the items worn (short names), and for the rifle (WW1GIF_WEAPON) hold =
-- in hands (in its safe mode: posing for a picture, not in action), mode = its carry mode.
WW1GIF_STATES = WW1GIF_STATES or {
    -- 1: helmets (backpack on, rifle slung beside it) / 2: webbing (rifle slung) / 3: the rifle, in
    -- hand, slung, muzzle down on the back, then slung beside a backpack / 4: gas mask (rifle muzzle
    -- down) / 5: headgear and webbing (rifle in hand).
    -- No front carry for the 130 cm Lebel (the generic template centres it on the chest: the stock
    -- sticks out past the shoulder).
    { { "kepi", "berthier_webbing", "backpack", mode = "sling_up" }, { "adrian_2", "berthier_webbing", mode = "sling_up" },
      { "adrian", "berthier_webbing", hold = true }, { "adrian_2", "chauchat_webbing", mode = "sling_down" },
      { "kepi", "holster_belt", hold = true } },
    { { "adrian", "berthier_webbing", "backpack" }, { "adrian_2", "chauchat_webbing" }, { "adrian", "berthier_webbing", mode = "sling_up" },
      { "adrian_4", "chauchat_webbing" }, { "adrian_2", "berthier_webbing" } },
    { { "adrian_2", "berthier_webbing", "backpack" }, { "adrian_2", "holster_berthier" }, { "adrian", "berthier_webbing", mode = "sling_down" },
      { "adrian_2", "chauchat_webbing" }, { "beanie", "holster_berthier" } },
    { { "adrian_3", "berthier_webbing", "backpack" }, { "adrian_2", "holster_belt" }, { "adrian", "berthier_webbing", "backpack", mode = "sling_up" },
      { "adrian_4", "chauchat_webbing" }, { "adrian", "berthier_webbing" } },
}
local HOLD = WW1GIF_HOLD or { false, false, false, false, true }  -- who has the rifle in hands (unless a state says)
-- poses: each body turned its own way (degrees off the camera), the eyes on the camera: the
-- body is set first, then the gaze turns to the lens (within ~30 degrees the feet stay put and
-- only the head and aim follow)
local TURN = WW1GIF_TURN or { 24, -14, 8, -22, 18 }
local DUCK = WW1GIF_DUCK or { false, false, false, false, false }
local SLOTS = { "Helmet", "Vest", "Rucksack", "Gasmask", "NVGs", "Radio" }

-- bots stand still; their facing comes from their commands (SetEyeAngles alone is overwritten)
hook.Add("StartCommand", "AdvInvWW1Gif_Bots", function(ply, cmd)
    if not ply:IsBot() then return end
    cmd:ClearMovement()
    cmd:ClearButtons()
    if ply.ww1gifAng then cmd:SetViewAngles(ply.ww1gifAng) end
    if ply.ww1gifDuck then cmd:SetButtons(IN_DUCK) end
end)
local bots = player.GetBots()
if #bots < 5 then
    for k = #bots + 1, 5 do player.CreateNextBot("Poilu" .. k) end
    return { wait = true }
end
local base, yaw = WW1GIF_SPOT[1], WW1GIF_SPOT[2]
local right, fwd = Angle(0, yaw, 0):Right(), Angle(0, yaw, 0):Forward()
local shift = WW1GIF_SHIFT or -32  -- the camera's sideways offset (units, along the squad's right)
local camPos = base + fwd * (WW1GIF_DIST or 165) + right * shift + Vector(0, 0, 54)
local function ground(p)
    local tr = util.TraceLine({ start = p + Vector(0, 0, 80), endpos = p - Vector(0, 0, 200), mask = MASK_SOLID_BRUSHONLY })
    return tr.Hit and tr.HitPos or p
end
-- where a standing player's box rests near p: on a slope or beside a sandbag a box set at the
-- ground under its centre intersects the map, and the bot then stays stuck (crouched, or in the
-- jump animation); nudged a few units until it fits on walkable ground
local NUDGE = { { 0, 0 }, { 8, 0 }, { -8, 0 }, { 0, 8 }, { 0, -8 }, { 12, 12 }, { -12, 12 }, { 12, -12 }, { -12, -12 }, { 20, 0 }, { -20, 0 }, { 0, 20 }, { 0, -20 } }
local function place(p)
    for _, n in ipairs(NUDGE) do
        local q = ground(p + right * n[1] + fwd * n[2])
        local tr = util.TraceHull({ start = q + Vector(0, 0, 30), endpos = q - Vector(0, 0, 60),
            mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72), mask = MASK_PLAYERSOLID, filter = player.GetAll() })
        if tr.Hit and not tr.StartSolid and tr.HitNormal.z > 0.75 then return tr.HitPos + Vector(0, 0, 1) end
    end
    return ground(p) + Vector(0, 0, 6)
end
-- a soldier with the rifle in hands has it in TFA's safe mode, as a player would (the rifle
-- lowered across the body, passive hold, standing or crouched); held ready, it follows his gaze,
-- points at the lens and hides his face
local function shoulder(b)
    timer.Simple(0.5, function()
        if not IsValid(b) then return end
        local w = b:GetActiveWeapon()
        if IsValid(w) and w.IsSafety and w.CycleSafety and not w:IsSafety() then w:CycleSafety() end
    end)
end
for k = 1, 5 do
    local b = bots[k]
    if not b:Alive() then b:Spawn() end
    b:SetModel(MODELS[k])
    for g = 0, b:GetNumBodyGroups() - 1 do b:SetBodygroup(g, 0) end
    b:SetMoveType(MOVETYPE_WALK)
    -- player boxes are aligned on the world's axes, not the squad's: on a diagonal row, soldiers
    -- close together overlap and get stuck in each other (jump animation) unless they pass through
    b:SetNoCollideWithTeammates(true)
    b:SetPos(place(base + right * SPREAD[k][1] + fwd * SPREAD[k][2]))
    b.ww1gifAng = Angle(0, (camPos - b:GetPos()):Angle().y + (TURN[k] or 0), 0)  -- the body first
    b:SetEyeAngles(b.ww1gifAng)
    -- the crouch: the engine starts one only when the duck key goes down, so it is released for a
    -- moment first (held all along, a respawned bot never crouches again)
    b.ww1gifDuck = nil
    timer.Simple(0.3, function() if IsValid(b) then b.ww1gifDuck = DUCK[k] or nil end end)
    timer.Simple(1, function()  -- then the eyes on the camera
        if not IsValid(b) then return end
        local look = (camPos - (b:GetPos() + Vector(0, 0, b.ww1gifDuck and 40 or 64))):Angle()
        -- the crouch animation bows the head: aim higher to bring the face up to the lens
        b.ww1gifAng = Angle(math.NormalizeAngle(look.p) - (b.ww1gifDuck and (WW1GIF_DUCKUP or 25) or 0), look.y, 0)
    end)
    I.SetDefaults(b)
    if WW1GIF_WEAPON then I.Equip(b, { id = I.GENERIC_WEAPON, c = WW1GIF_WEAPON, r = 8 }) end
    local held = HOLD[k] and WW1GIF_WEAPON
    b:SelectWeapon(held or "keys")
    shoulder(b)
end
concommand.Add("advinv_ww1gif_state", function(p, _, args)
    if not (IsValid(p) and p:IsListenServerHost()) then return end
    local st = WW1GIF_STATES[tonumber(args[1]) or 0]
    if not st then return end
    for k, b in ipairs(player.GetBots()) do
        local want = st[k] or {}
        for _, s in ipairs(SLOTS) do if b:GetNW2Int(s) > 1 then I.TakeOff(b, s) end end
        for _, short in ipairs(want) do
            local c = P .. short
            local t = scripted_ents.Get(c)
            if t and C[c] then I.Equip(b, { id = C[c], a = t.Armor or 0 }, {}) end
        end
        I.ApplyModelGear(b)
        if WW1GIF_WEAPON then
            if want.mode then I.RequestCarryMode(b, "PrimaryWep", want.mode) end
            b:SelectWeapon((want.hold or (want.hold == nil and HOLD[k])) and WW1GIF_WEAPON or "keys")
            shoulder(b)
        end
    end
end)
-- the camera, for the client: in front of the squad, a little to the side
SetGlobalVector("ww1gif_cam", camPos)
SetGlobalVector("ww1gif_look", base + fwd * 12 + right * shift + Vector(0, 0, 40))
return { bots = 5, states = #WW1GIF_STATES }
--@client
local done = ASYNC(240)
local N = WW1GIF_COUNT or 4
local W, H = ScrW(), ScrH()
local rt = GetRenderTargetEx("advinv_ww1gif", W, H, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE, bit.bor(2, 256), 0, IMAGE_FORMAT_RGB888)
file.CreateDir("devkit_cl/gif")
local function capture(name, cb)
    local taken = false
    hook.Add("PostRender", "AdvInv_WW1Gif", function()
        if taken then return end
        taken = true
        hook.Remove("PostRender", "AdvInv_WW1Gif")
        local cam, look = GetGlobalVector("ww1gif_cam"), GetGlobalVector("ww1gif_look")
        local o = WW1GIF_CAM or cam
        -- optional: a dynamic fill light from the camera's side (WW1GIF_FILL = brightness)
        local dl = (WW1GIF_FILL or 0) > 0 and DynamicLight(4242)
        if dl then
            dl.pos = o + Vector(0, 0, 30)
            dl.r, dl.g, dl.b = 255, 236, 210
            dl.brightness = WW1GIF_FILL or 2
            dl.size = 520
            dl.decay = 0
            dl.dietime = CurTime() + 2
        end
        render.PushRenderTarget(rt)
        render.Clear(0, 0, 0, 255, true, true)
        -- the squad stands in the trench's shade: models lit like soft overcast daylight instead
        -- (an ambient cube, brightest from the camera's side; the map keeps its own lighting)
        local L = WW1GIF_LIGHT or 0  -- (0: the map's own light, the default)
        if L > 0 then
            local toCam = (o - (WW1GIF_LOOK or look))
            toCam.z = 0
            toCam:Normalize()
            render.SuppressEngineLighting(true)
            local function side(dir) return 0.22 + 0.42 * math.max(0, dir:Dot(toCam)) end
            local cube = { { Vector(1, 0, 0), 0 }, { Vector(-1, 0, 0), 1 }, { Vector(0, 1, 0), 2 }, { Vector(0, -1, 0), 3 } }
            for _, c in ipairs(cube) do
                local v = side(c[1]) * L
                render.SetModelLighting(c[2], v * 0.95, v * 0.97, v)
            end
            render.SetModelLighting(4, 0.5 * L * 0.95, 0.5 * L * 0.97, 0.5 * L)
            render.SetModelLighting(5, 0.1 * L, 0.1 * L, 0.1 * L)
            render.SetLocalModelLights({})
        end
        render.RenderView({ origin = o, angles = ((WW1GIF_LOOK or look) - o):Angle(), fov = WW1GIF_FOV or 62,
            x = 0, y = 0, w = W, h = H, drawhud = false, drawviewmodel = false, znear = 3 })
        if L > 0 then render.SuppressEngineLighting(false) end
        local data = render.Capture({ format = "png", x = 0, y = 0, w = W, h = H })
        render.PopRenderTarget()
        file.Write("devkit_cl/gif/" .. name .. ".png", data or "")
        cb(data and #data or 0)
    end)
end
-- the head raised or lowered to the lens (bots don't send their view pitch) and the eyes on it
hook.Add("PrePlayerDraw", "AdvInv_WW1Gif_Eyes", function(ply)
    if not ply:IsBot() then return end
    local cam = WW1GIF_CAM or GetGlobalVector("ww1gif_cam")
    ply:SetEyeTarget(cam)
    local hb = ply:LookupBone("ValveBiped.Bip01_Head1")
    local hp = hb and ply:GetBonePosition(hb)
    if not hp then return end
    local pitch = (cam - hp):Angle().p
    pitch = math.NormalizeAngle(pitch) + (ply:Crouching() and (WW1GIF_DUCKUP or -30) or 0)
    ply:SetPoseParameter("head_pitch", math.Clamp(pitch, -60, 60))
    ply:InvalidateBoneCache()
end)
local sizes = {}
local function step(k)
    if k > N then return done({ frames = N, bytes = sizes }) end
    RunConsoleCommand("advinv_ww1gif_state", tostring(k))
    timer.Simple(WW1GIF_WAIT or 2, function()
        capture(string.format("ww1_%02d", k), function(n) sizes[#sizes + 1] = n step(k + 1) end)
    end)
end
timer.Simple(2, function() step(1) end)
