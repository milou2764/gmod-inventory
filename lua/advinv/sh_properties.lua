-- Context menu (C): "Inventory" on a crate or vehicle within reach.
properties.Add("chest", {
    MenuLabel = AdvInv.L("property_inventory"),
    Order = 9999,
    MenuIcon = "icon16/application_form_edit.png",
    Filter = function(_, ent, ply)
        return AdvInv.IsStorage(ent) and ply:GetPos():Distance(ent:GetPos()) < AdvInv.Config.UseDistance + 100
    end,
    Action = function(_, ent)
        AdvInv.OpenStorage(ent)
    end,
    Receive = function() end,
})
