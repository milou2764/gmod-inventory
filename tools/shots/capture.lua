-- Clean screen capture for the Workshop images (dev tool, not shipped): the player's view (or the
-- camera SHOT_VIEW = { origin, angles, fov }), DarkRP's HUD and the inventory windows, rendered into
-- a 1920x1080 target: no Garry's Mod hints, no debug counters (the user's settings are not changed).
-- SHOT_NAME: file name (data/devkit_cl/shots/<name>.jpg). SHOT_NOHUD = true: no HUD.
--   python devkit/gmodclient.py scene advanced-inventory/tools/shots/capture.lua
--@serveur
return { ok = true }
--@client
local done = ASYNC(15)
local W, H = ScrW(), ScrH()
local rt = GetRenderTargetEx("advinv_shot", W, H, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE, bit.bor(2, 256), 0, IMAGE_FORMAT_RGB888)
local name = SHOT_NAME or "shot"
local zone = IsValid(AdvInv.dropZone) and AdvInv.dropZone or nil
local extra = {}
for _, p in ipairs(SHOT_PANELS or {}) do if IsValid(p) then extra[#extra + 1] = p end end
if zone then zone:SetPaintedManually(true) end
for _, p in ipairs(extra) do p:SetPaintedManually(true) end
local taken = false
hook.Add("PostRender", "AdvInv_Shot", function()
    if taken then return end
    taken = true
    hook.Remove("PostRender", "AdvInv_Shot")
    local ply = LocalPlayer()
    local v = SHOT_VIEW or hook.Run("CalcView", ply, ply:EyePos(), ply:EyeAngles(), 75) or {}
    render.PushRenderTarget(rt)
    render.Clear(0, 0, 0, 255, true, true)
    render.RenderView({ origin = v.origin or ply:EyePos(), angles = v.angles or ply:EyeAngles(), fov = v.fov or 75,
        x = 0, y = 0, w = W, h = H, drawhud = false, drawviewmodel = SHOT_VIEW == nil and not SHOT_NOVM, znear = 3 })
    cam.Start2D()
    if not SHOT_NOHUD then
        if GAMEMODE.HUDPaint then GAMEMODE:HUDPaint() end
        hook.Run("HUDPaint")
    end
    if zone then zone:PaintManual() end
    for _, p in ipairs(extra) do p:PaintManual() end
    cam.End2D()
    local data = render.Capture({ format = "jpeg", quality = 95, x = 0, y = 0, w = W, h = H })
    render.PopRenderTarget()
    if zone then zone:SetPaintedManually(false) end
    for _, p in ipairs(extra) do p:SetPaintedManually(false) end
    file.Write("devkit_cl/shots/" .. name .. ".jpg", data or "")
    done({ capture = name, bytes = data and #data or 0 })
end)
