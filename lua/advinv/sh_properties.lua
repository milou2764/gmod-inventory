-- Context menu (C): "Inventory" on a crate or vehicle within reach. (A name of our own: properties
-- with the same name replace each other, and "chest" is a common one.)
properties.Add("advinv_open_storage", {
    MenuLabel = AdvInv.L("property_inventory"),
    Order = 9999,
    MenuIcon = "icon16/application_form_edit.png",
    Filter = function(_, ent, ply)
        return AdvInv.IsStorage(ent) and ply:GetPos():Distance(ent:GetPos()) < AdvInv.Config.UseDistance + 100
    end,
    Action = function(_, ent)
        -- as the Use key: the server opens it, or asks for its code (sv_storage.lua)
        net.Start("advinv_storage_use")
        net.WriteEntity(ent)
        net.SendToServer()
    end,
    Receive = function() end,
})
