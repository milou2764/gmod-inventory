--[[
    Carry modes of long guns: how an equipped long gun that is not in the hands is carried on the
    body (shared rules; the server decides, the client uses the same rules to grey out the menu).

    Modes (network index = position in I.CARRY_MODES):
        sling_up    sling arms: from the right shoulder, muzzle up                zone "shoulder"
        sling_down  back carry: the sling across the chest, the gun flat on the back, butt behind the
                    left shoulder blade, muzzle down (USMC weapons carries, 0300-M16-1004 p. 19)  zone "back"
        front_hang  front carry: hanging in front of the chest                    zone "front"
    A long gun is always carried in one of them: "stowed" (index 6) only means "nothing" internally
    (empty slot) and can never be chosen. Removed modes keep their index (saves and the network keep
    the others' numbers) but have no zone, so no weapon can use them (a weapon saved that way takes
    another mode): "cross_body" (index 3) and "back_carry" (index 4, the old diagonal back carry).

    Rules: one weapon per body zone; worn gear can block zones (ENT.BlocksCarryZones on the item,
    e.g. { back = true } on backpacks) or single modes (ENT.BlocksCarryModes: a backpack leaves only
    sling arms on the back, the back carry is blocked; a weapon carried that
    way moves to the front carry when it goes on); hooks CanChangeCarryMode(ply, item, mode) -> false to forbid,
    OnCarryModeChanged(ply, item, mode, oldMode) after a change. When nothing fits any more (gear or
    a weapon being equipped), I.CarryPlan finds no plan and the change is refused.

    Weapons are configured by weapon class in I.CarryWeapons (other addons can add theirs):
        AdvInv.CarryWeapons["my_rifle"] = { default = "sling_up" }             -- every mode
        AdvInv.CarryWeapons["my_launcher"] = { modes = { "sling_up" }, default = "sling_up" }
    An item can also set ENT.CarryModes / ENT.CarryDefault.
--]]
local I = AdvInv

I.CARRY_MODES = { "sling_up", "sling_down", "cross_body", "back_carry", "front_hang", "stowed" }
I.CARRY_INDEX = {}
for k, m in ipairs(I.CARRY_MODES) do I.CARRY_INDEX[m] = k end
I.CARRY_NET_BITS = 3

I.CarryZone = {
    sling_up = "shoulder", sling_down = "back", front_hang = "front", -- (cross_body, back_carry: removed)
}
-- When a weapon has to move, it tries these modes first, then its other modes.
I.CarryFallback = { "sling_up", "sling_down", "front_hang" }

-- Equipment slots that can hold a long gun (the sidearm keeps its holster).
I.CARRY_CATS = { "PrimaryWep", "RocketLauncher" }

local ALL = { "sling_up", "sling_down", "front_hang" }
I.CarryWeapons = I.CarryWeapons or {}
for class, conf in pairs({
    weapon_smg1 = { modes = ALL, default = "sling_up" },
    weapon_ar2 = { modes = ALL, default = "sling_up" },
    weapon_shotgun = { modes = ALL, default = "sling_up" },
    -- wide: its bow can't hang beside a backpack (limbs in front of the face) nor over it (far off
    -- the back): with a backpack on, only in front
    weapon_crossbow = { modes = ALL, default = "sling_up", wide = true },
    weapon_rpg = { modes = { "sling_up" }, default = "sling_up" },
}) do
    I.CarryWeapons[class] = I.CarryWeapons[class] or conf
end

