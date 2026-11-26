util.AddNetworkString("advinv_gear_follow")
util.AddNetworkString("advinv_gear_playerspawn")
util.AddNetworkString("advinv_gear_drop")
util.AddNetworkString("advinv_gear_mnt")
util.AddNetworkString("advinv_gear_umnt")
util.AddNetworkString("advinv_gear_dndrp_mnt")
util.AddNetworkString("advinv_gear_dndrp_umnt")
util.AddNetworkString("advinv_gear_vis")

hook.Add(
    "InitPostEntity",
    "AdvInv_CloakHook",
    function()
        -- Cache l'équipement des joueurs rendus invisibles par ULX (si ULib est installé).
        if not (ULib and ULib.invisible) then return end
        local oldInvis = ULib.invisible
        ULib.invisible = function(ply, bool, vis)
            if not ply:IsValid() then return end -- This is called on a timer so we need to verify they're still connected
            net.Start("advinv_gear_vis")
            net.WriteEntity(ply)
            net.WriteBool(bool)
            net.WriteInt(vis or 0, 8)
            net.Broadcast()

            oldInvis(ply, bool, vis)
        end
    end
)

hook.Add("PlayerSpawn", "AdvInv_Gear_PlayerSpawn", function(ply)
    -- Player is not alive right away and there is no better hook
    -- PlayerSetModel does not work either
    timer.Simple(3, function()
        net.Start("advinv_gear_playerspawn")
        net.WriteEntity(ply)
        net.Broadcast()
    end)
end)

-- Équiper, retirer et déposer passent par les actions vérifiées de sv_containers.lua :
-- les anciens messages advinv_gear_drop / advinv_gear_dndrp_* (qui faisaient confiance au client)
-- ne sont plus écoutés.

--[[
    Armour by body part: a worn item with ENT.Armor protects the body parts it covers, wears down
    as it is hit and lets more damage through as it does. Covered parts: ENT.ArmorHitgroups on the
    item, else AdvInv.ArmorZones of its slot (helmet: head; vest: chest and stomach;
    uniform: body, arms and legs; gas mask: head). The first item with armour left takes the hit.
--]]
AdvInv.ArmorZones = AdvInv.ArmorZones or {
    Helmet = { HITGROUP_HEAD },
    Gasmask = { HITGROUP_HEAD },
    Vest = { HITGROUP_CHEST, HITGROUP_STOMACH },
    Uniform = { HITGROUP_CHEST, HITGROUP_STOMACH, HITGROUP_LEFTARM, HITGROUP_RIGHTARM, HITGROUP_LEFTLEG, HITGROUP_RIGHTLEG },
}
local ARMOR_ORDER = { "Helmet", "Gasmask", "Vest", "Uniform", "Rucksack", "NVGs", "Radio" }

hook.Add("ScalePlayerDamage", "AdvInv_Gear_SPD", function(ply, hitgroup, dmginfo)
    for _, cat in ipairs(ARMOR_ORDER) do
        local id = AdvInv.GearCat[cat] and ply:GetNW2Int(cat) or 1
        local t = id > 1 and AdvInv.EntityTable(id)
        local base = t and t.Armor
        if base and base > 0 then
            local zones = t.ArmorHitgroups or AdvInv.ArmorZones[cat]
            -- the pellets of one shot come one by one before the damage is taken: each one wears
            -- what the previous ones left (else all read the unworn armor and only the last one's
            -- wear was kept: a shotgun barely hurt through armor and barely wore it)
            local now = engine.TickCount()
            local wear = ply.AdvInvArmorWear
            if not (wear and wear.tick == now and wear.cats) then
                wear = { tick = now, cats = {} }
                ply.AdvInvArmorWear = wear
            end
            local left = wear.cats[cat] or ply:GetNWInt(cat .. "Armor")
            if zones and left > 0 and table.HasValue(zones, hitgroup) then
                local newArmor = math.Clamp(math.floor(left - dmginfo:GetDamage()), 0, base)
                -- worn once the damage is really taken (not blocked later: god mode, safe zone...)
                wear.cats[cat] = newArmor
                dmginfo:ScaleDamage(1 - newArmor / base)
                return
            end
        end
    end
end)

hook.Add("PostEntityTakeDamage", "AdvInv_Gear_Wear", function(ent, _, took)
    local w = ent.AdvInvArmorWear
    if not w then return end
    ent.AdvInvArmorWear = nil
    if took and w.tick == engine.TickCount() and ent:IsPlayer() then
        for cat, armor in pairs(w.cats or {}) do ent:SetNWInt(cat .. "Armor", armor) end
    end
end)



