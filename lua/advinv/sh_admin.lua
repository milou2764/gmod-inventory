--[[
    Administration (sv_admin.lua, cl_admin.lua): admins see and change any player's inventory,
    give items, and change the server settings of the addon from a menu (console: advinv_admin, or
    the context menu on a player).

    Who is an admin: the CAMI privilege "Advanced Inventory System - Admin" (superadmins by default; ULX, SAM,
    serverguard... can give it to other groups). Without CAMI: superadmins.
--]]
local I = AdvInv

I.ADMIN_PRIVILEGE = "Advanced Inventory System - Admin"
if CAMI then
    CAMI.RegisterPrivilege({
        Name = I.ADMIN_PRIVILEGE,
        MinAccess = "superadmin",
        Description = "See and change any player's inventory, give items, change Advanced Inventory System settings",
    })
end

function I.IsAdmin(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    if CAMI and CAMI.PlayerHasAccess then
        local has
        CAMI.PlayerHasAccess(ply, I.ADMIN_PRIVILEGE, function(ok) has = ok end)
        if has ~= nil then return has and true or false end
    end
    return ply:IsSuperAdmin()
end

-- Sub-commands of the ADMIN action (4 bits).
I.ADMIN = { VIEW = 1, UNVIEW = 2, DELETE = 3, CLEAR = 4, GIVE = 5, SLOT_DELETE = 6, SLOT_TAKE = 7 }

--[[
    Server settings shown in the admin menu: { convar, kind, min, max } (kind: bool, int, float,
    choice with a list). Their labels are sh_lang.lua's "set_" .. convar. Other files add theirs.
--]]
I.AdminSettings = I.AdminSettings or {}
function I.AddAdminSetting(name, kind, a, b)
    for _, s in ipairs(I.AdminSettings) do
        if s[1] == name then return end
    end
    I.AdminSettings[#I.AdminSettings + 1] = { name, kind, a, b }
end

I.AddAdminSetting("advinv_language", "choice", { "en", "fr", "de", "es", "ru" })
I.AddAdminSetting("advinv_death_drop", "int", 0, 3)
I.AddAdminSetting("advinv_death_loot_time", "int", 0, 3600)
I.AddAdminSetting("advinv_death_loot_name", "bool")
I.AddAdminSetting("advinv_death_body_max", "int", 1, 200)
I.AddAdminSetting("advinv_ground_item_time", "int", 0, 86400)
I.AddAdminSetting("advinv_pickup_weapons", "bool")
I.AddAdminSetting("advinv_pickup_any_weapon", "bool")
I.AddAdminSetting("advinv_pickup_entities", "bool")
I.AddAdminSetting("advinv_carry_refuse_gear", "bool")
I.AddAdminSetting("advinv_load_slowdown", "bool")
I.AddAdminSetting("advinv_load_free", "int", 0, 5000)
I.AddAdminSetting("advinv_load_max", "int", 1, 10000)
I.AddAdminSetting("advinv_load_min_speed", "float", 0.1, 1)
I.AddAdminSetting("advinv_darkrp_buy_to_inventory", "bool")
I.AddAdminSetting("advinv_darkrp_loadout_to_inventory", "bool")

function I.AdminSetting(name)
    for _, s in ipairs(I.AdminSettings) do
        if s[1] == name then return s end
    end
end
