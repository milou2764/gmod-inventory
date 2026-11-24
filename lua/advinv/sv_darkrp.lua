--[[
    DarkRP integration (only does something under DarkRP).

    - What is bought from the F4 menu (entities, weapons, ammo) goes straight into the inventory
      when there is room (advinv_darkrp_buy_to_inventory 1); shipments stay as they are, and the
      weapons they give are taken with Use like any weapon lying around.
    - /drop on a weapon of the inventory: DarkRP drops it as usual and its slot is freed (no copy
      left in the inventory). DarkRP's drop on death doesn't drop inventory weapons (the
      dead player's body has them, sv_death.lua).
    - Money: "Drop money" in the inventory (wallet amount checked here).
    - advinv_darkrp_loadout_to_inventory 1: the job's weapons that fit a free slot become inventory
      weapons (shown on the body, carry modes, dropped on death). Off by default: with death drops
      on, every respawn would give new ones to drop.
--]]
local I = AdvInv
local FLAGS = { FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED }

local buyInv = CreateConVar("advinv_darkrp_buy_to_inventory", "1", FLAGS, "DarkRP: what is bought goes into the inventory", 0, 1)
local loadoutInv = CreateConVar("advinv_darkrp_loadout_to_inventory", "0", FLAGS, "DarkRP: job weapons become inventory weapons", 0, 1)

util.AddNetworkString("advinv_drop_money")

local function isDarkRP() return DarkRP ~= nil end

-- An entity into ply's inventory: equipped if its slot is free, else stored.
local function intoInventory(ply, ent)
    local item = I.ItemFromEntity(ent)
    if not item then return false end
    local info = I.Info(item.id, item.c)
    if info.cat and (info.isWeapon or AdvInv.GearCat[info.cat]) and I.SlotID(ply, info.cat) <= 1 then
        if I.Equip(ply, item, ent.AdvInvContents) then
            I.TakeFromGround(ent, 1)
            return true
        end
    end
    return I.PickupEntity(ply, ent)
end
I.IntoInventory = intoInventory

local function bought(ply, _, ent)
    if not (buyInv:GetBool() and IsValid(ent)) then return end
    timer.Simple(0, function()
        if IsValid(ent) and IsValid(ply) and ply:Alive() then intoInventory(ply, ent) end
    end)
end
hook.Add("playerBoughtCustomEntity", "AdvInv_DarkRP", bought)
hook.Add("playerBoughtPistol", "AdvInv_DarkRP", bought)
hook.Add("playerBoughtAmmo", "AdvInv_DarkRP", bought)

-- Frees a weapon slot without taking the weapon away (DarkRP drops it itself).
local function releaseSlot(ply, cat) I.ReleaseSlot(ply, cat) end

local function slotOf(ply, class)
    for _, cat in ipairs(AdvInv.WeaponCat) do
        if I.SlotInfo(ply, cat).weaponClass == class then return cat end
    end
end

-- Dying: the body has the inventory's weapons (sv_death.lua), DarkRP doesn't drop them.
hook.Add("canDropWeapon", "AdvInv_DarkRP", function(ply, wep)
    if IsValid(wep) and not ply:Alive() and slotOf(ply, wep:GetClass()) then return false end
end)

-- /drop: once DarkRP has dropped it, the slot is free; the dropped weapon keeps its attachments and
-- carry mode, but not the reserve (it is the boxes, which stay in the inventory).
hook.Add("onDarkRPWeaponDropped", "AdvInv_DarkRP", function(ply, ent, wep)
    if not (IsValid(ply) and IsValid(ent)) then return end
    ent.ammoadd = 0
    local cat = IsValid(wep) and slotOf(ply, wep:GetClass())
    if cat then
        ent.AdvInvExtra = I.WeaponExtra(wep)
        if I.CarryConfig(I.SlotRef(ply, cat)) then ent.AdvInvCarryMode = ply:GetNWInt(cat .. "Carry", 0) end
        releaseSlot(ply, cat)
    end
end)

-- The weapon checker confiscates: the inventory's weapons leave their slots (given back later as
-- ordinary weapons by DarkRP).
hook.Add("playerWeaponsConfiscated", "AdvInv_DarkRP", function(_, target, list)
    if not (IsValid(target) and istable(list)) then return end
    for class in pairs(list) do
        local cat = isstring(class) and slotOf(target, class)
        if cat then releaseSlot(target, cat) end
    end
end)

-- DarkRP's drop takes the reserve away (RemoveAmmo): guarded, the boxes stay.
hook.Add("InitPostEntity", "AdvInv_DarkRPDrop", function()
    local meta = FindMetaTable("Player")
    local orig = meta.AdvInvOrigDrop or meta.dropDRPWeapon
    if not orig then return end
    meta.AdvInvOrigDrop = orig
    meta.dropDRPWeapon = function(ply, ...)
        if IsValid(ply) then I.GuardAmmo(ply) end
        local r = { orig(ply, ...) }
        if IsValid(ply) then I.MarkDirty(ply, "Uniform") end
        return unpack(r)
    end
end)

