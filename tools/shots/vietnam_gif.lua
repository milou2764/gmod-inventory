-- Frames of the Vietnam Workshop screenshot (dev tool, not shipped): five US soldiers (bots) of the
-- Vietnam era posing in front of a bamboo stilt hut, whose gear changes from frame to frame (the
-- Vietnam US extension's items, shown by the soldiers' own bodygroups), the M16A1 VNGIF_WEAPON
-- slung or held. Rendered into a target (no HUD, hints or counters). Frames:
-- data/devkit_cl/gif/vn_<nn>.png, then the skill's make_gif.py. Needs the soldiers as playermodels
-- ([PM]&[NPC] Vietnam era US Soldiers, Workshop 3188829345: the same models/namsoldiers paths as the
-- ragdolls the extension takes its gear from, with player animations), the extension
-- advinv-ext-vietnam-us, the map rp_sog_lgdv_v3_day (RP Vietnam War Day, 2147462595; its sun at
-- pitch -45, brightness 768) and the rifle: VNGIF_WEAPON = the class of [TFA][AT] M16A1 (Workshop
-- 3436346826, with the TFA base and TFA Insurgency Shared Parts, subscribed in Steam: its Lua runs,
-- so never mounted by hand). Models and the map may be linked in by hand.
--   python devkit/gmodclient.py start --gamemode darkrp --map rp_sog_lgdv_v3_day --maxplayers 8 --size 1920x1080
--   python devkit/gmodclient.py scene advanced-inventory/tools/shots/vietnam_gif.lua   (twice: bots first)
--@serveur
local I, C = AdvInv, AdvInv.ClassID
-- squad centre (ground) and the way they face (toward the camera): on the path in front of a bamboo
-- stilt hut among palm trees, the sun on their fronts (render.ComputeLighting there: 2.2 facing
-- 90-135 degrees, 0.2 facing away)
VNGIF_SPOT = VNGIF_SPOT or { Vector(7297, -9235, -1189), 150 }
-- a group photo: the five standing side by side, the ends a little forward. Sideways (right),
-- depth toward the camera. Image left to right: 1 to 5
local SPREAD = VNGIF_SPREAD or { { 64, 10 }, { 32, 0 }, { 0, 4 }, { -32, 0 }, { -64, 10 } }
local MODELS = VNGIF_MODELS or { "models/namsoldiers/male_01.mdl", "models/namsoldiers/male_03.mdl",
    "models/namsoldiers/male_05.mdl", "models/namsoldiers/male_08.mdl", "models/namsoldiers/male_09.mdl" }  -- (male_07: a pale patch on the face; nick: purple eyes)
local P = "advinv_milou_vnus_"
-- One track per soldier: from frame to frame each one changes a different thing, so four frames
-- show many combinations. Per state, per soldier: the items worn (short names), hold = the rifle
-- in hands (in its safe mode: posing for a picture, not in action), mode = its carry mode.
VNGIF_STATES = VNGIF_STATES or {
    -- 1: helmets / 2: web gear / 3: the rifle: in hand, slung, muzzle down, in front / 4: his gear
    -- off and back on (the hat, then the web gear) / 5: the rifle in hand, then slung beside a pack
    -- he puts on (seen from the front, a pack on its own hardly shows: turned, the upper body
    -- follows the gaze to the lens and keeps the pack hidden)
    { { "m1_cover", "web_gear" }, { "m1", "web_gear" }, { "m1_cover_ace", "web_gear_2", hold = true },
      { "boonie", "web_gear_2" }, { "m1", "web_gear_m60_belt", hold = true } },
    { { "m1_cover_ace", "web_gear" }, { "m1", "web_gear_2" }, { "m1_cover_ace", "web_gear_2", mode = "sling_up" },
      { "web_gear_2" }, { "m1", "web_gear_m60_belt", "tropical_rucksack", mode = "sling_up" } },
    { { "m1_born_to_kill", "web_gear" }, { "m1", "web_gear_bandolier" }, { "m1_cover_ace", "web_gear_2", mode = "sling_down" },
      {}, { "m1", "web_gear_m60_belt", hold = true } },
    { { "boonie", "web_gear" }, { "m1", "web_gear_m60_belt" }, { "m1_cover_ace", "web_gear_2", mode = "front_hang" },
      { "boonie", "web_gear_2" }, { "m1", "web_gear_m60_belt", "frame_rucksack", mode = "sling_up" } },
}
-- poses: each body turned its own way (degrees off the camera), the eyes on the camera: the body is
-- set first, then the gaze turns to the lens (within ~30 degrees the feet stay put)
local TURN = VNGIF_TURN or { 22, -12, 10, -26, 16 }
local SLOTS = { "Helmet", "Vest", "Rucksack", "Gasmask", "NVGs", "Radio" }

