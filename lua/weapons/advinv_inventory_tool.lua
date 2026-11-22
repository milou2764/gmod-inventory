--[[
    Inventory tool (optional, for servers that give it): left click opens the inventory, right
    click takes the item looked at (like the Use key).
--]]
AddCSLuaFile()
SWEP.PrintName = AdvInv and AdvInv.T("Inventory", "Inventaire") or "Inventory"
SWEP.Category = AdvInv.T("Inventory", "Inventaire")
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 5
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = ""
SWEP.UseHands = true
SWEP.DrawAmmo = false
SWEP.HoldType = "normal"
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

function SWEP:Initialize()
    self:SetHoldType("normal")
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.5)
    if CLIENT and IsFirstTimePredicted() and AdvInv.OpenInventory then AdvInv.OpenInventory() end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.5)
    if SERVER then
        local owner = self:GetOwner()
        if IsValid(owner) and AdvInv.PickupLooked then AdvInv.PickupLooked(owner) end
    end
end

function SWEP:DrawWorldModel() end