-- advinv_darkrp_loadout_to_inventory: the job's own weapons (its F4 list, not what every job or
-- other addons give) that fit a free slot become inventory weapons, marked as the job's: they go
-- when the player changes job or dies, and are never saved (sv_inventory.lua).
hook.Add("PlayerLoadout", "AdvInv_DarkRP", function(ply)
    if not (isDarkRP() and loadoutInv:GetBool()) then return end
    timer.Simple(0.2, function()
        if not (IsValid(ply) and ply:Alive()) then return end
        local job = ply.getJobTable and ply:getJobTable()
        local own = {}
        for _, class in ipairs(job and istable(job.weapons) and job.weapons or {}) do own[string.lower(class)] = true end
        for _, wep in ipairs(ply:GetWeapons()) do
            if own[string.lower(wep:GetClass())] then
                local item = I.ItemForWeaponClass(wep:GetClass(), math.max(wep:Clip1(), 0))
                if item then
                    local cat = I.Info(item.id, item.c).cat
                    if cat and I.SlotID(ply, cat) <= 1 then
                        item.j = true
                        I.Equip(ply, item)
                    end
                end
            end
        end
    end)
end)

-- Leaving a job: its weapons stay with it (DarkRP calls this before its strip and new loadout).
hook.Add("OnPlayerChangedTeam", "AdvInv_JobItems", function(ply)
    if IsValid(ply) then I.RemoveJobItems(ply) end
end)

net.Receive("advinv_drop_money", function(_, ply)
    local amount = math.floor(net.ReadUInt(32))
    if not (isDarkRP() and ply:Alive() and amount > 0) then return end
    if (ply.AdvInvMoneyWait or 0) > CurTime() then return end
    ply.AdvInvMoneyWait = CurTime() + 1
    -- DarkRP's own /dropmoney: its pile limit, placement, hooks and logs
    local cmd = DarkRP.getChatCommand and DarkRP.getChatCommand("dropmoney")
    if cmd and isfunction(cmd.callback) then
        cmd.callback(ply, tostring(amount))
        return
    end
    if not (ply.canAfford and ply:canAfford(amount)) then
        I.Tell(ply, I.L("money_cannot"))
        return
    end
    local bags = {}
    for _, b in ipairs(ply.AdvInvMoneyBags or {}) do if IsValid(b) then bags[#bags + 1] = b end end
    ply.AdvInvMoneyBags = bags
    if #bags >= ((GAMEMODE.Config and GAMEMODE.Config.maxMoneyPiles) or 20) then
        I.Tell(ply, I.L("money_cannot"))
        return
    end
    ply:addMoney(-amount)
    bags[#bags + 1] = DarkRP.createMoneyBag(I.DropPos(ply), amount)
    hook.Run("playerDroppedMoney", ply, amount, bags[#bags])
end)

--[[
    Job isolation (military or Star Wars RP, where a job is another character): switching into or
    out of an isolated job forgets the inventory (gear, slot weapons, pockets, munitions); the new
    job starts empty.
        advinv_job_isolation 1     every job is isolated (except the jobs with AdvInvIsolated = false)
        advinv_isolated_jobs "a,b" else only these jobs (commands or names, comma separated), and the
                                   jobs with AdvInvIsolated = true in their DarkRP.createJob table
    Hook AdvInv_JobIsolation(ply, oldTeam, newTeam): false keeps the inventory, true forgets it.
--]]
local isoAll = CreateConVar("advinv_job_isolation", "0", { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Every job keeps its own inventory: changing job forgets it (0: only advinv_isolated_jobs)", 0, 1)
local isoList = CreateConVar("advinv_isolated_jobs", "", { FCVAR_ARCHIVE },
    "Jobs whose inventory is forgotten when changing job: commands or names, comma separated")

-- Is this DarkRP team an isolated job?
function I.JobIsolated(t)
    local job = RPExtraTeams and RPExtraTeams[t]
    if not job then return false end
    if job.AdvInvIsolated ~= nil then return job.AdvInvIsolated == true end
    if isoAll:GetBool() then return true end
    local cmd, name = string.lower(job.command or ""), string.lower(job.name or "")
    for raw in string.gmatch(string.lower(isoList:GetString()), "[^,]+") do
        local entry = string.Trim(raw)
        if entry ~= "" and (entry == cmd or entry == name) then return true end
    end
    return false
end

-- Called by DarkRP before it strips the weapons and gives the new loadout.
hook.Add("OnPlayerChangedTeam", "AdvInv_JobIsolation", function(ply, before, after)
    if not (IsValid(ply) and before ~= after and RPExtraTeams and RPExtraTeams[before]) then return end -- (joining: no job before)
    local h = hook.Run("AdvInv_JobIsolation", ply, before, after)
    if h == false then return end
    if h ~= true and not (I.JobIsolated(before) or I.JobIsolated(after)) then return end
    I.Clear(ply)
    ply.AdvInvUnknown = nil -- items of missing addons too
    I.MarkAllDirty(ply)
    I.Tell(ply, I.L("msg_job_isolated"))
    hook.Run("AdvInv_JobInventoryForgotten", ply, before, after)
end)

