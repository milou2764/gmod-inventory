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
local function releaseSlot(ply, cat)
    ply:SetNWInt(cat .. "Carry", I.CARRY_INDEX.stowed)
    ply:SetNWString(cat .. "Class", "")
    ply:SetNWInt(cat, 1)
    ply:SetNWInt(cat .. "Rounds", 0)
    I.MarkDirty(ply, "Uniform")
end

hook.Add("canDropWeapon", "AdvInv_DarkRP", function(ply, wep)
    if not IsValid(wep) then return end
    for _, cat in ipairs(AdvInv.WeaponCat) do
        local info = I.SlotInfo(ply, cat)
        if info.weaponClass and info.weaponClass == wep:GetClass() then
            if not ply:Alive() then return false end -- dying: the belongings bag has it
            releaseSlot(ply, cat)
            return
        end
    end
end)

hook.Add("PlayerLoadout", "AdvInv_DarkRP", function(ply)
    if not (isDarkRP() and loadoutInv:GetBool()) then return end
    timer.Simple(0.2, function()
        if not (IsValid(ply) and ply:Alive()) then return end
        for _, wep in ipairs(ply:GetWeapons()) do
            local item = I.ItemForWeaponClass(wep:GetClass(), math.max(wep:Clip1(), 0))
            if item then
                local cat = I.Info(item.id, item.c).cat
                if cat and I.SlotID(ply, cat) <= 1 then I.Equip(ply, item) end
            end
        end
    end)
end)

net.Receive("advinv_drop_money", function(_, ply)
    local amount = math.floor(net.ReadUInt(32))
    if not (isDarkRP() and ply:Alive() and amount > 0) then return end
    if (ply.AdvInvMoneyWait or 0) > CurTime() then return end
    ply.AdvInvMoneyWait = CurTime() + 1
    if not (ply.canAfford and ply:canAfford(amount)) then
        I.Tell(ply, I.L("money_cannot"))
        return
    end
    ply:addMoney(-amount)
    DarkRP.createMoneyBag(I.DropPos(ply), amount)
end)