-- Carry configuration of an item (ID, class of a generic item) (nil: not a long gun with carry
-- modes). A generic weapon of the primary or launcher slot gets every mode (launcher: sling arms);
-- it is placed by the mode's template (cl_carry.lua). Modes that no longer exist (back_carry, in
-- another addon's configuration) are left out.
function I.CarryConfig(id, c)
    local t = id and id > 1 and I.DefTable(id, c)
    if not t then return end
    local base = t.WeaponClass and I.CarryWeapons[t.WeaponClass]
    if not base and not t.CarryModes and t.Generic and t.WeaponClass then
        if t.AdvInvCategory == "PrimaryWep" then
            base = { modes = ALL, default = "sling_up" }
        elseif t.AdvInvCategory == "RocketLauncher" then
            base = { modes = { "sling_up" }, default = "sling_up" }
        end
    end
    if not (base or t.CarryModes) then return end
    local modes = {}
    for _, m in ipairs(t.CarryModes or (base and base.modes) or ALL) do
        if I.CarryZone[m] then modes[#modes + 1] = m end
    end
    if #modes == 0 then modes = { "sling_up" } end
    local default = t.CarryDefault or (base and base.default)
    if not table.HasValue(modes, default) then default = modes[1] end
    return { modes = modes, default = default, weaponClass = t.WeaponClass, wide = t.CarryWide or (base and base.wide) or nil }
end

function I.CarryModeAllowedForWeapon(conf, mode)
    return conf ~= nil and I.CarryZone[mode] ~= nil and table.HasValue(conf.modes, mode)
end

-- Current carry mode of the long gun in slot cat ("stowed" if nothing is set).
function I.CarryMode(ply, cat)
    return I.CARRY_MODES[ply:GetNWInt(cat .. "Carry", I.CARRY_INDEX.stowed)] or "stowed"
end

-- Zones and modes blocked by the gear the player wears: { zone or mode = gear slot }.
function I.BlockedZones(ply, extraID, extraCat)
    local out = {}
    for cat in pairs(AdvInv.GearCat) do
        local id = (cat == extraCat and extraID) or ply:GetNW2Int(cat)
        local t = id and id > 1 and AdvInv.EntityTable(id)
        if t then
            for zone, on in pairs(t.BlocksCarryZones or {}) do
                if on then out[zone] = cat end
            end
            for mode, on in pairs(t.BlocksCarryModes or {}) do
                if on then out[mode] = cat end
            end
        end
    end
    return out
end

-- Is mode blocked by worn gear (blocked: I.BlockedZones)? -> the gear slot, or nil
function I.CarryModeBlocked(blocked, mode)
    return blocked[mode] or blocked[I.CarryZone[mode] or ""]
end

-- "Back occupied by backpack": a phrase for this zone and gear slot if there is one, else generic.
function I.CarryBlockedReason(zone, gearCat)
    local key = "carry_blocked_" .. zone .. "_" .. gearCat
    local s = I.L(key)
    if s ~= key then return s end
    return I.L("carry_blocked", I.L("zone_" .. zone), string.lower(I.SlotLabels[gearCat] or gearCat))
end

-- Item table given to the hooks for the long gun in slot cat.
function I.CarryItem(ply, cat)
    local id, c = I.SlotRef(ply, cat)
    return { id = id, c = c, cat = cat, m = I.CarryMode(ply, cat) }
end

-- Item of slot cat: from the overrides (an ID or an item table) or what ply wears. -> id, class
local function ref(ply, cat, ids)
    local v = ids and ids[cat]
    if istable(v) then return v.id, v.c end
    if v then return v, nil end
    return I.SlotRef(ply, cat)
end

--[[
    Can ply carry the long gun of slot cat in mode? -> true, or false and a reason (text in the
    server's language). Optional overrides, to try a change before making it:
        blocked  zones taken by gear (I.BlockedZones with the gear being equipped)
        others   slot -> mode of the other long guns ("stowed": none)
        ids      slot -> item (table, or an ID: a weapon being equipped, 1 for a slot being emptied)
--]]
function I.CarryAllowed(ply, cat, mode, blocked, others, ids)
    local id, c = ref(ply, cat, ids)
    local conf = I.CarryConfig(id, c)
    if not I.CarryModeAllowedForWeapon(conf, mode) then return false, I.L("carry_not_weapon") end
    local zone = I.CarryZone[mode]
    blocked = blocked or I.BlockedZones(ply)
    if blocked[zone] then return false, I.CarryBlockedReason(zone, blocked[zone]) end
    local function modeBlocked(gear)
        local key = "carry_blocked_mode_" .. gear -- "...: not possible with a backpack on"
        local s = I.L(key, I.L("carry_" .. mode))
        if s == key then
            s = I.L("carry_blocked_mode", I.L("carry_" .. mode), string.lower(I.SlotLabels[gear] or gear))
        end
        return false, s
    end
    if blocked[mode] then return modeBlocked(blocked[mode]) end
    -- a wide weapon (conf.wide: a crossbow) with gear on the back: only in front
    if conf.wide and blocked.back and zone ~= "front" then return modeBlocked(blocked.back) end
    for _, other in ipairs(I.CARRY_CATS) do
        local oid, oc = ref(ply, other, ids)
        if other ~= cat and oid > 1 and I.CarryConfig(oid, oc) then
            local om = (others and others[other]) or I.CarryMode(ply, other)
            if I.CarryZone[om] == zone then
                return false, I.L("carry_zone_used_" .. zone, I.Info(oid, oc).name)
            end
        end
    end
    local item = { id = id, c = c, cat = cat, m = I.CarryMode(ply, cat) }
    if hook.Run("CanChangeCarryMode", ply, item, mode) == false then
        return false, I.L("carry_refused")
    end
    return true
end

-- Modes to try for a weapon, best first: the wanted one, then I.CarryFallback, then its others; a
-- weapon whose mode worn gear blocks (a backpack) goes to the front carry first.
I.CarryGearFallback = I.CarryGearFallback or "front_hang"
local function candidates(conf, want, gearBlocked)
    local out, seen = {}, {}
    local function add(m)
        if not seen[m] and I.CarryModeAllowedForWeapon(conf, m) then
            seen[m] = true
            out[#out + 1] = m
        end
    end
    if want then add(want) end
    if gearBlocked and I.CarryGearFallback then add(I.CarryGearFallback) end
    for _, m in ipairs(I.CarryFallback) do add(m) end
    for _, m in ipairs(conf.modes) do add(m) end
    return out
end

--[[
    A carry mode for every long gun of ply that respects every rule: { slot = mode }, or nil when
    there is none (then the change being tried must be refused). Weapons keep their mode when they
    can; the slot that just changed (opts.newCat) gives way to the others first, then slot order.
    opts (all optional): ids / blocked as in I.CarryAllowed, want = { slot = mode wanted }, newCat.
--]]
function I.CarryPlan(ply, opts)
    opts = opts or {}
    local ids = opts.ids or {}
    local blocked = opts.blocked or I.BlockedZones(ply)
    -- order: weapons whose mode is still possible on its own (they keep it), then the ones that
    -- must move, then the slot that just changed
    local keepers, movers, last = {}, {}, {}
    local cands = {}
    local none = {}
    for _, c in ipairs(I.CARRY_CATS) do none[c] = "stowed" end
    for _, cat in ipairs(I.CARRY_CATS) do
        local id, c = ref(ply, cat, ids)
        local conf = id > 1 and I.CarryConfig(id, c)
        if conf then
            local want = (opts.want and opts.want[cat]) or I.CarryMode(ply, cat)
            cands[cat] = candidates(conf, want, I.CarryModeBlocked(blocked, want) ~= nil)
            if cat == opts.newCat then
                last[1] = cat
            elseif I.CarryAllowed(ply, cat, want, blocked, none, ids) then
                keepers[#keepers + 1] = cat
            else
                movers[#movers + 1] = cat
            end
        end
    end
    local order = {}
    for _, list in ipairs({ keepers, movers, last }) do
        for _, cat in ipairs(list) do order[#order + 1] = cat end
    end
    local plan = {}
    local function others(cat)
        local o = {}
        for _, c in ipairs(I.CARRY_CATS) do
            if c ~= cat then o[c] = plan[c] or "stowed" end
        end
        return o
    end
    local function search(k)
        local cat = order[k]
        if not cat then return true end
        for _, m in ipairs(cands[cat]) do
            if I.CarryAllowed(ply, cat, m, blocked, others(cat), ids) then
                plan[cat] = m
                if search(k + 1) then return true end
                plan[cat] = nil
            end
        end
        return false
    end
    if search(1) then return plan end
end