-- bots stand still; their facing comes from their commands (SetEyeAngles alone is overwritten, and
-- a view set once stays pinned: both every tick)
hook.Add("StartCommand", "AdvInvVnGif_Bots", function(ply, cmd)
    if not ply:IsBot() then return end
    cmd:ClearMovement()
    cmd:ClearButtons()
    if ply.vngifAng then
        cmd:SetViewAngles(ply.vngifAng)
        if ply:EyeAngles() ~= ply.vngifAng then ply:SetEyeAngles(ply.vngifAng) end
    end
end)
local bots = player.GetBots()
if #bots < 5 then
    for k = #bots + 1, 5 do player.CreateNextBot("GI" .. k) end
    return { wait = true }
end
local base, yaw = VNGIF_SPOT[1], VNGIF_SPOT[2]
local right, fwd = Angle(0, yaw, 0):Right(), Angle(0, yaw, 0):Forward()
local shift = VNGIF_SHIFT or 0  -- the camera's sideways offset (units, along the squad's right)
local camPos = base + fwd * (VNGIF_DIST or 165) + right * shift + Vector(0, 0, VNGIF_CAMZ or 54)
local function ground(p)
    local tr = util.TraceLine({ start = p + Vector(0, 0, 80), endpos = p - Vector(0, 0, 200), mask = MASK_SOLID_BRUSHONLY })
    return tr.Hit and tr.HitPos or p
end
-- where a standing player's box rests near p (nudged until it fits on walkable ground: a box set
-- into a slope keeps the bot stuck in the jump animation)
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
-- a soldier with the rifle in hands has it in TFA's safe mode, as a player would (lowered across
-- the body); held ready, it follows his gaze, points at the lens and hides his face
local function safe(b)
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
    b:SetMoveType(MOVETYPE_WALK)
    -- (player boxes are aligned on the world's axes: close together on a diagonal row they overlap)
    b:SetNoCollideWithTeammates(true)
    b:SetPos(place(base + right * SPREAD[k][1] + fwd * SPREAD[k][2]))
    b.vngifAng = Angle(0, (camPos - b:GetPos()):Angle().y + (TURN[k] or 0), 0)  -- the body first
    b:SetEyeAngles(b.vngifAng)
    timer.Simple(1, function()  -- then the eyes on the camera
        if not IsValid(b) then return end
        b.vngifAng = Angle(0, (camPos - b:GetPos()):Angle().y, 0)
    end)
    I.SetDefaults(b)
    if VNGIF_WEAPON then I.Equip(b, { id = I.GENERIC_WEAPON, c = VNGIF_WEAPON, r = 20 }) end
    b:SelectWeapon("keys")
end
concommand.Add("advinv_vngif_state", function(p, _, args)
    if not (IsValid(p) and p:IsListenServerHost()) then return end
    local st = VNGIF_STATES[tonumber(args[1]) or 0]
    if not st then return end
    for k, b in ipairs(player.GetBots()) do
        if k > 5 then break end
        local want = st[k] or {}
        for _, s in ipairs(SLOTS) do if b:GetNW2Int(s) > 1 then I.TakeOff(b, s) end end
        for _, short in ipairs(want) do
            local c = P .. short
            local t = scripted_ents.Get(c)
            if t and C[c] then I.Equip(b, { id = C[c], a = t.Armor or 0 }, {}) end
        end
        I.ApplyModelGear(b)
        if VNGIF_WEAPON then
            if want.mode then I.RequestCarryMode(b, "PrimaryWep", want.mode) end
            b:SelectWeapon(want.hold and VNGIF_WEAPON or "keys")
            safe(b)
        end
    end
end)
-- the scene in the local player's view wherever he spawned (else the bots stay dormant on the
-- client), and the local player at the camera looking at the squad (the exposure follows his view),
-- empty-handed (no physics gun glow)
hook.Add("SetupPlayerVisibility", "AdvInvVnGif_PVS", function() AddOriginToPVS(camPos) AddOriginToPVS(base) end)
local host = player.GetHumans()[1]
if IsValid(host) and VNGIF_HOST ~= false then
    host:SetPos(ground(camPos + fwd * 30) + Vector(0, 0, 2))
    host:SetEyeAngles((base + Vector(0, 0, 50) - camPos):Angle())
    host:SelectWeapon("keys")
