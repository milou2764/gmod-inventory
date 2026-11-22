-- Debug log, only when AdvInv.Debug is true.
AdvInv = AdvInv or {}
AdvInv.Log = AdvInv.Log or {}

local white = Color(255, 255, 255)
local red = Color(255, 80, 80)

local function log(col, tag, m)
    MsgC(red, "[AdvInv] ", white, os.date("%X"), " ", tag, " ", col, tostring(m), "\n")
end

function AdvInv.Log.d(tag, m)
    if not AdvInv.Debug then return end
    log(white, tag, m)
end

function AdvInv.Log.e(tag, m)
    log(red, tag, m)
end
