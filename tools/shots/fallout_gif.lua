-- Frames of the Fallout Workshop screenshot (dev tool, not shipped): five vault dwellers (bots) seen
-- from behind, looking out over the wasteland (the user's choice: the packs are on their backs; a
-- face can only look at the lens with the body at most ~25 degrees off the camera, and the player
-- animation draws no "look over the shoulder"). What they carry changes from frame to frame: the
-- Fallout 76 and Fallout 3 backpacks, a laser rifle and a 10mm pistol used through the inventory.
-- Rendered into a target (no HUD, hints or counters). Frames: data/devkit_cl/gif/fo_<nn>.png, then
-- make_gif.py (--colors 256 --method octree: the red and purple packs). Needs: Vault Dwellers Part 1 (Workshop 3612720459), Fallout 76 - Backpacks
-- (3234192542), Fallout 3 Custom Backpacks (891790188), FO3 Backpacks (315810701), the map
-- sanctuary_hills_final (Sanctuary Hills [Fallout 4], 1455024343, with its textures in Sanctuary
-- Hills - Map Content 1454955042 and Map Content 2 1454958597) and the weapons FOGIF_RIFLE / FOGIF_PISTOL (classes of
-- [TFA] Fallout Institute Rifle & 10MM Pistol, 922863387, with the TFA base: subscribed in Steam,
-- their Lua runs; models, textures and maps of the others may be linked in by hand).
--   python devkit/gmodclient.py start --gamemode darkrp --map <map> --maxplayers 8 --size 1920x1080
--   python devkit/gmodclient.py scene advanced-inventory/tools/shots/fallout_gif.lua   (twice: bots first)
--@serveur
local I, C = AdvInv, AdvInv.ClassID
-- the group's centre (ground) and the way they look: on sanctuary_hills_final (the user's choice
-- of map for better light: its sun low in the east, pitch -35; render.ComputeLighting 0.81 on a
-- surface facing east, 0.02 facing west), on the lawn between two houses of Sanctuary Hills,
-- looking west down the street at the houses across it (a fire hydrant in the corner): the sun
-- full on their backs, their shadows long and diagonal on the ground. The user's pick among four
-- spots (a back yard between picket fences, Vector(933, -983, -153) yaw 170, was the other
-- candidate). (Before: Fallout: Mojave Wasteland, 2093902215, Vector(-8100, 650, 66) yaw 327; its
-- haze and flatter light made the user look for another map)
FOGIF_SPOT = FOGIF_SPOT or { Vector(945, -86, -159), 195 }
-- side by side (right of the way they look), depth along it (the ends a little back, nearer the
-- camera)
local SPREAD = FOGIF_SPREAD or { { -68, -8 }, { -34, 0 }, { 0, -2 }, { 34, 0 }, { 68, -8 } }
-- who: model, bodygroups (2 outfit: vault suit / security / lab / hazard; 3 Pip-Boy: 0 on, 1 off;
-- 4-6 the vault number's digits on the back, 1-10 = 1..9, 0), what they carry
local DWELLERS = FOGIF_DWELLERS or {
    { "models/humans/vaulttec/male_01.mdl", { [2] = 0, [3] = 0, [4] = 1, [5] = 10, [6] = 1 }, {} },
    { "models/humans/vaulttec/male_02.mdl", { [2] = 1, [3] = 1, [4] = 1, [5] = 1, [6] = 1 }, { rifle = true } },
    { "models/humans/vaulttec/male_03.mdl", { [2] = 0, [3] = 0, [4] = 0, [5] = 7, [6] = 6 }, { pistol = true } },
    { "models/humans/vaulttec/male_04.mdl", { [2] = 2, [3] = 0, [4] = 0, [5] = 8, [6] = 1 }, { pistol = true } },
    { "models/humans/vaulttec/male_02.mdl", { [2] = 0, [3] = 1, [4] = 1, [5] = 1, [6] = 1 }, {} },
}
local F76, F3 = "advinv_c_fo76_backpacks_", "advinv_c_fo3_"
-- One track per dweller: from frame to frame each one changes a different thing, so four frames
-- show many combinations. Per state, per dweller: the items worn (classes), hold = "rifle" or
-- "pistol" in hand (in its safe mode, as a player at rest holds it), mode = the rifle's carry mode.
FOGIF_STATES = FOGIF_STATES or {
    -- 1: Fallout 76 packs / 2: the rifle: in hand, slung, muzzle down, then slung beside a pack he
    -- put on (the front carry is hidden from behind) / 3: Fallout 3 packs (pistol holstered) / 4:
    -- the pistol in hand or holstered (Fallout 76 pack) / 5: a pack off and on (the vault number
    -- on the back shows)
    { { F76 .. "backpack_vault_survivor" }, { hold = "rifle" }, { F3 .. "custom_backpack_1" },
      { F76 .. "atx_backpack_wanderer", hold = "pistol" }, {} },
    { { F76 .. "backpack_cappy" }, { mode = "sling_up" }, { F3 .. "custom_backpack_3" },
      { F76 .. "atx_backpack_wanderer" }, { F76 .. "backpack_packrat" } },
    { { F76 .. "backpack_bottle" }, { mode = "sling_down" }, { F3 .. "campish_campish_pack" },
      { F76 .. "atx_backpack_wanderer", hold = "pistol" }, {} },
    { { F76 .. "backpack_space_explorer" }, { F3 .. "custom_backpack_2", mode = "sling_up" }, { F3 .. "custom_backpack_5" },
      { F76 .. "atx_backpack_wanderer" }, { F76 .. "backpack_postalservice" } },
}
-- poses: each body turned its own way off the look direction (degrees), then the head turned to
-- where that one looks (within ~25 degrees of the body: the feet stay put). The two who take a
-- weapon in hand stand turned a little sideways, else from behind the weapon is hidden: 2 shows
-- his left side (the rifle held low across the body), 4 his right side (the pistol); their
-- heads follow their bodies (looking at another part of the town)
local BODY = FOGIF_BODY or { 10, 50, 4, -55, 14 }
local LOOK = FOGIF_LOOK or { -20, 0, -4, 0, -16 }
-- or all of them, bodies and gaze, toward one place (the user: "their bodies facing the same
-- object"): far ahead along the look direction, so the five bodies stand parallel
-- (FOGIF_TARGET = false: the per-dweller turns above)
local TARGET = FOGIF_TARGET
if TARGET == nil then TARGET = FOGIF_SPOT[1] + Angle(0, FOGIF_SPOT[2], 0):Forward() * 2500 end
local SLOTS = { "Helmet", "Vest", "Rucksack", "Gasmask", "NVGs", "Radio" }

hook.Add("StartCommand", "AdvInvFoGif_Bots", function(ply, cmd)
    if not ply:IsBot() then return end
    cmd:ClearMovement()
    cmd:ClearButtons()
    -- in the command and on the player: after a SetEyeAngles the bot's view stays pinned to it and
    -- later command angles are ignored
    if ply.fogifAng then
        cmd:SetViewAngles(ply.fogifAng)
        if ply:EyeAngles() ~= ply.fogifAng then ply:SetEyeAngles(ply.fogifAng) end
    end
end)
local bots = player.GetBots()
if #bots < 5 then
    for k = #bots + 1, 5 do player.CreateNextBot("Dweller" .. k) end
    return { wait = true }
end
local base, yaw = FOGIF_SPOT[1], FOGIF_SPOT[2]
local right, fwd = Angle(0, yaw, 0):Right(), Angle(0, yaw, 0):Forward()
local shift = FOGIF_SHIFT or 0  -- the camera's sideways offset (units, along the group's right)
local camPos = base - fwd * (FOGIF_DIST or 185) + right * shift + Vector(0, 0, FOGIF_CAMZ or 64)
local lookAt = base + fwd * (FOGIF_LOOKF or 60) + right * shift + Vector(0, 0, FOGIF_LOOKZ or 46)
local function ground(p)
    local tr = util.TraceLine({ start = p + Vector(0, 0, 80), endpos = p - Vector(0, 0, 200), mask = MASK_SOLID_BRUSHONLY })
    return tr.Hit and tr.HitPos or p
end
-- where a standing player's box rests near p (nudged until it fits on walkable ground)
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
-- a weapon in hand is in TFA's safe mode, as a player at rest holds it
local function safe(b)
    timer.Simple(0.5, function()
        if not IsValid(b) then return end
        local w = b:GetActiveWeapon()
        if IsValid(w) and w.IsSafety and w.CycleSafety and not w:IsSafety() then w:CycleSafety() end
    end)
end
local function hand(b, k, want)
    local d = DWELLERS[k][3]
    local cls = (want.hold == "rifle" and d.rifle and FOGIF_RIFLE) or (want.hold == "pistol" and d.pistol and FOGIF_PISTOL)
    b:SelectWeapon(cls or "keys")
    safe(b)
end
for k = 1, 5 do
    local b, d = bots[k], DWELLERS[k]
    if not b:Alive() then b:Spawn() end
    b:SetModel(d[1])
    for g = 0, b:GetNumBodyGroups() - 1 do b:SetBodygroup(g, d[2][g] or 0) end
    b:SetMoveType(MOVETYPE_WALK)
    b:SetNoCollideWithTeammates(true)
    b:SetPos(place(base + right * SPREAD[k][1] + fwd * SPREAD[k][2]))
    -- the body first, then the head to where this one looks
    local toward = TARGET and (TARGET - b:GetPos()):Angle().y
    b.fogifAng = Angle(0, toward or (yaw + (BODY[k] or 0)), 0)
    b:SetEyeAngles(b.fogifAng)
    timer.Simple(1, function()
        if IsValid(b) then b.fogifAng = Angle(0, toward or (yaw + (BODY[k] or 0) + (LOOK[k] or 0)), 0) end
    end)
    I.SetDefaults(b)
    if d[3].rifle and FOGIF_RIFLE then I.Equip(b, { id = I.GENERIC_WEAPON, c = FOGIF_RIFLE, r = 20 }) end
    if d[3].pistol and FOGIF_PISTOL then I.Equip(b, { id = I.GENERIC_WEAPON, c = FOGIF_PISTOL, r = 12 }) end
    b:SelectWeapon("keys")
end
concommand.Add("advinv_fogif_state", function(p, _, args)
    if not (IsValid(p) and p:IsListenServerHost()) then return end
    local st = FOGIF_STATES[tonumber(args[1]) or 0]
    if not st then return end
    for k, b in ipairs(player.GetBots()) do
        if k > 5 then break end
        local want = st[k] or {}
        for _, s in ipairs(SLOTS) do if b:GetNW2Int(s) > 1 then I.TakeOff(b, s) end end
        for _, c in ipairs(want) do
            local t = scripted_ents.Get(c)
            if t and C[c] then I.Equip(b, { id = C[c], a = t.Armor or 0 }, {}) end
        end
        I.ApplyModelGear(b)
        if want.mode and FOGIF_RIFLE then I.RequestCarryMode(b, "PrimaryWep", want.mode) end
        hand(b, k, want)
    end
end)
-- the scene in the local player's view set wherever he spawned (else the bots stay dormant on the
-- client: not sent, not drawn)
hook.Add("SetupPlayerVisibility", "AdvInvFoGif_PVS", function() AddOriginToPVS(camPos) AddOriginToPVS(base) end)
-- the local player stands where the camera is, looking at the group: the game adapts its exposure
-- to what he looks at (looking at a bright sky elsewhere, the capture came out dark)
local host = player.GetHumans()[1]
if IsValid(host) and FOGIF_HOST ~= false then
    host:SetPos(ground(camPos) + Vector(0, 0, 2))
    host:SetEyeAngles((lookAt - (ground(camPos) + Vector(0, 0, 64))):Angle())
    -- empty hands: the physics gun's glow lit the ground in front of the camera (cyan patch)
    host:SelectWeapon("keys")