end
SetGlobalVector("vngif_cam", camPos)
SetGlobalVector("vngif_look", base + fwd * 12 + right * shift + Vector(0, 0, VNGIF_LOOKZ or 40))
return { bots = 5, states = #VNGIF_STATES }
--@client
local done = ASYNC(240)
local N = VNGIF_COUNT or 4
local W, H = ScrW(), ScrH()
local rt = GetRenderTargetEx("advinv_vngif", W, H, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE, bit.bor(2, 256), 0, IMAGE_FORMAT_RGB888)
file.CreateDir("devkit_cl/gif")
local function capture(name, cb)
    local taken = false
    hook.Add("PostRender", "AdvInv_VnGif", function()
        if taken then return end
        taken = true
        hook.Remove("PostRender", "AdvInv_VnGif")
        local cam, look = GetGlobalVector("vngif_cam"), GetGlobalVector("vngif_look")
        local o = VNGIF_CAM or cam
        render.PushRenderTarget(rt)
        render.Clear(0, 0, 0, 255, true, true)
        render.RenderView({ origin = o, angles = ((VNGIF_LOOK or look) - o):Angle(), fov = VNGIF_FOV or 62,
            x = 0, y = 0, w = W, h = H, drawhud = false, drawviewmodel = false, znear = 3 })
        local data = render.Capture({ format = "png", x = 0, y = 0, w = W, h = H })
        render.PopRenderTarget()
        file.Write("devkit_cl/gif/" .. name .. ".png", data or "")
        cb(data and #data or 0)
    end)
end
-- the head raised or lowered to the lens (bots don't send their view pitch) and the eyes on it
hook.Add("PrePlayerDraw", "AdvInv_VnGif_Eyes", function(ply)
    if not ply:IsBot() then return end
    local cam = VNGIF_CAM or GetGlobalVector("vngif_cam")
    ply:SetEyeTarget(cam)
    local hb = ply:LookupBone("ValveBiped.Bip01_Head1")
    local hp = hb and ply:GetBonePosition(hb)
    if not hp then return end
    ply:SetPoseParameter("head_pitch", math.Clamp(math.NormalizeAngle((cam - hp):Angle().p), -60, 60))
    ply:InvalidateBoneCache()
end)
local sizes = {}
local function step(k)
    if k > N then return done({ frames = N, bytes = sizes }) end
    RunConsoleCommand("advinv_vngif_state", tostring(k))
    timer.Simple(VNGIF_WAIT or 2, function()
        capture(string.format("vn_%02d", k), function(n) sizes[#sizes + 1] = n step(k + 1) end)
    end)
end
timer.Simple(2, function() step(1) end)
