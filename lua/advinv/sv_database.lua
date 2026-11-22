--[[
    SQLite tables of the inventory (created if missing; their columns never change, the data is
    JSON, so they are never dropped):
        advinv_inventory   OwnerID, Data    saved inventories (sv_inventory.lua)
        advinv_storage     permanent storages (sv_storage.lua)
        advinv_stores      shared and personal stores, banks (sv_storage.lua)
--]]
local I = AdvInv
local TAG = "Database"

I.TABLE = "advinv_inventory"

function I.SQLRequest(request)
    if sql.Query(request) == false then
        I.Log.d(TAG, "error in SQL request: " .. request)
        I.Log.d(TAG, sql.LastError())
        return false
    end
    return true
end

sql.Query("CREATE TABLE IF NOT EXISTS " .. I.TABLE .. " (OwnerID TEXT PRIMARY KEY, Data TEXT)")
