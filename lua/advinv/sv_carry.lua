--[[
    Carry modes, server side (rules in sh_carry.lua). The server decides every change: requests
    from the menu (validated, forged ones refused), and checks after spawn, inventory load,
    equipment changes and pickups.

    Gear that blocks the zone of a carried weapon (a backpack on the back...):
        advinv_carry_refuse_gear 0   the weapon moves to another possible mode (default), the
                                   player is told
        advinv_carry_refuse_gear 1   the gear cannot be equipped while the weapon uses that zone
    Long guns are never stowed: gear or a weapon that would leave one with no possible mode is
    refused.
--]]
local I = AdvInv

local refuseGear = CreateConVar("advinv_carry_refuse_gear", "0", { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Refuse gear that blocks the body zone of a carried weapon (0: move the weapon instead)", 0, 1)

local function hasCarry(ply, cat)
    local id, c = I.SlotRef(ply, cat)
    return id > 1 and I.CarryConfig(id, c) ~= nil
end

local function setMode(ply, cat, mode, notify)
    local old = I.CarryMode(ply, cat)
    ply:SetNWInt(cat .. "Carry", I.CARRY_INDEX[mode])
    if old == mode then return end
    hook.Run("OnCarryModeChanged", ply, I.CarryItem(ply, cat), mode, old)
    if notify then
        I.Tell(ply, I.L("carry_moved", I.SlotInfo(ply, cat).name, I.L("carry_" .. mode)))
    end
end

--[[
    Makes every carried long gun legal (I.CarryPlan): weapons keep their mode when they can, the
    others move to a possible one, the slot that just changed (newCat) giving way first. notify:
    tell the player what moved. If no plan exists (only after a config change: equipping is
    refused before that can happen), modes are left as they are, a missing one set to the default.
--]]
function I.ValidateCarry(ply, notify, newCat)
    if not IsValid(ply) then return end
    local plan = I.CarryPlan(ply, { newCat = newCat })
    for _, cat in ipairs(I.CARRY_CATS) do
        local conf = hasCarry(ply, cat) and I.CarryConfig(I.SlotRef(ply, cat))
        if not conf then
            if ply:GetNWInt(cat .. "Carry", 0) ~= I.CARRY_INDEX.stowed then
                ply:SetNWInt(cat .. "Carry", I.CARRY_INDEX.stowed)
            end
        elseif plan then
            setMode(ply, cat, plan[cat], notify)
        elseif not I.CarryModeAllowedForWeapon(conf, I.CarryMode(ply, cat)) then
            setMode(ply, cat, conf.default, false)
        end
    end
end

-- A long gun just put in slot cat: its saved mode (item.m) or the weapon's default; then checked
-- with I.ValidateCarry.
function I.CarryOnEquip(ply, cat, item)
    local conf = I.CarryConfig(item.id, item.c)
    if not conf then return end
    local wanted = I.CARRY_MODES[item.m or 0]
    if not I.CarryModeAllowedForWeapon(conf, wanted) then wanted = conf.default end
    ply:SetNWInt(cat .. "Carry", I.CARRY_INDEX[wanted])
end

-- Can the long gun item (an ID) go into slot cat (empty, or about to be emptied)? Some carry mode
-- must be left for it and for the other long guns. -> true, or false and the reason.
function I.CarryEquipCheck(ply, cat, item)
    if not I.CarryConfig(item.id, item.c) then return true end
    if I.CarryPlan(ply, { ids = { [cat] = item }, newCat = cat }) then return true end
    return false, I.L("carry_no_room", I.Info(item.id, item.c).name)
end

-- Gear about to be equipped in gearCat: refused if it leaves a long gun with no possible mode, or
-- (advinv_carry_refuse_gear 1) if it blocks the zone a carried weapon uses. -> true, or false and
-- the reason.
function I.CarryGearCheck(ply, id, gearCat)
    local blocked = I.BlockedZones(ply, id, gearCat)
    for _, cat in ipairs(I.CARRY_CATS) do
        if hasCarry(ply, cat) then
            local mode = I.CarryMode(ply, cat)
            if refuseGear:GetBool() and I.CarryModeBlocked(blocked, mode) == gearCat then
                return false, I.L("carry_gear_refused", I.SlotInfo(ply, cat).name, I.L("carry_" .. mode))
            end
        end
    end
    if I.CarryPlan(ply, { blocked = blocked }) then return true end
    for _, cat in ipairs(I.CARRY_CATS) do -- name a weapon that loses its place
        if hasCarry(ply, cat) and I.CarryModeBlocked(blocked, I.CarryMode(ply, cat)) then
            return false, I.L("carry_gear_no_room", I.SlotInfo(ply, cat).name)
        end
    end
    return false, I.L("carry_gear_no_room", "?")
end

-- Request from the menu (action ACT.CARRY): validated like everything else ("stowed" is refused
-- by I.CarryAllowed: it is no mode for a long gun).
function I.RequestCarryMode(ply, cat, mode)
    if not (cat and mode and table.HasValue(I.CARRY_CATS, cat) and I.CARRY_INDEX[mode]) then return false end
    if not hasCarry(ply, cat) then return false end
    local ok, why = I.CarryAllowed(ply, cat, mode)
    if not ok then return false, why end
    setMode(ply, cat, mode, false)
    return true
end

hook.Add("PlayerSpawn", "AdvInv_CarryValidate", function(ply)
    timer.Simple(0, function() I.ValidateCarry(ply, false) end)
end)