end
SetGlobalVector("fogif_cam", camPos)
SetGlobalVector("fogif_look", lookAt)
return { bots = 5, states = #FOGIF_STATES }
--@client
local done = ASYNC(240)
local N = FOGIF_COUNT or 4
local W, H = ScrW(), ScrH()
local rt = GetRenderTargetEx("advinv_fogif", W, H, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE, bit.bor(2, 256), 0, IMAGE_FORMAT_RGB888)
file.CreateDir("devkit_cl/gif")
local function capture(name, cb)
    local taken = false
    hook.Add("PostRender", "AdvInv_FoGif", function()
        if taken then return end
        taken = true
        hook.Remove("PostRender", "AdvInv_FoGif")
        local o, look = FOGIF_CAM or GetGlobalVector("fogif_cam"), FOGIF_LOOKAT or GetGlobalVector("fogif_look")
        render.PushRenderTarget(rt)
        render.Clear(0, 0, 0, 255, true, true)
        render.RenderView({ origin = o, angles = (look - o):Angle(), fov = FOGIF_FOV or 62,
            x = 0, y = 0, w = W, h = H, drawhud = false, drawviewmodel = false, znear = 3 })
        local data = render.Capture({ format = "png", x = 0, y = 0, w = W, h = H })
        render.PopRenderTarget()
        file.Write("devkit_cl/gif/" .. name .. ".png", data or "")
        cb(data and #data or 0)
    end)
end
-- every body square to the town: their gaze is not seen from behind, only their bodies are (the
-- user: "their bodies are facing different things"). A standing player's feet keep the yaw they
-- had until the gaze turns past ~45 degrees, and the upper body twists the rest (aim_yaw,
-- head_yaw): the five then faced five ways. So each bot is drawn with its render angles on its
-- gaze and no twist, and its bones rebuilt before anything of the view is drawn: worn gear is
-- placed from the wearer's bones when the gear itself draws, sometimes before the wearer (a pack
-- then hung beside the body)
local function straight(b)
    b:SetRenderAngles(Angle(0, b:EyeAngles().y, 0))
    b:SetPoseParameter("aim_yaw", 0)
    b:SetPoseParameter("head_yaw", 0)
    b:InvalidateBoneCache()
end
hook.Add("PreDrawOpaqueRenderables", "AdvInv_FoGif_Body", function(_, sky)
    if sky then return end
    for _, b in ipairs(player.GetBots()) do
        straight(b)
        b:SetupBones()
    end
end)
hook.Add("PrePlayerDraw", "AdvInv_FoGif_Body", function(ply)
    if ply:IsBot() then straight(ply) end
end)
local sizes = {}
local function step(k)
    if k > N then return done({ frames = N, bytes = sizes }) end
    RunConsoleCommand("advinv_fogif_state", tostring(k))
    timer.Simple(FOGIF_WAIT or 2, function()
        capture(string.format("fo_%02d", k), function(n) sizes[#sizes + 1] = n step(k + 1) end)
    end)
end
timer.Simple(2, function() step(1) end)
