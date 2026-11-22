--[[
    Option: the carried load slows the player down, as in Arma 3 (off by default).

    The load is the mass of everything the player carries: contents of the uniform, vest and
    backpack, plus the equipped items (helmet, vest, backpack, weapons...). Up to advinv_load_free
    points there is no effect; above it, speed drops down to advinv_load_min_speed (fraction of the
    normal speed), reached at advinv_load_max points.

        advinv_load_slowdown 1       -- turns the option on (server.cfg)
        advinv_load_free 300
        advinv_load_max 1000
        advinv_load_min_speed 0.55
--]]
local I = AdvInv
local FLAGS = { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY }

local enabled = CreateConVar("advinv_load_slowdown", "0", FLAGS, "The carried load slows the player down (0 or 1)", 0, 1)
local free = CreateConVar("advinv_load_free", "300", FLAGS, "Load carried without any effect on speed (points)", 0)
local full = CreateConVar("advinv_load_max", "1000", FLAGS, "Load at which the slowdown is at its maximum (points)", 1)
local minSpeed = CreateConVar("advinv_load_min_speed", "0.55", FLAGS, "Remaining speed at the maximum load (0.1 to 1)", 0.1, 1)

function I.LoadSlowdownEnabled() return enabled:GetBool() end

-- Fraction de la vitesse normale (1 = aucun effet).
function I.SpeedFactor(ply)
    if not enabled:GetBool() then return 1 end
    local load = ply:GetNWInt("AdvInvLoad")
    local f = free:GetFloat()
    local m = math.max(full:GetFloat(), f + 1)
    local k = math.Clamp((load - f) / (m - f), 0, 1)
    return 1 - k * (1 - math.Clamp(minSpeed:GetFloat(), 0.1, 1))
end

hook.Add("SetupMove", "AdvInv_Load", function(ply, mv)
    local factor = I.SpeedFactor(ply)
    if factor >= 1 then return end
    mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * factor)
    mv:SetMaxSpeed(mv:GetMaxSpeed() * factor)
end)
