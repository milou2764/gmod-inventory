-- Touche d'ouverture de l'inventaire, enregistrée dans data/advinv/keybinds.txt.
local KEYBINDS_FILE = "advinv/keybinds.txt"

AdvInv.keybinds = AdvInv.keybinds or {}

if AdvInv.keybinds.inventory == nil then
    local saved = file.Read(KEYBINDS_FILE, "DATA")
    local tab = saved and util.JSONToTable(saved)
    if tab and tab.inventory then
        AdvInv.keybinds.inventory = tab.inventory
    end
end

function AdvInv.InventoryKey()
    return (AdvInv.keybinds and AdvInv.keybinds.inventory) or KEY_I
end

hook.Add("PopulateToolMenu", "AdvInv_Keybind", function()
    spawnmenu.AddToolMenuOption(
        "Options",
        "Advanced Inventory",
        "advinv_keybind",
        AdvInv.L("options_title"),
        "",
        "",
        function(panel)
            panel:ClearControls()
            panel:Help(AdvInv.L("options_key"))
            local binder = vgui.Create("AdvInvBinder")
            binder:SetValue(AdvInv.InventoryKey())
            binder.OnChange = function(_, val)
                AdvInv.keybinds = AdvInv.keybinds or {}
                AdvInv.keybinds.inventory = val
                file.CreateDir("advinv")
                file.Write(KEYBINDS_FILE, util.TableToJSON(AdvInv.keybinds))
            end
            panel:AddItem(binder)
        end
    )
end)
