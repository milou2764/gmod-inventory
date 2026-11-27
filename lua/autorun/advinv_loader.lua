-- Advanced Inventory System : inventaire façon Arma 3 (tenue, gilet, sac, casque, armes), à capacité.
-- Ce fichier charge les modules de lua/advinv/ dans un ordre fixe.
AdvInv = AdvInv or {}

local files = {
    "sh_log.lua",
    "sh_config.lua",
    "sh_lang.lua",
    "sh_lang_more.lua",
    "sh_items.lua",
    "sh_containers.lua",
    "sh_generic.lua",
    "sh_compat_data.lua",
    "sh_compat.lua",
    "sh_modelgear.lua",
    "sh_modelgear_items.lua",
    "sh_carry.lua",
    "sh_admin.lua",
    "sh_use.lua",
    "sh_grenades.lua",
    "sh_arccw.lua",
    "sh_acs.lua",
    "sh_search.lua",
    "sh_storage.lua",
    "sh_craft.lua",
    "sh_load.lua",
    "sh_meta.lua",
    "sh_properties.lua",
    "sv_database.lua",
    "sv_containers.lua",
    "sv_carry.lua",
    "sv_death.lua",
    "sv_generic.lua",
    "sv_cw2.lua",
    "sv_sandswep.lua",
    "sv_arccw.lua",
    "sv_acs.lua",
    "sv_admin.lua",
    "sv_use.lua",
    "sv_grenades.lua",
    "sv_search.lua",
    "sv_storage.lua",
    "sv_darkrp.lua",
    "sv_craft.lua",
    "sv_extra.lua",
    "sv_meta.lua",
    "sv_inventory.lua",
    "sv_gear.lua",
    "sv_modelgear.lua",
    "cl_keybinds.lua",
    "cl_vgui.lua",
    "cl_bodyfit_data.lua",
    "cl_bodyfit.lua",
    "cl_fits_data.lua",
    "cl_fits_compat.lua",
    "cl_gear.lua",
    "cl_weapons.lua",
    "cl_gearicon.lua",
    "cl_carry_data.lua",
    "cl_vest_back.lua",
    "cl_carry.lua",
    "cl_carry_tools.lua",
    "cl_attach_editor.lua",
    "cl_admin.lua",
    "cl_search.lua",
    "cl_storage.lua",
    "cl_ground.lua",
    "cl_death.lua",
    "cl_craft.lua",
    "cl_extra.lua",
    "cl_inventory.lua",
}

for _, name in ipairs(files) do
    local path = "advinv/" .. name
    local prefix = string.sub(name, 1, 3)

    if prefix == "sv_" then
        if SERVER then include(path) end
    elseif prefix == "cl_" then
        if SERVER then
            AddCSLuaFile(path)
        else
            include(path)
        end
    else
        if SERVER then AddCSLuaFile(path) end
        include(path)
    end
end
