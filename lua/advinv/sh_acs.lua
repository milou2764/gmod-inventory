--[[
    Advanced Crafting System (Workshop 3017902884 and its copies; global AdvancedCraftingSystem):
    its resources become an inventory item, bags of resources (advinv_acs_resources, a box of the
    ammo type below: a bag holds ENT.Capacity resources and weighs ENT.Mass points). Its workbench,
    resource boxes, scrapper and commands read and change the bags the player carries (sv_acs.lua).
    Its tools and its box of crafted things are never inventory weapons (sh_generic.lua).
    Only when that addon is installed: nothing is registered without it.
--]]
local I = AdvInv

I.ACS_CLASS = "advinv_acs_resources"
I.ACS_AMMO = "advinv_acs_resources"

hook.Add("Initialize", "AdvInv_ACS", function()
    if not istable(AdvancedCraftingSystem) then return end
    I.ACSActive = true
    -- (an ammo type: the inventory's boxes count, split, stack and save it like rounds)
    game.AddAmmoType({ name = I.ACS_AMMO, dmgtype = DMG_GENERIC, tracer = TRACER_NONE, maxcarry = 999999 })
    if CLIENT then language.Add(I.ACS_AMMO .. "_ammo", I.L and I.L("acs_resources") or "Crafting resources") end
    I.Items = I.Items or {}
    I.Items[I.ACS_CLASS] = true
    local stored = scripted_ents.GetStored(I.ACS_CLASS)
    if stored and stored.t then stored.t.Spawnable = true end
end)
